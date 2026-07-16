import CoreSpiceIO
import CircuiteFoundation
import Foundation
import LayoutCommands
import LayoutCore
import LayoutIO
import LayoutTech
import LVSEngine
import DesignFlowKernel

extension XcircuiteCandidatePlanExecutor {
    func executeLayoutCommand(
        step: XcircuiteCandidatePlanStep,
        plan: XcircuiteCandidatePlan,
        projectRoot: URL,
        context: inout CandidatePlanExecutionContext
    ) async throws -> XcircuiteCandidatePlanExecutionStepResult {
        let executionDirectory = try executionDirectoryURL(plan: plan, step: step, projectRoot: projectRoot)
        try await ensureWorkspaceDirectory(at: executionDirectory, projectRoot: projectRoot)
        let request = try layoutCommandRequest(
            step: step,
            plan: plan,
            executionDirectory: executionDirectory,
            projectRoot: projectRoot,
            context: context
        )
        let requestURL = executionDirectory.appending(path: "layout-command-request.json")
        try await writeWorkspaceJSON(request, to: requestURL, projectRoot: projectRoot)

        let result = try layoutRunner.run(request: request, baseURL: projectRoot)
        let validatedArtifacts = try validateLayoutCommandResult(
            result,
            request: request,
            step: step,
            projectRoot: projectRoot
        )
        context.latestLayoutDocumentPath = try projectRelativePath(
            for: validatedArtifacts.outputDocumentURL,
            projectRoot: projectRoot
        )
        var artifacts = try [
            artifactBuilder.reference(
                for: requestURL,
                projectRoot: projectRoot,
                artifactID: "candidate-step-\(step.order)-layout-request",
                kind: .other,
                format: .json
            ),
            artifactBuilder.reference(
                for: validatedArtifacts.outputDocumentURL,
                projectRoot: projectRoot,
                artifactID: "candidate-step-\(step.order)-layout-document",
                kind: .layout,
                format: .json
            ),
            artifactBuilder.reference(
                for: validatedArtifacts.resultURL,
                projectRoot: projectRoot,
                artifactID: "candidate-step-\(step.order)-layout-result",
                kind: .report,
                format: .json
            ),
            artifactBuilder.reference(
                for: validatedArtifacts.manifestURL,
                projectRoot: projectRoot,
                artifactID: "candidate-step-\(step.order)-layout-manifest",
                kind: .report,
                format: .json
            ),
        ]
        artifacts.append(contentsOf: try standardLayoutArtifactRefs(
            step: step,
            plan: plan,
            result: result,
            outputDocumentURL: validatedArtifacts.outputDocumentURL,
            executionDirectory: executionDirectory,
            projectRoot: projectRoot
        ))
        artifacts = try await retainRunArtifacts(artifacts, runID: plan.runID)
        return XcircuiteCandidatePlanExecutionStepResult(
            stepID: step.stepID,
            order: step.order,
            actionID: step.actionID,
            domainID: step.domainID,
            operationID: step.operationID,
            status: "executed",
            artifactReferences: artifacts,
            nextActions: signoffNextActions(for: step)
        )
    }

    func executeLVSPolicyRepair(
        step: XcircuiteCandidatePlanStep,
        plan: XcircuiteCandidatePlan,
        projectRoot: URL
    ) async throws -> XcircuiteCandidatePlanExecutionStepResult {
        let executionDirectory = try executionDirectoryURL(plan: plan, step: step, projectRoot: projectRoot)
        try await ensureWorkspaceDirectory(at: executionDirectory, projectRoot: projectRoot)

        let policyKind = try lvsPolicyRepairKind(from: step)
        let policyURL: URL
        let policyArtifactID: String
        let terminalPolicyMetadata: (kind: String, model: String?, pinCount: Int?, groups: [[Int]])?
        switch policyKind {
        case "model-equivalence":
            let policy = try modelEquivalencePolicy(from: step)
            policyURL = executionDirectory.appending(path: "model-equivalence-policy.json")
            try await writeWorkspaceJSON(policy, to: policyURL, projectRoot: projectRoot)
            policyArtifactID = "candidate-step-\(step.order)-model-equivalence-policy"
            terminalPolicyMetadata = nil
        case "terminal-equivalence":
            let policy = try terminalEquivalencePolicy(from: step)
            policyURL = executionDirectory.appending(path: "terminal-equivalence-policy.json")
            try await writeWorkspaceJSON(policy.policy, to: policyURL, projectRoot: projectRoot)
            policyArtifactID = "candidate-step-\(step.order)-terminal-equivalence-policy"
            terminalPolicyMetadata = (
                kind: policy.rule.kind,
                model: policy.rule.model,
                pinCount: policy.rule.pinCount,
                groups: policy.rule.equivalentPinGroups
            )
        default:
            throw XcircuiteCandidatePlanExecutionError.invalidHint(
                stepID: step.stepID,
                key: "policyKind",
                expected: "model-equivalence or terminal-equivalence"
            )
        }
        let policyPath = try projectRelativePath(for: policyURL, projectRoot: projectRoot)

        let sourceDiagnosticIndex = try optionalNumberHint("sourceDiagnosticIndex", step: step).map(Int.init)
        let report = XcircuiteLVSPolicyRepairReport(
            status: "executed",
            runID: plan.runID,
            planID: plan.planID,
            stepID: step.stepID,
            operationID: step.operationID,
            policyKind: policyKind,
            sourceRepairHintID: stringHint("sourceRepairHintID", step: step),
            sourceDiagnosticIndex: sourceDiagnosticIndex,
            ruleID: stringHint("ruleID", step: step),
            category: stringHint("category", step: step),
            layoutModel: stringHint("layoutModel", step: step),
            schematicModel: stringHint("schematicModel", step: step),
            terminalKind: terminalPolicyMetadata?.kind,
            terminalModel: terminalPolicyMetadata?.model,
            terminalPinCount: terminalPolicyMetadata?.pinCount,
            equivalentPinGroups: terminalPolicyMetadata?.groups ?? [],
            producedPolicyArtifactID: policyArtifactID,
            producedPolicyPath: policyPath,
            rationale: step.reason
        )
        let reportURL = executionDirectory.appending(path: "lvs-policy-repair-report.json")
        try await writeWorkspaceJSON(report, to: reportURL, projectRoot: projectRoot)

        let artifacts = try await retainRunArtifacts([
            artifactBuilder.reference(
                for: policyURL,
                projectRoot: projectRoot,
                artifactID: policyArtifactID,
                kind: .model,
                format: .json
            ),
            artifactBuilder.reference(
                for: reportURL,
                projectRoot: projectRoot,
                artifactID: "candidate-step-\(step.order)-lvs-policy-repair-report",
                kind: .report,
                format: .json
            ),
        ], runID: plan.runID)
        return XcircuiteCandidatePlanExecutionStepResult(
            stepID: step.stepID,
            order: step.order,
            actionID: step.actionID,
            domainID: step.domainID,
            operationID: step.operationID,
            status: "executed",
            artifactReferences: artifacts,
            nextActions: signoffNextActions(for: step)
        )
    }

    func standardLayoutArtifactRefs(
        step: XcircuiteCandidatePlanStep,
        plan: XcircuiteCandidatePlan,
        result: LayoutCommandResult,
        outputDocumentURL: URL,
        executionDirectory: URL,
        projectRoot: URL
    ) throws -> [ArtifactReference] {
        let specs = try standardLayoutExportSpecs(from: step)
        guard !specs.isEmpty else {
            return []
        }
        let documentData = try Data(contentsOf: outputDocumentURL)
        let document = try LayoutDocumentSerializer().decodeDocument(documentData)
        let runDirectory = try XcircuiteWorkspaceLayout(projectRoot: projectRoot).runDirectoryURL(for: plan.runID)
        return try specs.map { spec in
            let artifact = try exportStandardLayout(
                document,
                spec: spec,
                executionDirectory: executionDirectory,
                runDirectory: runDirectory,
                projectRoot: projectRoot
            )
            return try artifactBuilder.reference(
                for: artifact.url,
                projectRoot: projectRoot,
                artifactID: artifact.artifactID,
                kind: .layout,
                format: artifact.format
            )
        }
    }

    func validateLayoutCommandResult(
        _ result: LayoutCommandResult,
        request: LayoutCommandRequest,
        step: XcircuiteCandidatePlanStep,
        projectRoot: URL
    ) throws -> CandidatePlanLayoutCommandArtifacts {
        guard result.status == "passed" else {
            throw XcircuiteCandidatePlanExecutionError.layoutCommandStatusFailed(
                stepID: step.stepID,
                status: result.status
            )
        }
        guard let manifestPath = request.artifactManifestPath else {
            throw XcircuiteCandidatePlanExecutionError.missingLayoutCommandArtifactPath(
                stepID: step.stepID,
                field: "artifactManifestPath"
            )
        }
        guard let resultPath = request.resultPath else {
            throw XcircuiteCandidatePlanExecutionError.missingLayoutCommandArtifactPath(
                stepID: step.stepID,
                field: "resultPath"
            )
        }
        let outputURL = try projectURL(for: request.outputDocumentPath, projectRoot: projectRoot)
        let manifestURL = try projectURL(for: manifestPath, projectRoot: projectRoot)
        let resultURL = try projectURL(for: resultPath, projectRoot: projectRoot)
        try requireLayoutCommandPath(
            result.outputArtifact.path,
            equals: outputURL,
            stepID: step.stepID,
            field: "outputArtifact.path"
        )
        try validateLayoutCommandOutputIntegrity(
            result,
            outputURL: outputURL,
            stepID: step.stepID,
            projectRoot: projectRoot
        )
        return CandidatePlanLayoutCommandArtifacts(
            outputDocumentURL: outputURL,
            manifestURL: manifestURL,
            resultURL: resultURL
        )
    }

    func requireLayoutCommandPath(
        _ actualPath: String,
        equals expectedURL: URL,
        stepID: String,
        field: String
    ) throws {
        let expected = canonicalPath(expectedURL)
        let actual = canonicalPath(URL(filePath: actualPath))
        guard actual == expected else {
            throw XcircuiteCandidatePlanExecutionError.layoutCommandResultPathMismatch(
                stepID: stepID,
                field: field,
                expected: expected,
                actual: actual
            )
        }
    }

    func validateLayoutCommandOutputIntegrity(
        _ result: LayoutCommandResult,
        outputURL: URL,
        stepID: String,
        projectRoot: URL
    ) throws {
        guard result.outputArtifact.kind == .layout,
              result.outputArtifact.format == .json,
              result.outputArtifact.locator.role.rawValue == "output-layout-document" else {
            throw XcircuiteCandidatePlanExecutionError.layoutCommandOutputReferenceInvalid(
                stepID: stepID,
                path: canonicalPath(outputURL)
            )
        }
        let integrity = artifactVerifier.verify(result.outputArtifact, relativeTo: projectRoot)
        guard let issue = integrity.issues.first else {
            return
        }
        if issue.code == .byteCountMismatch {
            throw XcircuiteCandidatePlanExecutionError.layoutCommandOutputByteCountMismatch(
                stepID: stepID,
                path: canonicalPath(outputURL),
                expected: Int64(clamping: issue.expectedByteCount ?? result.outputArtifact.byteCount),
                actual: Int64(clamping: issue.actualByteCount ?? 0)
            )
        }
        if issue.code == .digestMismatch {
            throw XcircuiteCandidatePlanExecutionError.layoutCommandOutputDigestMismatch(
                stepID: stepID,
                path: canonicalPath(outputURL),
                expected: issue.expectedDigest?.hexadecimalValue
                    ?? result.outputArtifact.digest.hexadecimalValue,
                actual: issue.actualDigest?.hexadecimalValue ?? "unavailable"
            )
        }
        throw XcircuiteCandidatePlanExecutionError.layoutCommandOutputIntegrityFailed(
            stepID: stepID,
            path: canonicalPath(outputURL),
            issue: issue.code.rawValue
        )
    }

    func canonicalPath(_ url: URL) -> String {
        url.standardizedFileURL.path(percentEncoded: false)
    }

    func standardLayoutExportSpecs(
        from step: XcircuiteCandidatePlanStep
    ) throws -> [LayoutCommandStandardLayoutExportSpec] {
        if case .standardLayoutExports(let specs)? = step.parameterHints["standardLayoutExports"] {
            return specs
        }
        return []
    }

    func exportStandardLayout(
        _ document: LayoutDocument,
        spec: LayoutCommandStandardLayoutExportSpec,
        executionDirectory: URL,
        runDirectory: URL,
        projectRoot: URL
    ) throws -> CandidatePlanStandardLayoutArtifact {
        try FlowIdentifierValidator().validate(spec.artifactID, kind: .artifactID)
        let exportURL = executionDirectory.appending(
            path: "\(spec.artifactID).\(try standardLayoutFileExtension(for: spec.format))"
        )
        let technologyURL = try spec.technologyInput.resolveExisting(
            projectRoot: projectRoot,
            runDirectory: runDirectory
        )
        let converter = MaskDataFormatConverter(tech: try loadTechnology(from: technologyURL))
        try converter.exportDocument(document, to: exportURL, format: spec.format)
        return CandidatePlanStandardLayoutArtifact(
            url: exportURL,
            artifactID: spec.artifactID,
            format: try artifactFormat(for: spec.format)
        )
    }

    func loadTechnology(from url: URL) throws -> LayoutTechDatabase {
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(LayoutTechDatabase.self, from: data)
        } catch {
            throw CandidatePlanStandardLayoutExportError.technologyLoadFailed(
                path: url.path(percentEncoded: false),
                reason: error.localizedDescription
            )
        }
    }

    func standardLayoutFileExtension(for format: LayoutFileFormat) throws -> String {
        switch format {
        case .gds:
            return "gds"
        case .oasis:
            return "oas"
        case .cif:
            return "cif"
        case .dxf:
            return "dxf"
        case .json, .lef, .def, .odb:
            throw CandidatePlanStandardLayoutExportError.unsupportedFormat(format.rawValue)
        }
    }

    func artifactFormat(for format: LayoutFileFormat) throws -> ArtifactFormat {
        switch format {
        case .gds:
            return .gdsii
        case .oasis:
            return .oasis
        case .cif, .dxf:
            return .raw
        case .json, .lef, .def, .odb:
            throw CandidatePlanStandardLayoutExportError.unsupportedFormat(format.rawValue)
        }
    }

    func initialLayoutDocumentPathIfNeeded(
        for plan: XcircuiteCandidatePlan,
        projectRoot: URL
    ) async throws -> String? {
        guard plan.steps.contains(where: needsInitialLayoutDocument) else {
            return nil
        }
        guard let problemPath = plan.sourceProblemRef.path else {
            return nil
        }
        let problemURL = try projectURL(for: problemPath, projectRoot: projectRoot)
        let problem = try JSONDecoder().decode(
            XcircuiteCircuitPlanningProblem.self,
            from: Data(contentsOf: problemURL)
        )
        guard let layoutPath = problem.initialStateRefs.first(where: { $0.refID == "layout-ref" })?.path else {
            return nil
        }
        guard layoutPath.lowercased().hasSuffix(".json") else {
            return nil
        }
        let layoutURL = try projectURL(for: layoutPath, projectRoot: projectRoot)
        guard FileManager.default.fileExists(atPath: layoutURL.path(percentEncoded: false)) else {
            return nil
        }
        return layoutPath
    }

    func needsInitialLayoutDocument(_ step: XcircuiteCandidatePlanStep) -> Bool {
        guard step.requiredInputRefs.contains("layout-ref") else {
            return false
        }
        guard stringHint("inputDocumentPath", step: step) == nil,
              stringHint("layoutDocumentPath", step: step) == nil else {
            return false
        }
        return requiresExistingCell(step.operationID)
    }
}
