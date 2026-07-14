import CoreSpiceIO
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
    ) throws -> XcircuiteCandidatePlanExecutionStepResult {
        let executionDirectory = try executionDirectoryURL(plan: plan, step: step, projectRoot: projectRoot)
        try packageStore.ensureDirectory(at: executionDirectory)
        let request = try layoutCommandRequest(
            step: step,
            plan: plan,
            executionDirectory: executionDirectory,
            projectRoot: projectRoot,
            context: context
        )
        let requestURL = executionDirectory.appending(path: "layout-command-request.json")
        try packageStore.writeJSON(request, to: requestURL, forProjectAt: projectRoot)

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
                format: .json,
                producedByRunID: plan.runID
            ),
            artifactBuilder.reference(
                for: validatedArtifacts.outputDocumentURL,
                projectRoot: projectRoot,
                artifactID: "candidate-step-\(step.order)-layout-document",
                kind: .layout,
                format: .json,
                producedByRunID: plan.runID
            ),
            artifactBuilder.reference(
                for: validatedArtifacts.resultURL,
                projectRoot: projectRoot,
                artifactID: "candidate-step-\(step.order)-layout-result",
                kind: .report,
                format: .json,
                producedByRunID: plan.runID
            ),
            artifactBuilder.reference(
                for: validatedArtifacts.manifestURL,
                projectRoot: projectRoot,
                artifactID: "candidate-step-\(step.order)-layout-manifest",
                kind: .report,
                format: .json,
                producedByRunID: plan.runID
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
        for artifact in artifacts {
            try packageStore.upsertRunArtifact(artifact, runID: plan.runID, inProjectAt: projectRoot)
        }
        let artifactReferences = try foundationArtifactReferences(
            artifacts,
            field: "candidate-step-layout-command"
        )
        return XcircuiteCandidatePlanExecutionStepResult(
            stepID: step.stepID,
            order: step.order,
            actionID: step.actionID,
            domainID: step.domainID,
            operationID: step.operationID,
            status: "executed",
            artifactReferences: artifactReferences,
            nextActions: signoffNextActions(for: step)
        )
    }

    func executeLVSPolicyRepair(
        step: XcircuiteCandidatePlanStep,
        plan: XcircuiteCandidatePlan,
        projectRoot: URL
    ) throws -> XcircuiteCandidatePlanExecutionStepResult {
        let executionDirectory = try executionDirectoryURL(plan: plan, step: step, projectRoot: projectRoot)
        try packageStore.ensureDirectory(at: executionDirectory)

        let policyKind = try lvsPolicyRepairKind(from: step)
        let policyURL: URL
        let policyArtifactID: String
        let terminalPolicyMetadata: (kind: String, model: String?, pinCount: Int?, groups: [[Int]])?
        switch policyKind {
        case "model-equivalence":
            let policy = try modelEquivalencePolicy(from: step)
            policyURL = executionDirectory.appending(path: "model-equivalence-policy.json")
            try packageStore.writeJSON(policy, to: policyURL, forProjectAt: projectRoot)
            policyArtifactID = "candidate-step-\(step.order)-model-equivalence-policy"
            terminalPolicyMetadata = nil
        case "terminal-equivalence":
            let policy = try terminalEquivalencePolicy(from: step)
            policyURL = executionDirectory.appending(path: "terminal-equivalence-policy.json")
            try packageStore.writeJSON(policy.policy, to: policyURL, forProjectAt: projectRoot)
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
        try packageStore.writeJSON(report, to: reportURL, forProjectAt: projectRoot)

        let artifacts = try [
            artifactBuilder.reference(
                for: policyURL,
                projectRoot: projectRoot,
                artifactID: policyArtifactID,
                kind: .model,
                format: .json,
                producedByRunID: plan.runID
            ),
            artifactBuilder.reference(
                for: reportURL,
                projectRoot: projectRoot,
                artifactID: "candidate-step-\(step.order)-lvs-policy-repair-report",
                kind: .report,
                format: .json,
                producedByRunID: plan.runID
            ),
        ]
        for artifact in artifacts {
            try packageStore.upsertRunArtifact(artifact, runID: plan.runID, inProjectAt: projectRoot)
        }
        let artifactReferences = try foundationArtifactReferences(
            artifacts,
            field: "candidate-step-lvs-policy-repair"
        )

        return XcircuiteCandidatePlanExecutionStepResult(
            stepID: step.stepID,
            order: step.order,
            actionID: step.actionID,
            domainID: step.domainID,
            operationID: step.operationID,
            status: "executed",
            artifactReferences: artifactReferences,
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
    ) throws -> [XcircuiteFileReference] {
        let specs = try standardLayoutExportSpecs(from: step)
        guard !specs.isEmpty else {
            return []
        }
        let documentData = try Data(contentsOf: outputDocumentURL)
        let document = try LayoutDocumentSerializer().decodeDocument(documentData)
        let runDirectory = try XcircuitePackage(projectRoot: projectRoot).runDirectoryURL(for: plan.runID)
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
                format: artifact.format,
                producedByRunID: plan.runID
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
        let outputURL = try packageStore.url(
            forProjectRelativePath: request.outputDocumentPath,
            inProjectAt: projectRoot
        )
        let manifestURL = try packageStore.url(
            forProjectRelativePath: manifestPath,
            inProjectAt: projectRoot
        )
        let resultURL = try packageStore.url(
            forProjectRelativePath: resultPath,
            inProjectAt: projectRoot
        )
        try requireLayoutCommandPath(
            result.outputDocumentPath,
            equals: outputURL,
            stepID: step.stepID,
            field: "outputDocumentPath"
        )
        try requireLayoutCommandPath(
            result.artifactManifestPath,
            equals: manifestURL,
            stepID: step.stepID,
            field: "artifactManifestPath"
        )
        try validateLayoutCommandOutputIntegrity(
            result,
            outputURL: outputURL,
            stepID: step.stepID
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
        stepID: String
    ) throws {
        let hasher = XcircuiteHasher()
        let byteCount = try hasher.byteCount(fileAt: outputURL)
        guard byteCount == Int64(result.outputDocumentByteCount) else {
            throw XcircuiteCandidatePlanExecutionError.layoutCommandOutputByteCountMismatch(
                stepID: stepID,
                path: canonicalPath(outputURL),
                expected: Int64(result.outputDocumentByteCount),
                actual: byteCount
            )
        }
        let digest = try hasher.sha256(fileAt: outputURL)
        guard digest == result.outputDocumentSHA256 else {
            throw XcircuiteCandidatePlanExecutionError.layoutCommandOutputDigestMismatch(
                stepID: stepID,
                path: canonicalPath(outputURL),
                expected: result.outputDocumentSHA256,
                actual: digest
            )
        }
    }

    func canonicalPath(_ url: URL) -> String {
        url.standardizedFileURL.path(percentEncoded: false)
    }

    func standardLayoutExportSpecs(
        from step: XcircuiteCandidatePlanStep
    ) throws -> [LayoutCommandStandardLayoutExportSpec] {
        if let specs: [LayoutCommandStandardLayoutExportSpec] = try decodedHint("standardLayoutExports", from: step) {
            return specs
        }
        if let spec: LayoutCommandStandardLayoutExportSpec = try decodedHint("standardLayoutExport", from: step) {
            return [spec]
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
        try XcircuiteIdentifierValidator().validate(spec.artifactID, kind: .artifactID)
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
            format: try xcircuiteFileFormat(for: spec.format)
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

    func xcircuiteFileFormat(for format: LayoutFileFormat) throws -> XcircuiteFileFormat {
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
    ) throws -> String? {
        guard plan.steps.contains(where: needsInitialLayoutDocument) else {
            return nil
        }
        guard let problemPath = plan.sourceProblemRef.path else {
            return nil
        }
        let problemURL = try packageStore.url(
            forProjectRelativePath: problemPath,
            inProjectAt: projectRoot
        )
        let problem = try packageStore.readJSON(
            XcircuiteCircuitPlanningProblem.self,
            from: problemURL
        )
        guard let layoutPath = problem.initialStateRefs.first(where: { $0.refID == "layout-ref" })?.path else {
            return nil
        }
        guard layoutPath.lowercased().hasSuffix(".json") else {
            return nil
        }
        let layoutURL = try packageStore.url(
            forProjectRelativePath: layoutPath,
            inProjectAt: projectRoot
        )
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
