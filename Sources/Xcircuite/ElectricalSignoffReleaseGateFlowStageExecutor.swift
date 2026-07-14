import CircuiteFoundation
import DesignFlowKernel
import ElectricalSignoffCore
import ElectricalSignoffEngine
import ElectricalSignoffQualification
import Foundation
import ToolQualification

public struct ElectricalSignoffReleaseGateFlowStageExecutor: FlowStageExecutor {
    public let stageID: String
    public let toolID: String
    private let requestInput: XcircuiteFlowInputReference
    private let runResultInput: XcircuiteFlowInputReference
    private let qualificationSpecInput: XcircuiteFlowInputReference
    private let qualificationReportInput: XcircuiteFlowInputReference
    private let policyInput: XcircuiteFlowInputReference
    private let processQualificationEvidenceInput: XcircuiteFlowInputReference?
    private let evaluator: any ElectricalSignoffReleaseGateEvaluating

    public init(
        stageID: String = "electrical-signoff.release-gate",
        toolID: String = "native-electrical-signoff-release-gate",
        requestInput: XcircuiteFlowInputReference,
        runResultInput: XcircuiteFlowInputReference,
        qualificationSpecInput: XcircuiteFlowInputReference,
        qualificationReportInput: XcircuiteFlowInputReference,
        policyInput: XcircuiteFlowInputReference,
        processQualificationEvidenceInput: XcircuiteFlowInputReference? = nil,
        evaluator: any ElectricalSignoffReleaseGateEvaluating = DefaultElectricalSignoffReleaseGateEvaluator()
    ) {
        self.stageID = stageID
        self.toolID = toolID
        self.requestInput = requestInput
        self.runResultInput = runResultInput
        self.qualificationSpecInput = qualificationSpecInput
        self.qualificationReportInput = qualificationReportInput
        self.policyInput = policyInput
        self.processQualificationEvidenceInput = processQualificationEvidenceInput
        self.evaluator = evaluator
    }

    public func execute(
        stage: FlowStageDefinition,
        context: FlowExecutionContext
    ) async throws -> FlowStageResult {
        do {
            try context.checkCancellation()
            try validate(stage: stage, context: context)
            try validateIntegrityBoundInput(requestInput, field: "requestInput")
            try validateIntegrityBoundInput(runResultInput, field: "runResultInput")
            try validateIntegrityBoundInput(qualificationSpecInput, field: "qualificationSpecInput")
            try validateIntegrityBoundInput(qualificationReportInput, field: "qualificationReportInput")
            try validateIntegrityBoundInput(policyInput, field: "policyInput")
            if let processQualificationEvidenceInput {
                try validateIntegrityBoundInput(
                    processQualificationEvidenceInput,
                    field: "processQualificationEvidenceInput"
                )
            }
            let signoffRequest = try load(ElectricalSignoffRequest.self, from: requestInput, context: context)
            let runResult = try load(ElectricalSignoffRunResult.self, from: runResultInput, context: context)
            let qualificationSpec = try load(ElectricalSignoffQualificationSpec.self, from: qualificationSpecInput, context: context)
            let qualificationReport = try load(ElectricalSignoffQualificationReport.self, from: qualificationReportInput, context: context)
            let policy = try load(ElectricalSignoffReleaseGatePolicy.self, from: policyInput, context: context)
            let processQualificationEvidence = try processQualificationEvidenceInput.map { input in
                try load(ToolProcessQualificationEvidence.self, from: input, context: context)
            }
            try qualificationSpec.validate()
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
                LocalArtifactVerifier().verify($0, relativeTo: context.projectRoot)
            }
            let gateRequest = ElectricalSignoffReleaseGateRequest(
                runID: context.runID,
                runResult: runResult,
                qualificationSpec: qualificationSpec,
                qualificationReport: qualificationReport,
                processQualificationEvidence: processQualificationEvidence,
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
                processQualificationEvidenceInput: processQualificationEvidenceInput,
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

    private func validateIntegrityBoundInput(
        _ input: XcircuiteFlowInputReference,
        field: String
    ) throws {
        switch input {
        case .artifact(let reference):
            guard reference.sha256 != nil, reference.byteCount != nil else {
                throw ElectricalSignoffReleaseGateError.invalidRequest(
                    "\(field) must include SHA-256 and byte count"
                )
            }
        case .stageArtifact(let selector):
            guard selector.artifactID != nil else {
                throw ElectricalSignoffReleaseGateError.invalidRequest(
                    "\(field) must select an artifactID"
                )
            }
        case .path, .stageRawArtifact:
            throw ElectricalSignoffReleaseGateError.invalidRequest(
                "\(field) must be a digest-bound artifact or stageArtifact reference"
            )
        }
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
    ) throws -> ArtifactReference {
        let relativePath = ".xcircuite/runs/\(context.runID)/electrical-signoff/release-gate.json"
        let url = try context.storage.url(
            forProjectRelativePath: relativePath,
            inProjectAt: context.projectRoot
        )
        try context.storage.ensureDirectory(at: url.deletingLastPathComponent())
        try context.storage.writeJSON(result, to: url, forProjectAt: context.projectRoot)
        return try StageArtifactReferenceBuilder().reference(
            for: url,
            projectRoot: context.projectRoot,
            artifactID: "electrical-signoff-release-gate",
            kind: ArtifactKind.report,
            format: ArtifactFormat.json
        )
    }

    private func persist(
        _ bundle: ElectricalSignoffReleaseArtifactBundle,
        context: FlowExecutionContext
    ) throws -> ArtifactReference {
        let relativePath = ".xcircuite/runs/\(context.runID)/electrical-signoff/release-artifact-bundle.json"
        let url = try context.storage.url(
            forProjectRelativePath: relativePath,
            inProjectAt: context.projectRoot
        )
        try context.storage.ensureDirectory(at: url.deletingLastPathComponent())
        try context.storage.writeJSON(bundle, to: url, forProjectAt: context.projectRoot)
        return try StageArtifactReferenceBuilder().reference(
            for: url,
            projectRoot: context.projectRoot,
            artifactID: "electrical-signoff-release-artifact-bundle",
            kind: ArtifactKind.report,
            format: ArtifactFormat.json
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
        processQualificationEvidenceInput: XcircuiteFlowInputReference?,
        gateResultReference: ArtifactReference,
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
        let sourceArtifacts = uniqueCanonical(
            try requestInputs(request).map { sourceReference in
                try verifiedReference(sourceReference, context: context)
            }
        ).filter { !mandatoryPaths.contains($0.path) }
        let cornerAxisEvidence = uniqueCanonical(
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
        var qualificationArtifacts = uniqueCanonical(
            try qualificationStageArtifacts.map { sourceReference in
                try verifiedReference(
                    sourceReference,
                    context: context
                )
            }
        ).filter { !mandatoryPaths.contains($0.path) }
        if let processQualificationEvidenceInput {
            let processReference = try reference(
                for: processQualificationEvidenceInput,
                artifactID: "electrical-signoff-process-qualification-evidence",
                kind: .report,
                format: .json,
                context: context
            )
            qualificationArtifacts.append(processReference)
        }

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
        let approvalArtifacts = try context.storage.loadApprovals(
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

    private func requestInputs(_ request: ElectricalSignoffRequest) throws -> [ArtifactReference] {
        var references = request.inputs
        references.append(try request.materializedArtifact(for: request.design.artifact, role: "design"))
        references.append(request.physicalDesign.layoutArtifact)
        references.append(request.pdk.manifest)
        if let powerIntent = request.powerIntent {
            references.append(try request.materializedArtifact(for: powerIntent.artifact, role: "power-intent"))
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
        kind: ArtifactKind,
        format: ArtifactFormat,
        context: FlowExecutionContext
    ) throws -> ArtifactReference {
        switch input {
        case .artifact(let inputReference):
            _ = try input.resolveExisting(projectRoot: context.projectRoot, runDirectory: context.runDirectory)
            return ArtifactReference(
                id: try ArtifactID(rawValue: artifactID),
                locator: ArtifactLocator(
                    location: inputReference.locator.location,
                    role: .input,
                    kind: kind,
                    format: format
                ),
                digest: inputReference.digest,
                byteCount: inputReference.byteCount,
                producer: inputReference.producer
            )
        case .stageArtifact(let selector):
            let url = try input.resolveExisting(projectRoot: context.projectRoot, runDirectory: context.runDirectory)
            let resolvedPath = try projectRelativePath(for: url, projectRoot: context.projectRoot)
            let stageReferences = try stageArtifactReferences(selector: selector, context: context)
            let matches = stageReferences.filter { reference in
                reference.path == resolvedPath
                    && (selector.artifactID == nil || reference.artifactID == selector.artifactID)
            }
            guard let inputReference = matches.first, matches.count == 1 else {
                throw ElectricalSignoffReleaseGateError.invalidRequest(
                    "stage artifact reference is not uniquely addressable for \(selector.stageID)"
                )
            }
            return ArtifactReference(
                id: try ArtifactID(rawValue: artifactID),
                locator: ArtifactLocator(
                    location: inputReference.locator.location,
                    role: .input,
                    kind: kind,
                    format: format
                ),
                digest: inputReference.digest,
                byteCount: inputReference.byteCount,
                producer: inputReference.producer
            )
        case .path, .stageRawArtifact:
            throw ElectricalSignoffReleaseGateError.invalidRequest(
                "release gate inputs must be digest-bound artifact references"
            )
        }
    }

    private func stageArtifactReferences(
        selector: XcircuiteFlowInputReference.StageArtifact,
        context: FlowExecutionContext
    ) throws -> [ArtifactReference] {
        let resultURL = context.runDirectory
            .appending(path: "stages")
            .appending(path: selector.stageID)
            .appending(path: "result.json")
        let data = try Data(contentsOf: resultURL)
        return try JSONDecoder().decode(FlowStageResult.self, from: data).artifacts
    }

    private func optionalReference(
        path: String,
        artifactID: String,
        kind: ArtifactKind,
        format: ArtifactFormat,
        context: FlowExecutionContext
    ) throws -> ArtifactReference? {
        let url = try context.storage.url(forProjectRelativePath: path, inProjectAt: context.projectRoot)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return nil
        }
        return try StageArtifactReferenceBuilder().reference(
            for: url,
            projectRoot: context.projectRoot,
            artifactID: artifactID,
            kind: kind,
            format: format
        )
    }

    private func stageArtifacts(
        from input: XcircuiteFlowInputReference,
        context: FlowExecutionContext
    ) throws -> [ArtifactReference] {
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

    private func uniqueCanonical(_ references: [ArtifactReference]) -> [ArtifactReference] {
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
        _ reference: ArtifactReference,
        context: FlowExecutionContext
    ) throws -> ArtifactReference {
        let integrity = LocalArtifactVerifier().verify(reference, relativeTo: context.projectRoot)
        guard integrity.isVerified else {
            throw ElectricalSignoffReleaseGateError.invalidRequest(
                "artifact integrity verification failed for \(reference.path)"
            )
        }
        return reference
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
