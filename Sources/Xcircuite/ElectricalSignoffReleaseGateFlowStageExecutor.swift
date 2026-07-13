import DesignFlowKernel
import ElectricalSignoffCore
import ElectricalSignoffEngine
import ElectricalSignoffQualification
import Foundation
import XcircuitePackage

public struct ElectricalSignoffReleaseGateFlowStageExecutor: FlowStageExecutor {
    public let stageID: String
    public let toolID: String
    private let requestInput: XcircuiteFlowInputReference
    private let runResultInput: XcircuiteFlowInputReference
    private let qualificationSpecInput: XcircuiteFlowInputReference
    private let qualificationReportInput: XcircuiteFlowInputReference
    private let policyInput: XcircuiteFlowInputReference
    private let evaluator: any ElectricalSignoffReleaseGateEvaluating

    public init(
        stageID: String = "electrical-signoff.release-gate",
        toolID: String = "native-electrical-signoff-release-gate",
        requestInput: XcircuiteFlowInputReference,
        runResultInput: XcircuiteFlowInputReference,
        qualificationSpecInput: XcircuiteFlowInputReference,
        qualificationReportInput: XcircuiteFlowInputReference,
        policyInput: XcircuiteFlowInputReference,
        evaluator: any ElectricalSignoffReleaseGateEvaluating = DefaultElectricalSignoffReleaseGateEvaluator()
    ) {
        self.stageID = stageID
        self.toolID = toolID
        self.requestInput = requestInput
        self.runResultInput = runResultInput
        self.qualificationSpecInput = qualificationSpecInput
        self.qualificationReportInput = qualificationReportInput
        self.policyInput = policyInput
        self.evaluator = evaluator
    }

    public func execute(
        stage: FlowStageDefinition,
        context: FlowExecutionContext
    ) async throws -> FlowStageResult {
        do {
            try context.checkCancellation()
            try validate(stage: stage, context: context)
            let signoffRequest = try load(ElectricalSignoffRequest.self, from: requestInput, context: context)
            let runResult = try load(ElectricalSignoffRunResult.self, from: runResultInput, context: context)
            let qualificationSpec = try load(ElectricalSignoffQualificationSpec.self, from: qualificationSpecInput, context: context)
            let qualificationReport = try load(ElectricalSignoffQualificationReport.self, from: qualificationReportInput, context: context)
            let policy = try load(ElectricalSignoffReleaseGatePolicy.self, from: policyInput, context: context)
            guard signoffRequest.runID == context.runID, runResult.runID == context.runID else {
                return failureResult(
                    stageID: stage.stageID,
                    code: "ELECTRICAL_SIGNOFF_RELEASE_GATE_RUN_ID_MISMATCH",
                    message: "The persisted electrical signoff request or result does not belong to the flow run."
                )
            }
            let artifactReferences = Array(Set(
                runResult.cornerResults.values
                    .flatMap { $0.values }
                    .flatMap(\.artifacts)
            ))
            let artifactIntegrity = artifactReferences.map {
                XcircuiteFileReferenceVerifier().verify($0, projectRoot: context.projectRoot)
            }
            let gateRequest = ElectricalSignoffReleaseGateRequest(
                runID: context.runID,
                runResult: runResult,
                qualificationReport: qualificationReport,
                policy: policy,
                artifactIntegrity: artifactIntegrity
            )
            let result = try evaluator.evaluate(gateRequest)
            try context.checkCancellation()
            let reference = try persist(result, context: context)
            let bundle = try makeReleaseArtifactBundle(
                request: signoffRequest,
                requestInput: requestInput,
                runResult: runResult,
                runResultInput: runResultInput,
                qualificationSpec: qualificationSpec,
                qualificationSpecInput: qualificationSpecInput,
                qualificationReport: qualificationReport,
                qualificationReportInput: qualificationReportInput,
                policy: policy,
                policyInput: policyInput,
                gateResultReference: reference,
                context: context
            )
            let bundleReference = try persist(bundle, context: context)
            let diagnostics = result.failureCodes.map { code in
                FlowDiagnostic(
                    severity: .error,
                    code: "ELECTRICAL_SIGNOFF_RELEASE_GATE_\(code.uppercased().replacingOccurrences(of: "-", with: "_"))",
                    message: "Electrical signoff release gate check failed: \(code)."
                )
            }
            let gateStatus: FlowGateStatus
            let stageStatus: FlowStageStatus
            switch result.status {
            case .passed:
                gateStatus = .passed
                stageStatus = .succeeded
            case .blocked:
                gateStatus = .blocked
                stageStatus = .blocked
            case .failed:
                gateStatus = .failed
                stageStatus = .failed
            }
            return FlowStageResult(
                stageID: stage.stageID,
                status: stageStatus,
                diagnostics: diagnostics,
                gates: [FlowGateResult(gateID: "electrical-signoff-release", status: gateStatus, diagnostics: diagnostics)],
                artifacts: [reference, bundleReference]
            )
        } catch let cancellationError as FlowRunCancellationError {
            throw cancellationError
        } catch {
            return failureResult(
                stageID: stage.stageID,
                code: "ELECTRICAL_SIGNOFF_RELEASE_GATE_EXECUTION_ERROR",
                message: error.localizedDescription
            )
        }
    }

    private func validate(stage: FlowStageDefinition, context: FlowExecutionContext) throws {
        guard stage.stageID == stageID else {
            throw ElectricalSignoffReleaseGateError.invalidRequest("stage ID does not match the executor")
        }
        guard !context.runID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ElectricalSignoffReleaseGateError.invalidRequest("run ID is required")
        }
        try XcircuiteIdentifierValidator().validate(stageID, kind: .stageID)
        try XcircuiteIdentifierValidator().validate(toolID, kind: .toolID)
    }

    private func load<Value: Decodable>(
        _ type: Value.Type,
        from input: XcircuiteFlowInputReference,
        context: FlowExecutionContext
    ) throws -> Value {
        let url = try input.resolveExisting(
            projectRoot: context.projectRoot,
            runDirectory: context.runDirectory
        )
        return try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }

    private func persist(
        _ result: ElectricalSignoffReleaseGateResult,
        context: FlowExecutionContext
    ) throws -> XcircuiteFileReference {
        let relativePath = ".xcircuite/runs/\(context.runID)/electrical-signoff/release-gate.json"
        let url = try context.packageStore.url(
            forProjectRelativePath: relativePath,
            inProjectAt: context.projectRoot
        )
        try context.packageStore.ensureDirectory(at: url.deletingLastPathComponent())
        try context.packageStore.writeJSON(result, to: url, forProjectAt: context.projectRoot)
        return try context.packageStore.fileReference(
            forProjectRelativePath: relativePath,
            artifactID: "electrical-signoff-release-gate",
            kind: .report,
            format: .json,
            inProjectAt: context.projectRoot,
            producedByRunID: context.runID,
            verifiedByRunID: context.runID
        )
    }

    private func persist(
        _ bundle: ElectricalSignoffReleaseArtifactBundle,
        context: FlowExecutionContext
    ) throws -> XcircuiteFileReference {
        let relativePath = ".xcircuite/runs/\(context.runID)/electrical-signoff/release-artifact-bundle.json"
        let url = try context.packageStore.url(
            forProjectRelativePath: relativePath,
            inProjectAt: context.projectRoot
        )
        try context.packageStore.ensureDirectory(at: url.deletingLastPathComponent())
        try context.packageStore.writeJSON(bundle, to: url, forProjectAt: context.projectRoot)
        return try context.packageStore.fileReference(
            forProjectRelativePath: relativePath,
            artifactID: "electrical-signoff-release-artifact-bundle",
            kind: .report,
            format: .json,
            inProjectAt: context.projectRoot,
            producedByRunID: context.runID,
            verifiedByRunID: context.runID
        )
    }

    private func makeReleaseArtifactBundle(
        request: ElectricalSignoffRequest,
        requestInput: XcircuiteFlowInputReference,
        runResult: ElectricalSignoffRunResult,
        runResultInput: XcircuiteFlowInputReference,
        qualificationSpec: ElectricalSignoffQualificationSpec,
        qualificationSpecInput: XcircuiteFlowInputReference,
        qualificationReport: ElectricalSignoffQualificationReport,
        qualificationReportInput: XcircuiteFlowInputReference,
        policy: ElectricalSignoffReleaseGatePolicy,
        policyInput: XcircuiteFlowInputReference,
        gateResultReference: XcircuiteFileReference,
        context: FlowExecutionContext
    ) throws -> ElectricalSignoffReleaseArtifactBundle {
        guard qualificationSpec.pdkDigest == request.pdk.digest,
              qualificationReport.pdkDigest == request.pdk.digest,
              policy.pdkDigest == request.pdk.digest else {
            throw ElectricalSignoffReleaseArtifactBundleError.missingReference(role: "pdk-bound-qualification")
        }

        let requestReference = try reference(
            for: requestInput,
            artifactID: "electrical-signoff-request",
            kind: .report,
            format: .json,
            context: context
        )
        let runResultReference = try reference(
            for: runResultInput,
            artifactID: "electrical-signoff-run-result",
            kind: .report,
            format: .json,
            context: context
        )
        let qualificationSpecReference = try reference(
            for: qualificationSpecInput,
            artifactID: "electrical-signoff-qualification-spec",
            kind: .report,
            format: .json,
            context: context
        )
        let qualificationReportReference = try reference(
            for: qualificationReportInput,
            artifactID: "electrical-signoff-qualification-report",
            kind: .report,
            format: .json,
            context: context
        )
        let policyReference = try reference(
            for: policyInput,
            artifactID: "electrical-signoff-release-policy",
            kind: .technology,
            format: .json,
            context: context
        )

        let mandatoryPaths = Set([
            gateResultReference.path,
            requestReference.path,
            runResultReference.path,
            qualificationSpecReference.path,
            qualificationReportReference.path,
            policyReference.path,
        ])
        let sourceArtifacts = unique(
            try requestInputs(request).map { sourceReference in
                try verifiedReference(sourceReference, context: context)
            }
        ).filter { !mandatoryPaths.contains($0.path) }
        let cornerAxisEvidence = unique(
            try runResult.cornerResults.values
                .flatMap { $0.values }
                .flatMap(\.artifacts)
                .map { sourceReference in
                    try verifiedReference(sourceReference, context: context)
                }
        ).filter { !mandatoryPaths.contains($0.path) }
        let qualificationSpecStageArtifacts = try stageArtifacts(from: qualificationSpecInput, context: context)
        let qualificationReportStageArtifacts = try stageArtifacts(from: qualificationReportInput, context: context)
        let qualificationStageArtifacts = qualificationSpecStageArtifacts + qualificationReportStageArtifacts
        let qualificationArtifacts = unique(
            try qualificationStageArtifacts.map { sourceReference in
                try verifiedReference(sourceReference, context: context)
            }
        ).filter { !mandatoryPaths.contains($0.path) }

        let runManifest = try optionalReference(
            path: ".xcircuite/runs/\(context.runID)/manifest.json",
            artifactID: "run-manifest",
            kind: .report,
            format: .json,
            context: context
        )
        let plan = try optionalReference(
            path: ".xcircuite/runs/\(context.runID)/plan.json",
            artifactID: "run-plan",
            kind: .report,
            format: .json,
            context: context
        )
        let actionLog = try optionalReference(
            path: ".xcircuite/runs/\(context.runID)/actions.jsonl",
            artifactID: "run-action-ledger",
            kind: .other,
            format: .text,
            context: context
        )
        let approvalArtifacts = try context.packageStore.loadApprovals(
            runID: context.runID,
            inProjectAt: context.projectRoot
        ).compactMap { approval in
            try optionalReference(
                path: ".xcircuite/runs/\(context.runID)/approvals/\(approval.stageID).json",
                artifactID: "approval-\(approval.stageID)",
                kind: .other,
                format: .json,
                context: context
            )
        }
        let repairPlan = try optionalReference(
            path: ".xcircuite/runs/\(context.runID)/electrical-signoff/repair-plan.json",
            artifactID: "electrical-signoff-repair-plan",
            kind: .report,
            format: .json,
            context: context
        )

        return try ElectricalSignoffReleaseArtifactBundle(
            runID: context.runID,
            createdAt: Date(),
            gateResult: gateResultReference,
            request: requestReference,
            runResult: runResultReference,
            qualificationSpec: qualificationSpecReference,
            qualificationReport: qualificationReportReference,
            qualificationArtifacts: qualificationArtifacts,
            policy: policyReference,
            sourceArtifacts: sourceArtifacts,
            cornerAxisEvidence: cornerAxisEvidence,
            repairPlan: repairPlan,
            approvalArtifacts: approvalArtifacts,
            plan: plan,
            actionLog: actionLog,
            runManifest: runManifest
        )
    }

    private func requestInputs(_ request: ElectricalSignoffRequest) -> [XcircuiteFileReference] {
        var references = request.inputs
        references.append(request.design.artifact)
        references.append(request.physicalDesign.layoutArtifact)
        references.append(request.pdk.manifest)
        if let powerIntent = request.powerIntent {
            references.append(powerIntent.artifact)
        }
        if let parasitics = request.parasitics {
            references.append(parasitics)
        }
        if let topology = request.topologyArtifact {
            references.append(topology)
        }
        if let profile = request.topologyProfileArtifact {
            references.append(profile)
        }
        if let processRules = request.processRuleArtifact {
            references.append(processRules)
        }
        return references
    }

    private func reference(
        for input: XcircuiteFlowInputReference,
        artifactID: String,
        kind: XcircuiteFileKind,
        format: XcircuiteFileFormat,
        context: FlowExecutionContext
    ) throws -> XcircuiteFileReference {
        let url = try input.resolveExisting(projectRoot: context.projectRoot, runDirectory: context.runDirectory)
        let path = try projectRelativePath(for: url, projectRoot: context.projectRoot)
        return try context.packageStore.fileReference(
            forProjectRelativePath: path,
            artifactID: artifactID,
            kind: kind,
            format: format,
            inProjectAt: context.projectRoot,
            verifiedByRunID: context.runID
        )
    }

    private func optionalReference(
        path: String,
        artifactID: String,
        kind: XcircuiteFileKind,
        format: XcircuiteFileFormat,
        context: FlowExecutionContext
    ) throws -> XcircuiteFileReference? {
        let url = try context.packageStore.url(forProjectRelativePath: path, inProjectAt: context.projectRoot)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return nil
        }
        return try context.packageStore.fileReference(
            forProjectRelativePath: path,
            artifactID: artifactID,
            kind: kind,
            format: format,
            inProjectAt: context.projectRoot,
            producedByRunID: context.runID,
            verifiedByRunID: context.runID
        )
    }

    private func stageArtifacts(
        from input: XcircuiteFlowInputReference,
        context: FlowExecutionContext
    ) throws -> [XcircuiteFileReference] {
        guard case .stageArtifact(let selector) = input else {
            return []
        }
        let resultURL = context.runDirectory
            .appending(path: "stages")
            .appending(path: selector.stageID)
            .appending(path: "result.json")
        let data: Data
        do {
            data = try Data(contentsOf: resultURL)
        } catch {
            throw ElectricalSignoffReleaseGateError.invalidRequest(
                "qualification stage result could not be read: \(error.localizedDescription)"
            )
        }
        do {
            return try JSONDecoder().decode(FlowStageResult.self, from: data).artifacts
        } catch {
            throw ElectricalSignoffReleaseGateError.invalidRequest(
                "qualification stage result could not be decoded: \(error.localizedDescription)"
            )
        }
    }

    private func unique(_ references: [XcircuiteFileReference]) -> [XcircuiteFileReference] {
        var paths = Set<String>()
        return references.filter { paths.insert($0.path).inserted }
    }

    private func projectRelativePath(for url: URL, projectRoot: URL) throws -> String {
        let root = projectRoot.standardizedFileURL.path(percentEncoded: false)
        let path = url.standardizedFileURL.path(percentEncoded: false)
        guard path == root || path.hasPrefix("\(root)/") else {
            throw ElectricalSignoffReleaseGateError.invalidRequest("artifact is outside the project root: \(path)")
        }
        let relative = String(path.dropFirst(root.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !relative.isEmpty else {
            throw ElectricalSignoffReleaseGateError.invalidRequest("artifact path resolves to the project root")
        }
        return relative
    }

    private func verifiedReference(
        _ reference: XcircuiteFileReference,
        context: FlowExecutionContext
    ) throws -> XcircuiteFileReference {
        try context.packageStore.fileReference(
            forProjectRelativePath: reference.path,
            artifactID: reference.artifactID,
            kind: reference.kind,
            format: reference.format,
            inProjectAt: context.projectRoot,
            producedByRunID: reference.producedByRunID,
            verifiedByRunID: context.runID
        )
    }

    private func failureResult(stageID: String, code: String, message: String) -> FlowStageResult {
        let diagnostic = FlowDiagnostic(severity: .error, code: code, message: message)
        return FlowStageResult(
            stageID: stageID,
            status: .failed,
            diagnostics: [diagnostic],
            gates: [FlowGateResult(gateID: "electrical-signoff-release", status: .failed, diagnostics: [diagnostic])]
        )
    }
}
