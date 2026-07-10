import DRCEngine
import Foundation
import LVSEngine
import XcircuitePackage

public struct XcircuiteSignoffRepairFormulationBuilder: Sendable {
    private struct LoadedReports {
        var drc: DRCRepairHintReport?
        var drcPath: String?
        var drcReference: XcircuiteFileReference?
        var lvs: LVSRepairHintReport?
        var lvsPath: String?
        var lvsReference: XcircuiteFileReference?
    }

    private struct DraftAction {
        var goal: XcircuiteRepairPlanFormulation.Goal
        var action: XcircuiteRepairPlanFormulation.Action
        var risk: XcircuitePlanningRiskClassification?
    }

    private let packageStore: XcircuitePackageStore
    private let artifactStore: XcircuitePlanningArtifactStore
    private let compiler: XcircuiteRepairPlanFormulationCompiler
    private let fileReferenceVerifier: XcircuiteFileReferenceVerifier

    public init(
        packageStore: XcircuitePackageStore = XcircuitePackageStore(),
        artifactStore: XcircuitePlanningArtifactStore = XcircuitePlanningArtifactStore(),
        compiler: XcircuiteRepairPlanFormulationCompiler = XcircuiteRepairPlanFormulationCompiler(),
        fileReferenceVerifier: XcircuiteFileReferenceVerifier = XcircuiteFileReferenceVerifier()
    ) {
        self.packageStore = packageStore
        self.artifactStore = artifactStore
        self.compiler = compiler
        self.fileReferenceVerifier = fileReferenceVerifier
    }

    public func compile(
        request: XcircuiteSignoffRepairFormulationRequest,
        projectRoot: URL
    ) throws -> XcircuiteSignoffRepairFormulationResult {
        let loadedReports = try loadReports(request: request, projectRoot: projectRoot)
        let actionDomainArtifact = try artifactStore.persistActionDomainSnapshot(
            runID: request.runID,
            projectRoot: projectRoot
        )
        let formulation = try makeFormulation(
            request: request,
            loadedReports: loadedReports,
            actionDomainArtifact: actionDomainArtifact
        )
        let compilation = try compiler.compile(
            request: XcircuiteRepairPlanFormulationCompilationRequest(
                runID: request.runID,
                formulation: formulation,
                problemID: request.problemID
            ),
            projectRoot: projectRoot
        )
        return XcircuiteSignoffRepairFormulationResult(
            status: compilation.status,
            runID: request.runID,
            formulationID: formulation.formulationID,
            problemID: compilation.problemID,
            sourceReports: sourceReports(from: loadedReports),
            compilation: compilation
        )
    }

    public func makeFormulation(
        request: XcircuiteSignoffRepairFormulationRequest,
        projectRoot: URL
    ) throws -> XcircuiteRepairPlanFormulation {
        let loadedReports = try loadReports(request: request, projectRoot: projectRoot)
        let actionDomainArtifact = try artifactStore.persistActionDomainSnapshot(
            runID: request.runID,
            projectRoot: projectRoot
        )
        return try makeFormulation(
            request: request,
            loadedReports: loadedReports,
            actionDomainArtifact: actionDomainArtifact
        )
    }

    private func loadReports(
        request: XcircuiteSignoffRepairFormulationRequest,
        projectRoot: URL
    ) throws -> LoadedReports {
        try XcircuiteIdentifierValidator().validate(request.runID, kind: .runID)
        guard request.drcRepairHintPath != nil || request.lvsRepairHintPath != nil else {
            throw XcircuiteSignoffRepairFormulationError.missingRepairHintSource
        }
        let manifest = try loadRunManifest(runID: request.runID, projectRoot: projectRoot)
        let drc = try request.drcRepairHintPath.map {
            try loadVerifiedReport(
                DRCRepairHintReport.self,
                sourceKind: "drc",
                path: $0,
                expectedArtifactID: "drc-repair-hints",
                runID: request.runID,
                manifest: manifest,
                projectRoot: projectRoot
            )
        }
        let lvs = try request.lvsRepairHintPath.map {
            try loadVerifiedReport(
                LVSRepairHintReport.self,
                sourceKind: "lvs",
                path: $0,
                expectedArtifactID: "lvs-repair-hints",
                runID: request.runID,
                manifest: manifest,
                projectRoot: projectRoot
            )
        }
        return LoadedReports(
            drc: drc?.report,
            drcPath: request.drcRepairHintPath,
            drcReference: drc?.reference,
            lvs: lvs?.report,
            lvsPath: request.lvsRepairHintPath,
            lvsReference: lvs?.reference
        )
    }

    private func loadRunManifest(runID: String, projectRoot: URL) throws -> XcircuiteRunManifest {
        try packageStore.loadRunManifest(runID: runID, inProjectAt: projectRoot)
    }

    private func loadVerifiedReport<T: Decodable>(
        _ type: T.Type,
        sourceKind: String,
        path: String,
        expectedArtifactID: String,
        runID: String,
        manifest: XcircuiteRunManifest,
        projectRoot: URL
    ) throws -> (report: T, reference: XcircuiteFileReference) {
        do {
            _ = try packageStore.url(forProjectRelativePath: path, inProjectAt: projectRoot)
        } catch {
            throw XcircuiteSignoffRepairFormulationError.invalidRepairHintArtifact(
                sourceKind: sourceKind,
                path: path,
                reason: error.localizedDescription
            )
        }

        let matches = manifest.artifacts.filter { $0.path == path }
        guard !matches.isEmpty else {
            throw XcircuiteSignoffRepairFormulationError.unregisteredRepairHintReport(
                sourceKind: sourceKind,
                path: path
            )
        }
        guard matches.count == 1 else {
            throw XcircuiteSignoffRepairFormulationError.invalidRepairHintArtifact(
                sourceKind: sourceKind,
                path: path,
                reason: "run manifest contains \(matches.count) artifacts for the same repair hint path."
            )
        }

        let reference = matches[0]
        guard reference.artifactID == expectedArtifactID else {
            throw XcircuiteSignoffRepairFormulationError.invalidRepairHintArtifact(
                sourceKind: sourceKind,
                path: path,
                reason: "artifactID does not match expected \(expectedArtifactID)."
            )
        }
        guard reference.kind == .report, reference.format == .json else {
            throw XcircuiteSignoffRepairFormulationError.invalidRepairHintArtifact(
                sourceKind: sourceKind,
                path: path,
                reason: "repair hint reports must be JSON report artifacts."
            )
        }
        guard reference.producedByRunID == runID else {
            throw XcircuiteSignoffRepairFormulationError.repairHintProducerRunMismatch(
                sourceKind: sourceKind,
                expected: runID,
                actual: reference.producedByRunID
            )
        }
        let integrity = fileReferenceVerifier.verify(reference, projectRoot: projectRoot)
        guard integrity.status == .verified else {
            throw XcircuiteSignoffRepairFormulationError.repairHintArtifactIntegrityFailed(
                sourceKind: sourceKind,
                path: path,
                status: integrity.status,
                message: integrity.message
            )
        }

        return (
            report: try load(type, path: path, projectRoot: projectRoot),
            reference: reference
        )
    }

    private func load<T: Decodable>(
        _ type: T.Type,
        path: String,
        projectRoot: URL
    ) throws -> T {
        do {
            let url = try packageStore.url(forProjectRelativePath: path, inProjectAt: projectRoot)
            return try packageStore.readJSON(type, from: url)
        } catch {
            throw XcircuiteSignoffRepairFormulationError.reportReadFailed(
                path: path,
                message: error.localizedDescription
            )
        }
    }

    private func makeFormulation(
        request: XcircuiteSignoffRepairFormulationRequest,
        loadedReports: LoadedReports,
        actionDomainArtifact: XcircuiteFileReference
    ) throws -> XcircuiteRepairPlanFormulation {
        let drcRepairDrafts: [DraftAction] = loadedReports.drc.map {
            drcDrafts(report: $0, sourcePath: loadedReports.drcPath)
        } ?? []
        let lvsRepairDrafts: [DraftAction] = loadedReports.lvs.map {
            lvsDrafts(report: $0, sourcePath: loadedReports.lvsPath)
        } ?? []
        let drafts: [DraftAction] = drcRepairDrafts + lvsRepairDrafts
        guard !drafts.isEmpty else {
            throw XcircuiteSignoffRepairFormulationError.noActionableHints
        }

        let risks = drafts.compactMap(\.risk)
        let hasApprovalRisk = risks.contains { !$0.requiredApprovals.isEmpty }
        return XcircuiteRepairPlanFormulation(
            formulationID: request.formulationID ?? "signoff-repair-formulation-\(request.runID)",
            runID: request.runID,
            intentID: request.intentID ?? "repair-signoff-diagnostics-\(request.runID)",
            intent: request.intent ?? defaultIntent(loadedReports: loadedReports),
            sourceRefs: sourceRefs(from: loadedReports),
            initialStateRefs: [
                XcircuitePlanningReference(
                    refID: "action-domain-snapshot",
                    kind: "action-domain-snapshot",
                    path: actionDomainArtifact.path,
                    artifactID: actionDomainArtifact.artifactID
                ),
            ],
            assumptions: assumptions(from: loadedReports),
            riskClassifications: risks,
            goals: drafts.map(\.goal),
            constraints: constraints(
                hasApprovalRisk: hasApprovalRisk,
                sourceRefIDs: sourceRefIDs(from: loadedReports)
            ),
            actionDomainRefs: unique(drafts.map(\.action.domainID)),
            actions: drafts.map(\.action),
            costModel: costModel(),
            verificationGates: verificationGates(from: drafts),
            resumeContract: resumeContract(sourcePaths: [loadedReports.drcPath, loadedReports.lvsPath].compactMap { $0 }),
            metadata: metadata(from: loadedReports)
        )
    }

    private func sourceRefs(from loadedReports: LoadedReports) -> [XcircuitePlanningReference] {
        var refs: [XcircuitePlanningReference] = []
        if let report = loadedReports.drc, let path = loadedReports.drcPath {
            refs.append(XcircuitePlanningReference(
                refID: "drc-repair-hints",
                kind: "drc-repair-hint-report",
                path: path,
                artifactID: "drc-repair-hints",
                metadata: sourceMetadata(
                    sourceKind: "drc",
                    backendID: report.backendID,
                    topCell: report.topCell,
                    status: report.status,
                    activeDiagnosticCount: report.activeDiagnosticCount,
                    hintCount: report.hintCount,
                    unsupportedDiagnosticCount: report.unsupportedDiagnosticIndexes.count,
                    reference: loadedReports.drcReference
                )
            ))
        }
        if let report = loadedReports.lvs, let path = loadedReports.lvsPath {
            refs.append(XcircuitePlanningReference(
                refID: "lvs-repair-hints",
                kind: "lvs-repair-hint-report",
                path: path,
                artifactID: "lvs-repair-hints",
                metadata: sourceMetadata(
                    sourceKind: "lvs",
                    backendID: report.backendID,
                    topCell: report.topCell,
                    status: report.status,
                    activeDiagnosticCount: report.activeDiagnosticCount,
                    hintCount: report.hintCount,
                    unsupportedDiagnosticCount: report.unsupportedDiagnosticIndexes.count,
                    reference: loadedReports.lvsReference
                )
            ))
        }
        return refs
    }

    private func sourceReports(
        from loadedReports: LoadedReports
    ) -> [XcircuiteSignoffRepairFormulationResult.SourceReport] {
        var reports: [XcircuiteSignoffRepairFormulationResult.SourceReport] = []
        if let report = loadedReports.drc, let path = loadedReports.drcPath {
            reports.append(XcircuiteSignoffRepairFormulationResult.SourceReport(
                sourceKind: "drc",
                path: path,
                backendID: report.backendID,
                topCell: report.topCell,
                status: report.status,
                activeDiagnosticCount: report.activeDiagnosticCount,
                hintCount: report.hintCount,
                unsupportedDiagnosticCount: report.unsupportedDiagnosticIndexes.count,
                artifactID: loadedReports.drcReference?.artifactID,
                sha256: loadedReports.drcReference?.sha256,
                byteCount: loadedReports.drcReference?.byteCount,
                producedByRunID: loadedReports.drcReference?.producedByRunID,
                integrityStatus: XcircuiteFileReferenceIntegrityStatus.verified.rawValue
            ))
        }
        if let report = loadedReports.lvs, let path = loadedReports.lvsPath {
            reports.append(XcircuiteSignoffRepairFormulationResult.SourceReport(
                sourceKind: "lvs",
                path: path,
                backendID: report.backendID,
                topCell: report.topCell,
                status: report.status,
                activeDiagnosticCount: report.activeDiagnosticCount,
                hintCount: report.hintCount,
                unsupportedDiagnosticCount: report.unsupportedDiagnosticIndexes.count,
                artifactID: loadedReports.lvsReference?.artifactID,
                sha256: loadedReports.lvsReference?.sha256,
                byteCount: loadedReports.lvsReference?.byteCount,
                producedByRunID: loadedReports.lvsReference?.producedByRunID,
                integrityStatus: XcircuiteFileReferenceIntegrityStatus.verified.rawValue
            ))
        }
        return reports
    }

    private func drcDrafts(
        report: DRCRepairHintReport,
        sourcePath: String?
    ) -> [DraftAction] {
        report.hints.enumerated().map { pair in
            let index = pair.offset
            let hint = pair.element
            let goalID = "drc-goal-\(index)"
            let actionID = "drc-action-\(index)"
            let target = "drc-\(symbolicAtomToken(hint.kind ?? hint.ruleID ?? "violation"))-cleared"
            let goal = XcircuiteRepairPlanFormulation.Goal(
                goalID: goalID,
                kind: "repair",
                domain: "drc",
                priority: "error",
                sourceRefIDs: ["drc-repair-hints"],
                target: target,
                currentValue: hint.measured.map { .number($0) },
                requiredValue: hint.required.map { .number($0) },
                unit: hint.stringParameters["unit"],
                description: "Clear active DRC diagnostic \(hint.hintID) for \(hint.ruleID ?? hint.kind ?? "unknown-rule").",
                symbolicGoalAtoms: [target],
                evidence: drcEvidence(hint: hint, sourcePath: sourcePath),
                suggestedActions: [hint.operationID]
            )
            let action = XcircuiteRepairPlanFormulation.Action(
                actionID: actionID,
                domainID: domainID(for: hint.operationID),
                operationID: hint.operationID,
                maturity: "implemented",
                reason: hint.rationale,
                sourceGoalIDs: [goalID],
                requiredInputRefs: ["drc-repair-hints"],
                verificationGates: hint.verificationGates,
                parameterHints: drcParameterHints(hint: hint, sourcePath: sourcePath)
            )
            return DraftAction(
                goal: goal,
                action: action,
                risk: drcRisk(hint: hint, goalID: goalID, actionID: actionID)
            )
        }
    }

    private func lvsDrafts(
        report: LVSRepairHintReport,
        sourcePath: String?
    ) -> [DraftAction] {
        report.hints.enumerated().map { pair in
            let index = pair.offset
            let hint = pair.element
            let goalID = "lvs-goal-\(index)"
            let actionID = "lvs-action-\(index)"
            let target = "lvs-\(symbolicAtomToken(hint.category ?? hint.ruleID ?? "mismatch"))-resolved"
            let goal = XcircuiteRepairPlanFormulation.Goal(
                goalID: goalID,
                kind: "repair",
                domain: "lvs",
                priority: "error",
                sourceRefIDs: ["lvs-repair-hints"],
                target: target,
                currentValue: lvsCurrentValue(hint),
                requiredValue: lvsRequiredValue(hint),
                description: "Resolve active LVS diagnostic \(hint.hintID) for \(hint.ruleID ?? hint.category ?? "unknown-rule").",
                symbolicGoalAtoms: [target],
                evidence: lvsEvidence(hint: hint, sourcePath: sourcePath),
                suggestedActions: [hint.operationID]
            )
            let action = XcircuiteRepairPlanFormulation.Action(
                actionID: actionID,
                domainID: domainID(for: hint.operationID),
                operationID: hint.operationID,
                maturity: "implemented",
                reason: hint.rationale,
                sourceGoalIDs: [goalID],
                requiredInputRefs: ["lvs-repair-hints"],
                verificationGates: normalizedLVSGates(hint.verificationGates, operationID: hint.operationID),
                parameterHints: lvsParameterHints(hint: hint, sourcePath: sourcePath)
            )
            return DraftAction(
                goal: goal,
                action: action,
                risk: lvsRisk(hint: hint, goalID: goalID, actionID: actionID)
            )
        }
    }

    private func sourceMetadata(
        sourceKind: String,
        backendID: String,
        topCell: String,
        status: String,
        activeDiagnosticCount: Int,
        hintCount: Int,
        unsupportedDiagnosticCount: Int,
        reference: XcircuiteFileReference?
    ) -> [String: XcircuiteJSONValue] {
        var metadata: [String: XcircuiteJSONValue] = [
            "sourceKind": .string(sourceKind),
            "backendID": .string(backendID),
            "topCell": .string(topCell),
            "status": .string(status),
            "activeDiagnosticCount": .number(Double(activeDiagnosticCount)),
            "hintCount": .number(Double(hintCount)),
            "unsupportedDiagnosticCount": .number(Double(unsupportedDiagnosticCount)),
        ]
        if let reference {
            metadata["artifactID"] = reference.artifactID.map { .string($0) }
            metadata["artifactPath"] = .string(reference.path)
            metadata["artifactSHA256"] = reference.sha256.map { .string($0) }
            metadata["artifactByteCount"] = reference.byteCount.map { .number(Double($0)) }
            metadata["artifactProducedByRunID"] = reference.producedByRunID.map { .string($0) }
            metadata["artifactIntegrityStatus"] = .string(XcircuiteFileReferenceIntegrityStatus.verified.rawValue)
        }
        return metadata
    }

    private func drcEvidence(
        hint: DRCRepairHint,
        sourcePath: String?
    ) -> [String: XcircuiteJSONValue] {
        var evidence = drcParameterHints(hint: hint, sourcePath: sourcePath)
        evidence["sourceEngineOperation"] = .string("drc.export-repair-hints")
        evidence["sourceDiagnosticIndex"] = .number(Double(hint.sourceDiagnosticIndex))
        evidence["repairHintID"] = .string(hint.hintID)
        evidence["repairHintConfidence"] = .string(hint.confidence)
        return evidence
    }

    private func drcParameterHints(
        hint: DRCRepairHint,
        sourcePath: String?
    ) -> [String: XcircuiteJSONValue] {
        var values = jsonValues(strings: hint.stringParameters, numbers: hint.numericParameters)
        values["sourceKind"] = .string("drc")
        values["sourceRepairHintPath"] = sourcePath.map { .string($0) }
        values["repairHintID"] = .string(hint.hintID)
        values["operationID"] = .string(hint.operationID)
        values["confidence"] = .string(hint.confidence)
        values["targetShapeIDs"] = jsonArray(hint.targetShapeIDs)
        values["relatedViaIDs"] = jsonArray(hint.relatedViaIDs)
        values["relatedNetIDs"] = jsonArray(hint.relatedNetIDs)
        if let measured = hint.measured {
            values["measured"] = .number(measured)
        }
        if let required = hint.required {
            values["required"] = .number(required)
        }
        if let region = hint.region {
            values["region"] = .object([
                "x": .number(region.x),
                "y": .number(region.y),
                "width": .number(region.width),
                "height": .number(region.height),
            ])
        }
        return values
    }

    private func lvsEvidence(
        hint: LVSRepairHint,
        sourcePath: String?
    ) -> [String: XcircuiteJSONValue] {
        var evidence = lvsParameterHints(hint: hint, sourcePath: sourcePath)
        evidence["sourceEngineOperation"] = .string("lvs.export-repair-hints")
        evidence["sourceDiagnosticIndex"] = .number(Double(hint.sourceDiagnosticIndex))
        evidence["repairHintID"] = .string(hint.hintID)
        evidence["repairHintConfidence"] = .string(hint.confidence)
        return evidence
    }

    private func lvsParameterHints(
        hint: LVSRepairHint,
        sourcePath: String?
    ) -> [String: XcircuiteJSONValue] {
        var values = jsonValues(strings: hint.stringParameters, numbers: [:])
        values["sourceKind"] = .string("lvs")
        values["sourceRepairHintPath"] = sourcePath.map { .string($0) }
        values["repairHintID"] = .string(hint.hintID)
        values["operationID"] = .string(hint.operationID)
        values["confidence"] = .string(hint.confidence)
        values["layoutPorts"] = jsonArray(hint.layoutPorts)
        values["schematicPorts"] = jsonArray(hint.schematicPorts)
        if let layoutCount = hint.layoutCount {
            values["layoutCount"] = .number(Double(layoutCount))
        }
        if let schematicCount = hint.schematicCount {
            values["schematicCount"] = .number(Double(schematicCount))
        }
        return values
    }

    private func lvsCurrentValue(_ hint: LVSRepairHint) -> XcircuiteJSONValue? {
        if let value = hint.layoutValue {
            return .string(value)
        }
        if let count = hint.layoutCount {
            return .number(Double(count))
        }
        if !hint.layoutPorts.isEmpty {
            return jsonArray(hint.layoutPorts)
        }
        return nil
    }

    private func lvsRequiredValue(_ hint: LVSRepairHint) -> XcircuiteJSONValue? {
        if let value = hint.schematicValue {
            return .string(value)
        }
        if let count = hint.schematicCount {
            return .number(Double(count))
        }
        if !hint.schematicPorts.isEmpty {
            return jsonArray(hint.schematicPorts)
        }
        return nil
    }

    private func assumptions(from loadedReports: LoadedReports) -> [XcircuitePlanningAssumption] {
        [
            XcircuitePlanningAssumption(
                assumptionID: "signoff-repair-hints-are-engine-derived",
                source: "xcircuite.formulate-signoff-repair-planning-problem",
                statement: "DRC and LVS repair formulations are derived from engine-owned typed repair hint reports.",
                status: "resolved",
                confidence: 1,
                sourceRefIDs: sourceRefIDs(from: loadedReports),
                requiredBeforeExecution: false,
                evidence: metadata(from: loadedReports)
            ),
        ]
    }

    private func drcRisk(
        hint: DRCRepairHint,
        goalID: String,
        actionID: String
    ) -> XcircuitePlanningRiskClassification? {
        guard hint.confidence == "low"
            || hint.operationID == "layout.delete-shape"
            || hint.operationID == "layout.split-shape"
            || hint.operationID == "layout.add-via" else {
            return nil
        }
        let severity = hint.confidence == "low" ? "high" : "medium"
        return XcircuitePlanningRiskClassification(
            riskID: "\(actionID)-layout-risk",
            category: "layout-signoff-regression",
            severity: severity,
            scope: "layout-edit",
            description: "DRC repair hint \(hint.hintID) may change connectivity or create secondary signoff violations.",
            affectedObjectiveIDs: [goalID],
            affectedActionIDs: [actionID],
            requiredApprovals: severity == "high" ? ["layout-review"] : [],
            mitigationActions: ["run-native-drc", "run-native-lvs"],
            evidence: [
                "repairHintID": .string(hint.hintID),
                "operationID": .string(hint.operationID),
                "confidence": .string(hint.confidence),
            ]
        )
    }

    private func lvsRisk(
        hint: LVSRepairHint,
        goalID: String,
        actionID: String
    ) -> XcircuitePlanningRiskClassification? {
        if hint.operationID == "lvs.policy-repair" {
            return XcircuitePlanningRiskClassification(
                riskID: "\(actionID)-policy-risk",
                category: "lvs-policy-mutation",
                severity: "high",
                scope: "lvs-policy",
                description: "LVS policy repair hint \(hint.hintID) changes equivalence policy and requires human approval.",
                affectedObjectiveIDs: [goalID],
                affectedActionIDs: [actionID],
                requiredApprovals: ["lvs-policy-review"],
                mitigationActions: ["run-native-lvs", "review-policy-diff"],
                evidence: [
                    "repairHintID": .string(hint.hintID),
                    "operationID": .string(hint.operationID),
                    "confidence": .string(hint.confidence),
                ]
            )
        }
        if hint.confidence == "low" {
            return XcircuitePlanningRiskClassification(
                riskID: "\(actionID)-layout-risk",
                category: "lvs-layout-edit-regression",
                severity: "high",
                scope: "layout-edit",
                description: "Low-confidence LVS repair hint \(hint.hintID) may not preserve intended connectivity.",
                affectedObjectiveIDs: [goalID],
                affectedActionIDs: [actionID],
                requiredApprovals: ["layout-review"],
                mitigationActions: ["run-native-lvs", "run-native-drc"],
                evidence: [
                    "repairHintID": .string(hint.hintID),
                    "operationID": .string(hint.operationID),
                    "confidence": .string(hint.confidence),
                ]
            )
        }
        return nil
    }

    private func constraints(
        hasApprovalRisk: Bool,
        sourceRefIDs: [String]
    ) -> [XcircuitePlanningConstraint] {
        var constraints = [
            XcircuitePlanningConstraint(
                constraintID: "post-repair-signoff-required",
                kind: "verification",
                severity: "error",
                description: "Any selected signoff repair must be verified by the native DRC/LVS gates declared on the action.",
                sourceRefIDs: sourceRefIDs,
                evidence: [
                    "coveredSourceRefIDs": .array(sourceRefIDs.map { .string($0) }),
                ]
            ),
        ]
        if hasApprovalRisk {
            constraints.append(XcircuitePlanningConstraint(
                constraintID: "human-approval-required-for-risk",
                kind: "human-approval",
                severity: "error",
                description: "High-risk layout or LVS policy repair actions require explicit human approval before execution.",
                sourceRefIDs: sourceRefIDs,
                evidence: [
                    "coveredSourceRefIDs": .array(sourceRefIDs.map { .string($0) }),
                ]
            ))
        }
        return constraints
    }

    private func verificationGates(from drafts: [DraftAction]) -> [XcircuitePlanningVerificationGate] {
        unique(drafts.flatMap(\.action.verificationGates)).map { gateID in
            XcircuitePlanningVerificationGate(
                gateID: gateID,
                required: true,
                description: "Required by signoff repair formulation action gate \(gateID)."
            )
        }
    }

    private func costModel() -> XcircuitePlanningCostModel {
        XcircuitePlanningCostModel(
            strategy: "signoff-repair-formulation-confidence-first",
            terms: [
                XcircuitePlanningCostTerm(
                    termID: "repair.action-count",
                    weight: 1,
                    direction: "minimize",
                    description: "Prefer fewer signoff repair actions before re-running verification."
                ),
                XcircuitePlanningCostTerm(
                    termID: "repair.risk",
                    weight: 3,
                    direction: "minimize",
                    description: "Prefer higher-confidence repair hints and avoid approval-gated mutations when alternatives exist."
                ),
            ]
        )
    }

    private func resumeContract(sourcePaths: [String]) -> XcircuitePlanningResumeContract {
        XcircuitePlanningResumeContract(
            mode: "signoff-repair-formulation",
            requiredArtifacts: unique(
                sourcePaths
                    + [
                        XcircuitePlanningArtifactStore.repairPlanFormulationRelativePath,
                        XcircuitePlanningArtifactStore.problemRelativePath,
                        XcircuitePlanningArtifactStore.actionDomainRelativePath,
                    ]
            ),
            blockedStates: ["repair-hints-missing", "formulation-validation-failed", "candidate-rejected"]
        )
    }

    private func defaultIntent(loadedReports: LoadedReports) -> String {
        let kinds = sourceRefIDs(from: loadedReports).joined(separator: " and ")
        return "Repair active \(kinds) signoff diagnostics using engine-derived repair hints, then verify with native signoff gates."
    }

    private func metadata(from loadedReports: LoadedReports) -> [String: XcircuiteJSONValue] {
        let sourceReports = sourceReports(from: loadedReports)
        return [
            "sourceReportCount": .number(Double(sourceReports.count)),
            "totalActiveDiagnosticCount": .number(Double(sourceReports.map(\.activeDiagnosticCount).reduce(0, +))),
            "totalRepairHintCount": .number(Double(sourceReports.map(\.hintCount).reduce(0, +))),
            "totalUnsupportedDiagnosticCount": .number(Double(sourceReports.map(\.unsupportedDiagnosticCount).reduce(0, +))),
        ]
    }

    private func sourceRefIDs(from loadedReports: LoadedReports) -> [String] {
        var ids: [String] = []
        if loadedReports.drc != nil {
            ids.append("drc-repair-hints")
        }
        if loadedReports.lvs != nil {
            ids.append("lvs-repair-hints")
        }
        return ids
    }

    private func domainID(for operationID: String) -> String {
        operationID.hasPrefix("layout.") ? "layout-edit" : "lvs-signoff"
    }

    private func normalizedLVSGates(_ gates: [String], operationID: String) -> [String] {
        var result = gates
        if operationID == "lvs.policy-repair" && !result.contains("approval-gate") {
            result.append("approval-gate")
        }
        return result
    }

    private func jsonValues(
        strings: [String: String],
        numbers: [String: Double]
    ) -> [String: XcircuiteJSONValue] {
        var values = strings.mapValues { XcircuiteJSONValue.string($0) }
        for (key, value) in numbers {
            values[key] = .number(value)
        }
        return values
    }

    private func jsonArray(_ values: [String]) -> XcircuiteJSONValue {
        .array(values.map { .string($0) })
    }

    private func symbolicAtomToken(_ value: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-")
        let mapped = value.lowercased().map { character -> Character in
            allowed.contains(character) ? character : "-"
        }
        let collapsed = String(mapped).split(separator: "-").joined(separator: "-")
        return collapsed.isEmpty ? "diagnostic" : collapsed
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
}
