import Foundation
import CircuiteFoundation
import DesignFlowKernel

public struct XcircuiteSymbolicPlannerPlanImporter: Sendable {
    private let workspaceStore: XcircuiteWorkspaceStore
    private let artifactStore: XcircuitePlanningArtifactStore
    private let artifactVerifier: LocalArtifactVerifier

    public init(
        workspaceStore: XcircuiteWorkspaceStore = XcircuiteWorkspaceStore(),
        artifactStore: XcircuitePlanningArtifactStore = XcircuitePlanningArtifactStore(),
        artifactVerifier: LocalArtifactVerifier = LocalArtifactVerifier()
    ) {
        self.workspaceStore = workspaceStore
        self.artifactStore = artifactStore
        self.artifactVerifier = artifactVerifier
    }

    public func importSolverPlan(
        request: XcircuiteSymbolicPlannerPlanImportRequest,
        projectRoot: URL
    ) throws -> XcircuiteSymbolicPlannerPlanImportResult {
        try XcircuiteIdentifierValidator().validate(request.runID, kind: .runID)
        let manifest = try loadRunManifest(runID: request.runID, projectRoot: projectRoot)
        let problemPath = try requiredProblemPath(
            explicitPath: request.problemPath,
            artifactID: request.problemArtifactID ?? XcircuitePlanningArtifactStore.problemArtifactID,
            manifest: manifest,
            runID: request.runID,
            projectRoot: projectRoot
        )
        let problem = try workspaceStore.readJSON(
            XcircuiteCircuitPlanningProblem.self,
            from: workspaceStore.url(forProjectRelativePath: problemPath, inProjectAt: projectRoot)
        )
        guard problem.runID == request.runID else {
            throw XcircuiteSymbolicPlannerPlanImportError.runMismatch(
                expected: request.runID,
                actual: problem.runID
            )
        }

        let pddlExportRef = try pddlExportReference(
            explicitPath: request.pddlExportPath,
            artifactID: request.pddlExportArtifactID ?? XcircuitePlanningArtifactStore.symbolicPlannerPDDLExportArtifactID,
            manifest: manifest,
            runID: request.runID,
            projectRoot: projectRoot
        )
        let pddlExport = try workspaceStore.readJSON(
            XcircuiteSymbolicPlannerPDDLExport.self,
            from: workspaceStore.url(forProjectRelativePath: pddlExportRef.path, inProjectAt: projectRoot)
        )
        guard pddlExport.runID == request.runID else {
            throw XcircuiteSymbolicPlannerPlanImportError.runMismatch(
                expected: request.runID,
                actual: pddlExport.runID
            )
        }
        guard pddlExport.problemID == problem.problemID else {
            throw XcircuiteSymbolicPlannerPlanImportError.runMismatch(
                expected: problem.problemID,
                actual: pddlExport.problemID
            )
        }

        let solverPlanText = try loadSolverPlanText(
            request: request,
            manifest: manifest,
            projectRoot: projectRoot
        )
        let solverPlanArtifact = try foundationArtifact(
            artifactStore.persistSymbolicPlannerSolverPlan(
                solverPlanText,
                runID: request.runID,
                projectRoot: projectRoot
            ),
            field: "solver-plan"
        )
        let draft = makeCandidatePlan(
            problem: problem,
            problemPath: problemPath,
            pddlExport: pddlExport,
            solverPlanText: solverPlanText
        )
        let candidatePlanArtifact = try foundationArtifact(
            artifactStore.persistCandidatePlan(
                draft.plan,
                runID: request.runID,
                projectRoot: projectRoot
            ),
            field: "candidate-plan"
        )
        return XcircuiteSymbolicPlannerPlanImportResult(
            status: draft.diagnostics.contains(where: { $0.severity == "error" }) ? "imported-with-errors" : "imported",
            runID: request.runID,
            problemID: problem.problemID,
            planID: draft.plan.planID,
            importedActionCount: draft.plan.steps.count,
            solverPlanArtifact: solverPlanArtifact,
            pddlExportArtifact: pddlExportRef,
            candidatePlanArtifact: candidatePlanArtifact,
            candidatePlan: draft.plan,
            diagnostics: draft.diagnostics
        )
    }

    public func makeCandidatePlan(
        problem: XcircuiteCircuitPlanningProblem,
        problemPath: String,
        pddlExport: XcircuiteSymbolicPlannerPDDLExport,
        solverPlanText: String
    ) -> CandidatePlanDraft {
        let pddlActions = parsePDDLActions(from: solverPlanText)
        let actionByID = Dictionary(uniqueKeysWithValues: problem.candidateActions.map { ($0.actionID, $0) })
        let mappingByPDDLAction = Dictionary(uniqueKeysWithValues: pddlExport.actionMappings.map {
            ($0.pddlAction.lowercased(), $0)
        })
        let planID = identifier("\(problem.problemID)-external-symbolic-plan-1")
        let availableRefs = Set((problem.sourceRefs + problem.initialStateRefs).map(\.refID))
        var diagnostics: [XcircuiteSymbolicPlannerPlanImportDiagnostic] = []
        var steps: [XcircuiteCandidatePlanStep] = []
        var finalSymbolicState = initialSymbolicState(for: problem)

        for pddlAction in pddlActions {
            guard let mapping = mappingByPDDLAction[pddlAction.lowercased()] else {
                diagnostics.append(
                    XcircuiteSymbolicPlannerPlanImportDiagnostic(
                        severity: "error",
                        code: "unknown-pddl-action",
                        message: "Solver plan references action \(pddlAction), but the PDDL export mapping does not contain it.",
                        pddlAction: pddlAction
                    )
                )
                continue
            }
            guard mapping.included else {
                diagnostics.append(
                    XcircuiteSymbolicPlannerPlanImportDiagnostic(
                        severity: "error",
                        code: "excluded-pddl-action",
                        message: "Solver plan references action \(pddlAction), but that action was excluded from the PDDL export.",
                        pddlAction: pddlAction
                    )
                )
                continue
            }
            guard let action = actionByID[mapping.actionID] else {
                diagnostics.append(
                    XcircuiteSymbolicPlannerPlanImportDiagnostic(
                        severity: "error",
                        code: "candidate-action-not-found",
                        message: "PDDL action \(pddlAction) maps to candidate action \(mapping.actionID), but the planning problem no longer contains it.",
                        pddlAction: pddlAction
                    )
                )
                continue
            }

            let missingInputRefs = action.requiredInputRefs.filter { !availableRefs.contains($0) }
            let blockers = missingInputRefs.isEmpty
                ? []
                : ["missing-input-refs:\(missingInputRefs.joined(separator: ","))"]
            let order = steps.count + 1
            steps.append(
                XcircuiteCandidatePlanStep(
                    stepID: identifier("\(planID)-step-\(order)"),
                    order: order,
                    actionID: action.actionID,
                    domainID: action.domainID,
                    operationID: action.operationID,
                    maturity: action.maturity,
                    readiness: blockers.isEmpty ? "ready" : "blocked",
                    sourceObjectiveIDs: action.sourceObjectiveIDs,
                    requiredInputRefs: action.requiredInputRefs,
                    missingInputRefs: missingInputRefs,
                    verificationGates: action.verificationGates,
                    reason: "Imported from external symbolic planner action \(pddlAction). \(action.reason)",
                    parameterHints: action.parameterHints,
                    blockers: blockers
                )
            )
            if blockers.isEmpty {
                finalSymbolicState = unique(finalSymbolicState + mapping.effectAtoms)
            }
        }

        if pddlActions.isEmpty {
            diagnostics.append(
                XcircuiteSymbolicPlannerPlanImportDiagnostic(
                    severity: "error",
                    code: "empty-solver-plan",
                    message: "Solver plan did not contain any PDDL action entries."
                )
            )
        }

        let missingGoalBlockers = missingGoalAtomBlockers(
            objectives: problem.objectives,
            finalSymbolicState: finalSymbolicState
        )
        let stepBlockers = steps.flatMap(\.blockers)
        let planBlockers = unique(stepBlockers + missingGoalBlockers)
        let unresolvedObjectives = unresolvedObjectiveIDs(
            objectives: problem.objectives,
            finalSymbolicState: finalSymbolicState
        )
        let executionReadiness = diagnostics.contains(where: { $0.severity == "error" }) || !planBlockers.isEmpty
            ? "blocked"
            : "ready"
        let reviewProjection = XcircuiteCandidatePlanReviewProjection()

        let plan = XcircuiteCandidatePlan(
            planID: planID,
            problemID: problem.problemID,
            runID: problem.runID,
            strategy: "external-symbolic-planner-pddl-import",
            executionReadiness: executionReadiness,
            sourceProblemRef: XcircuitePlanningReference(
                refID: "planning-problem",
                kind: "planning-problem",
                path: problemPath,
                artifactID: XcircuitePlanningArtifactStore.problemArtifactID
            ),
            assumptions: reviewProjection.assumptions(from: problem),
            riskClassifications: reviewProjection.riskClassifications(
                from: problem,
                steps: steps
            ),
            steps: steps,
            verificationGates: problem.verificationGates,
            constraints: problem.constraints,
            unresolvedObjectives: unresolvedObjectives,
            blockers: planBlockers
        )
        return CandidatePlanDraft(plan: plan, diagnostics: diagnostics)
    }

    private func parsePDDLActions(from text: String) -> [String] {
        var actions: [String] = []
        for rawLine in text.components(separatedBy: .newlines) {
            let uncommented: Substring
            if let commentStart = rawLine.firstIndex(of: ";") {
                uncommented = rawLine[..<commentStart]
            } else {
                uncommented = rawLine[rawLine.startIndex...]
            }
            let line = String(uncommented).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            guard !isSolverMetadataLine(line) else { continue }
            var remaining = line
            var foundParenthesizedAction = false
            while let start = remaining.firstIndex(of: "("),
                  let end = remaining[start...].firstIndex(of: ")") {
                let content = remaining[remaining.index(after: start)..<end]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let actionName = content.split(whereSeparator: { $0 == " " || $0 == "\t" }).first {
                    actions.append(String(actionName).lowercased())
                    foundParenthesizedAction = true
                }
                remaining = String(remaining[remaining.index(after: end)...])
            }
            if !foundParenthesizedAction,
               let actionName = bareActionName(from: line) {
                actions.append(actionName.lowercased())
            }
        }
        return actions
    }

    private func isSolverMetadataLine(_ line: String) -> Bool {
        let lowered = line.lowercased()
        let metadataPrefixes = [
            "cost",
            "metric",
            "makespan",
            "plan length",
            "plan cost",
            "solution found",
            "optimal",
            "satisficing",
            "suboptimal",
            "search time",
            "total time",
        ]
        return metadataPrefixes.contains { lowered.hasPrefix($0) }
    }

    private func bareActionName(from line: String) -> String? {
        var candidate = line
        if let colonIndex = line.firstIndex(of: ":") {
            let prefix = line[..<colonIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            if prefix.allSatisfy({ character in
                character.isNumber || character == "." || character == "+"
            }) {
                candidate = String(line[line.index(after: colonIndex)...])
            }
        }
        guard let firstToken = candidate.split(whereSeparator: { $0 == " " || $0 == "\t" }).first else {
            return nil
        }
        let actionName = String(firstToken).trimmingCharacters(in: CharacterSet(charactersIn: "()"))
        guard !actionName.isEmpty else { return nil }
        guard actionName.allSatisfy({ character in
            character.isLetter || character.isNumber || character == "-" || character == "_" || character == "."
        }) else {
            return nil
        }
        return actionName
    }

    private func loadSolverPlanText(
        request: XcircuiteSymbolicPlannerPlanImportRequest,
        manifest: XcircuiteRunManifest,
        projectRoot: URL
    ) throws -> String {
        if let solverPlanText = request.solverPlanText {
            return solverPlanText
        }
        if let solverPlanPath = request.solverPlanPath {
            let reference = try verifiedProjectFileReference(
                path: solverPlanPath,
                artifactID: request.solverPlanArtifactID ?? XcircuitePlanningArtifactStore.symbolicPlannerSolverPlanArtifactID,
                field: "solver-plan",
                format: .text,
                runID: request.runID,
                projectRoot: projectRoot
            )
            let url = try workspaceStore.url(forProjectRelativePath: reference.path, inProjectAt: projectRoot)
            return try String(contentsOf: url, encoding: .utf8)
        }
        let artifactID = request.solverPlanArtifactID ?? XcircuitePlanningArtifactStore.symbolicPlannerSolverPlanArtifactID
        guard let reference = manifest.artifacts.first(where: { $0.artifactID == artifactID }) else {
            if request.solverPlanArtifactID == nil {
                throw XcircuiteSymbolicPlannerPlanImportError.missingSolverPlanReference
            }
            throw XcircuiteSymbolicPlannerPlanImportError.artifactNotFound(
                runID: request.runID,
                artifactID: artifactID
            )
        }
        let verifiedReference = try verifiedArtifactReference(
            foundationArtifact(reference, field: "solver-plan"),
            field: "solver-plan",
            projectRoot: projectRoot
        )
        let url = try workspaceStore.url(forProjectRelativePath: verifiedReference.path, inProjectAt: projectRoot)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func pddlExportReference(
        explicitPath: String?,
        artifactID: String?,
        manifest: XcircuiteRunManifest,
        runID: String,
        projectRoot: URL
    ) throws -> ArtifactReference {
        if let explicitPath {
            return try verifiedManifestProjectFileReference(
                path: explicitPath,
                artifactID: artifactID ?? XcircuitePlanningArtifactStore.symbolicPlannerPDDLExportArtifactID,
                field: "pddl-export",
                format: .json,
                manifest: manifest,
                runID: runID,
                projectRoot: projectRoot
            )
        }
        guard let artifactID else {
            throw XcircuiteSymbolicPlannerPlanImportError.missingPDDLExportReference
        }
        guard let reference = manifest.artifacts.first(where: { $0.artifactID == artifactID }) else {
            throw XcircuiteSymbolicPlannerPlanImportError.artifactNotFound(
                runID: runID,
                artifactID: artifactID
            )
        }
        return try verifiedArtifactReference(
            foundationArtifact(reference, field: "pddl-export"),
            field: "pddl-export",
            projectRoot: projectRoot
        )
    }

    private func requiredProblemPath(
        explicitPath: String?,
        artifactID: String?,
        manifest: XcircuiteRunManifest,
        runID: String,
        projectRoot: URL
    ) throws -> String {
        if let explicitPath {
            return try verifiedManifestProjectFileReference(
                path: explicitPath,
                artifactID: artifactID ?? XcircuitePlanningArtifactStore.problemArtifactID,
                field: "planning-problem",
                format: .json,
                manifest: manifest,
                runID: runID,
                projectRoot: projectRoot
            ).path
        }
        guard let artifactID else {
            throw XcircuiteSymbolicPlannerPlanImportError.missingProblemReference
        }
        guard let reference = manifest.artifacts.first(where: { $0.artifactID == artifactID }) else {
            throw XcircuiteSymbolicPlannerPlanImportError.artifactNotFound(
                runID: runID,
                artifactID: artifactID
            )
        }
        return try verifiedArtifactReference(
            foundationArtifact(reference, field: "planning-problem"),
            field: "planning-problem",
            projectRoot: projectRoot
        ).path
    }

    private func verifiedProjectFileReference(
        path: String,
        artifactID: String,
        field: String,
        format: XcircuiteFileFormat,
        runID: String,
        projectRoot: URL
    ) throws -> ArtifactReference {
        let reference = try workspaceStore.fileReference(
            forProjectRelativePath: path,
            artifactID: artifactID,
            kind: .other,
            format: format,
            inProjectAt: projectRoot,
            producedByRunID: runID
        )
        return try verifiedArtifactReference(
            foundationArtifact(reference, field: field),
            field: field,
            projectRoot: projectRoot
        )
    }

    private func verifiedManifestProjectFileReference(
        path: String,
        artifactID: String,
        field: String,
        format: XcircuiteFileFormat,
        manifest: XcircuiteRunManifest,
        runID: String,
        projectRoot: URL
    ) throws -> ArtifactReference {
        let explicitReference = try workspaceStore.fileReference(
            forProjectRelativePath: path,
            artifactID: artifactID,
            kind: .other,
            format: format,
            inProjectAt: projectRoot,
            producedByRunID: runID
        )
        guard let manifestReference = manifest.artifacts.first(where: { $0.artifactID == artifactID }) else {
            throw XcircuiteSymbolicPlannerPlanImportError.artifactNotFound(
                runID: runID,
                artifactID: artifactID
            )
        }
        guard manifestReference.producedByRunID == runID else {
            throw manifestReferenceMismatch(
                field: field,
                artifactID: artifactID,
                path: explicitReference.path,
                manifestPath: manifestReference.path,
                reason: "Run manifest artifact provenance does not match the requested run."
            )
        }
        let explicitArtifact = try foundationArtifact(explicitReference, field: field)
        let manifestArtifact = try foundationArtifact(manifestReference, field: field)
        try validateExplicitReference(
            explicitArtifact,
            matches: manifestArtifact,
            field: field,
            artifactID: artifactID,
            runID: runID
        )
        return try verifiedArtifactReference(manifestArtifact, field: field, projectRoot: projectRoot)
    }

    private func validateExplicitReference(
        _ explicitReference: ArtifactReference,
        matches manifestReference: ArtifactReference,
        field: String,
        artifactID: String,
        runID: String
    ) throws {
        if explicitReference.path != manifestReference.path {
            throw manifestReferenceMismatch(
                field: field,
                artifactID: artifactID,
                path: explicitReference.path,
                manifestPath: manifestReference.path,
                reason: "Explicit path does not match the run manifest artifact path."
            )
        }
        if explicitReference.sha256 != manifestReference.sha256 {
            throw manifestReferenceMismatch(
                field: field,
                artifactID: artifactID,
                path: explicitReference.path,
                manifestPath: manifestReference.path,
                reason: "Explicit file digest does not match the run manifest artifact digest."
            )
        }
        if explicitReference.byteCount != manifestReference.byteCount {
            throw manifestReferenceMismatch(
                field: field,
                artifactID: artifactID,
                path: explicitReference.path,
                manifestPath: manifestReference.path,
                reason: "Explicit file byte count does not match the run manifest artifact byte count."
            )
        }
    }

    private func manifestReferenceMismatch(
        field: String,
        artifactID: String,
        path: String,
        manifestPath: String,
        reason: String
    ) -> XcircuiteSymbolicPlannerPlanImportError {
        .manifestReferenceMismatch(
            field: field,
            artifactID: artifactID,
            path: path,
            manifestPath: manifestPath,
            reason: reason
        )
    }

    private func verifiedArtifactReference(
        _ reference: ArtifactReference,
        field: String,
        projectRoot: URL
    ) throws -> ArtifactReference {
        let integrity = artifactVerifier.verify(reference, relativeTo: projectRoot)
        guard integrity.isVerified else {
            let issue = integrity.issues.first
            throw XcircuiteSymbolicPlannerPlanImportError.artifactIntegrityFailed(
                field: field,
                artifactID: reference.artifactID,
                path: reference.path,
                status: legacyIntegrityStatus(for: issue),
                message: legacyIntegrityMessage(for: issue)
            )
        }
        return reference
    }

    private func foundationArtifact(
        _ reference: XcircuiteFileReference,
        field: String
    ) throws -> ArtifactReference {
        guard let converted = foundationArtifactReference(reference) else {
            throw XcircuiteSymbolicPlannerPlanImportError.invalidArtifactReference(
                field: field,
                path: reference.path,
                reason: "The verified legacy reference does not contain a valid digest and byte count."
            )
        }
        return converted
    }

    private func legacyIntegrityStatus(
        for issue: ArtifactIntegrityIssue?
    ) -> XcircuiteFileReferenceIntegrityStatus {
        switch issue?.code {
        case .missingFile:
            return .missingArtifact
        case .byteCountMismatch:
            return .byteCountMismatch
        case .digestMismatch:
            return .sha256Mismatch
        case .invalidLocation:
            return .invalidPath
        case .unsupportedDigestAlgorithm:
            return .invalidDigest
        case .notRegularFile, .unreadableFile, .none:
            return .unreadableArtifact
        }
    }

    private func legacyIntegrityMessage(
        for issue: ArtifactIntegrityIssue?
    ) -> String {
        switch issue?.code {
        case .byteCountMismatch:
            return "Artifact byte count does not match the file reference."
        case .digestMismatch:
            return "Artifact SHA-256 digest does not match the file reference."
        case .missingFile:
            return "Artifact file is missing."
        case .invalidLocation:
            return issue?.detail ?? "Artifact path must stay inside the project root."
        case .unsupportedDigestAlgorithm, .notRegularFile, .unreadableFile, .none:
            return issue?.detail ?? "Artifact file could not be read for integrity verification."
        }
    }

    private func initialSymbolicState(for problem: XcircuiteCircuitPlanningProblem) -> [String] {
        unique(
            (problem.sourceRefs + problem.initialStateRefs).flatMap { reference in
                var atoms = ["ref:\(reference.refID)"]
                if let artifactID = reference.artifactID {
                    atoms.append("artifact:\(artifactID)")
                }
                atoms.append(contentsOf: stringArrayValue(for: "symbolicStateAtoms", in: reference.metadata))
                atoms.append(contentsOf: stringArrayValue(for: "satisfiedPreconditions", in: reference.metadata))
                return atoms
            }
        )
    }

    private func unresolvedObjectiveIDs(
        objectives: [XcircuitePlanningObjective],
        finalSymbolicState: [String]
    ) -> [String] {
        objectives.compactMap { objective in
            let atoms = symbolicGoalAtoms(for: objective)
            guard !atoms.isEmpty else { return nil }
            return atoms.allSatisfy { finalSymbolicState.contains($0) } ? nil : objective.objectiveID
        }
    }

    private func missingGoalAtomBlockers(
        objectives: [XcircuitePlanningObjective],
        finalSymbolicState: [String]
    ) -> [String] {
        objectives.compactMap { objective in
            let missingAtoms = symbolicGoalAtoms(for: objective).filter { !finalSymbolicState.contains($0) }
            guard !missingAtoms.isEmpty else { return nil }
            return "missing-goal-atoms:\(objective.objectiveID):\(missingAtoms.joined(separator: ","))"
        }
    }

    private func symbolicGoalAtoms(for objective: XcircuitePlanningObjective) -> [String] {
        unique(
            stringArrayValue(for: "symbolicGoalAtoms", in: objective.evidence)
                + stringArrayValue(for: "goalAtoms", in: objective.evidence)
                + stringArrayValue(for: "requiredEffects", in: objective.evidence)
        )
    }

    private func stringArrayValue(
        for key: String,
        in values: [String: XcircuiteJSONValue]
    ) -> [String] {
        guard case .array(let items)? = values[key] else {
            return []
        }
        return items.compactMap { item in
            guard case .string(let value) = item else {
                return nil
            }
            return value
        }
    }

    private func loadRunManifest(runID: String, projectRoot: URL) throws -> XcircuiteRunManifest {
        try workspaceStore.loadRunManifest(runID: runID, inProjectAt: projectRoot)
    }

    private func identifier(_ rawValue: String) -> String {
        let allowedScalars = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        let sanitizedScalars = rawValue.unicodeScalars.map { scalar in
            allowedScalars.contains(scalar) ? String(scalar) : "-"
        }
        let collapsed = sanitizedScalars.joined()
            .split(separator: "-")
            .joined(separator: "-")
        let trimmed = String(collapsed.prefix(120)).trimmingCharacters(in: CharacterSet(charactersIn: ".-_"))
        return trimmed.isEmpty ? "external-symbolic-plan" : trimmed
    }

    private func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }

    public struct CandidatePlanDraft: Sendable, Hashable {
        public var plan: XcircuiteCandidatePlan
        public var diagnostics: [XcircuiteSymbolicPlannerPlanImportDiagnostic]

        public init(
            plan: XcircuiteCandidatePlan,
            diagnostics: [XcircuiteSymbolicPlannerPlanImportDiagnostic]
        ) {
            self.plan = plan
            self.diagnostics = diagnostics
        }
    }
}
