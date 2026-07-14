import CircuiteFoundation
import DesignFlowKernel
import ElectricalSignoffCore
import ElectricalSignoffEngine
import Foundation

public struct ElectricalSignoffFlowStageExecutor: FlowStageExecutor {
    public let stageID: String
    public let toolID: String
    public let axes: [ElectricalSignoffAnalysisAxis]
    private let request: ElectricalSignoffRequest
    private let engine: any ElectricalSignoffExecuting

    public init(
        stageID: String,
        toolID: String = "native-electrical-signoff",
        request: ElectricalSignoffRequest,
        axes: [ElectricalSignoffAnalysisAxis] = ElectricalSignoffEngineAPI.supportedAxes,
        engine: any ElectricalSignoffExecuting
    ) {
        self.stageID = stageID
        self.toolID = toolID
        self.request = request
        self.axes = axes.filter { $0 != .aggregate }
        self.engine = engine
    }

    public func execute(
        stage: FlowStageDefinition,
        context: FlowExecutionContext
    ) async throws -> FlowStageResult {
        try context.checkCancellation()
        guard stage.stageID == stageID else {
            return failureResult(stageID: stage.stageID, code: "ELECTRICAL_SIGNOFF_STAGE_MISMATCH", message: "The configured electrical signoff stage does not match the requested stage.")
        }
        guard request.runID == context.runID else {
            return failureResult(stageID: stage.stageID, code: "ELECTRICAL_SIGNOFF_RUN_MISMATCH", message: "The electrical signoff request run ID does not match the flow run.")
        }
        do {
            try XcircuiteIdentifierValidator().validate(stageID, kind: .stageID)
            try XcircuiteIdentifierValidator().validate(toolID, kind: .toolID)
        } catch {
            return failureResult(stageID: stage.stageID, code: "ELECTRICAL_SIGNOFF_IDENTIFIER_INVALID", message: error.localizedDescription)
        }

        let runResult: ElectricalSignoffRunResult
        do {
            runResult = try await engine.execute(request, axes: axes)
            try context.checkCancellation()
        } catch let cancellationError as FlowRunCancellationError {
            throw cancellationError
        } catch {
            return failureResult(stageID: stage.stageID, code: "ELECTRICAL_SIGNOFF_EXECUTION_ERROR", message: error.localizedDescription)
        }

        var diagnostics: [FlowDiagnostic] = []
        var gates: [FlowGateResult] = []
        let persistedRunResult = try persistRunResult(runResult, context: context)
        let foundationEvidence = try ElectricalSignoffFoundationEvidence(
            result: runResult,
            provenance: try foundationProvenance(for: runResult, request: request)
        )
        let persistedFoundationEvidence = try persistFoundationEvidence(
            foundationEvidence,
            context: context
        )
        var artifacts: [ArtifactReference] = [
            persistedRunResult,
            persistedFoundationEvidence,
        ]
        for axis in axes {
            guard let envelope = runResult.axisResults[axis] else {
                let diagnostic = FlowDiagnostic(severity: .error, code: "ELECTRICAL_SIGNOFF_AXIS_MISSING", message: "The electrical signoff result did not contain the requested axis \(axis.rawValue).")
                diagnostics.append(diagnostic)
                gates.append(FlowGateResult(gateID: axis.rawValue, status: .blocked, diagnostics: [diagnostic]))
                continue
            }
            let axisDiagnostics = envelope.diagnostics.map { diagnostic in
                FlowDiagnostic(
                    severity: flowSeverity(for: diagnostic.severity),
                    code: diagnostic.code.rawValue,
                    message: diagnostic.summary
                )
            }
            let cornerEnvelopes = runResult.cornerResults.values.compactMap { $0[axis] }
            let evidenceEnvelopes = cornerEnvelopes.isEmpty ? [envelope] : cornerEnvelopes
            let evidenceDiagnostics = evidenceEnvelopes.flatMap { candidate in
                candidate.diagnostics.map { diagnostic in
                    FlowDiagnostic(
                        severity: flowSeverity(for: diagnostic.severity),
                        code: diagnostic.code.rawValue,
                        message: diagnostic.summary
                    )
                }
            }
            let gateStatus = gateStatus(for: envelope)
            diagnostics.append(contentsOf: evidenceDiagnostics.isEmpty ? axisDiagnostics : evidenceDiagnostics)
            gates.append(FlowGateResult(gateID: axis.rawValue, status: gateStatus, diagnostics: evidenceDiagnostics.isEmpty ? axisDiagnostics : evidenceDiagnostics))
        }

        var seenArtifactPaths = Set<String>()
        artifacts = artifacts.filter { artifact in
            guard !seenArtifactPaths.contains(artifact.path) else {
                return false
            }
            seenArtifactPaths.insert(artifact.path)
            return true
        }
        let repairPlan = ElectricalSignoffRepairPlan(runResult: runResult)
        if !repairPlan.candidates.isEmpty {
            let repairPlanReference = try persistRepairPlan(repairPlan, context: context)
            artifacts.append(repairPlanReference)
            diagnostics.append(FlowDiagnostic(
                severity: .warning,
                code: "ELECTRICAL_SIGNOFF_REPAIR_PLAN_AVAILABLE",
                message: "Typed electrical repair candidates were retained for human or agent review; applying one requires a new immutable design revision."
            ))
        }
        let integrityGate = StageArtifactIntegrityGateBuilder().gate(
            for: artifacts,
            projectRoot: context.projectRoot
        )
        diagnostics.append(contentsOf: integrityGate.diagnostics)
        let stageStatus: FlowStageStatus
        if gates.contains(where: { $0.status == .blocked }) {
            stageStatus = .blocked
        } else if gates.contains(where: { $0.status == .failed }) {
            stageStatus = .failed
        } else if integrityGate.status != .passed {
            stageStatus = .failed
        } else {
            stageStatus = .succeeded
        }
        gates.append(integrityGate)
        return FlowStageResult(
            stageID: stage.stageID,
            status: stageStatus,
            diagnostics: diagnostics,
            gates: gates,
            artifacts: artifacts
        )
    }

    private func gateStatus(for result: ElectricalSignoffResult) -> FlowGateStatus {
        switch result.status {
        case .completed:
            return result.payload.violationCount == 0 ? .passed : .failed
        case .blocked:
            return .blocked
        case .failed, .cancelled:
            return .failed
        }
    }

    private func flowSeverity(for severity: DiagnosticSeverity) -> FlowDiagnosticSeverity {
        switch severity {
        case .information: return .info
        case .warning: return .warning
        case .error: return .error
        }
    }

    private func persistRepairPlan(
        _ plan: ElectricalSignoffRepairPlan,
        context: FlowExecutionContext
    ) throws -> ArtifactReference {
        let relativeDirectory = ".xcircuite/runs/\(context.runID)/electrical-signoff"
        let relativePath = "\(relativeDirectory)/repair-plan.json"
        let fileURL = try context.storage.url(
            forProjectRelativePath: relativePath,
            inProjectAt: context.projectRoot
        )
        try context.storage.ensureDirectory(at: fileURL.deletingLastPathComponent())
        try context.storage.writeJSON(plan, to: fileURL, forProjectAt: context.projectRoot)
        return try StageArtifactReferenceBuilder().reference(
            for: fileURL,
            projectRoot: context.projectRoot,
            artifactID: "electrical-signoff-repair-plan",
            kind: ArtifactKind.report,
            format: ArtifactFormat.json
        )
    }

    private func persistRunResult(
        _ runResult: ElectricalSignoffRunResult,
        context: FlowExecutionContext
    ) throws -> ArtifactReference {
        let relativeDirectory = ".xcircuite/runs/\(context.runID)/electrical-signoff"
        let relativePath = "\(relativeDirectory)/run-result.json"
        let fileURL = try context.storage.url(
            forProjectRelativePath: relativePath,
            inProjectAt: context.projectRoot
        )
        try context.storage.ensureDirectory(at: fileURL.deletingLastPathComponent())
        try context.storage.writeJSON(runResult, to: fileURL, forProjectAt: context.projectRoot)
        return try StageArtifactReferenceBuilder().reference(
            for: fileURL,
            projectRoot: context.projectRoot,
            artifactID: "electrical-signoff-run-result",
            kind: ArtifactKind.report,
            format: ArtifactFormat.json
        )
    }

    private func persistFoundationEvidence(
        _ evidence: ElectricalSignoffFoundationEvidence,
        context: FlowExecutionContext
    ) throws -> ArtifactReference {
        let relativeDirectory = ".xcircuite/runs/\(context.runID)/electrical-signoff"
        let relativePath = "\(relativeDirectory)/foundation-evidence.json"
        let fileURL = try context.storage.url(
            forProjectRelativePath: relativePath,
            inProjectAt: context.projectRoot
        )
        try context.storage.ensureDirectory(at: fileURL.deletingLastPathComponent())
        try context.storage.writeJSON(evidence, to: fileURL, forProjectAt: context.projectRoot)
        return try StageArtifactReferenceBuilder().reference(
            for: fileURL,
            projectRoot: context.projectRoot,
            artifactID: "electrical-signoff-foundation-evidence",
            kind: ArtifactKind.report,
            format: ArtifactFormat.json
        )
    }

    private func foundationProvenance(
        for runResult: ElectricalSignoffRunResult,
        request: ElectricalSignoffRequest
    ) throws -> ExecutionProvenance {
        guard let metadata = executionMetadata(from: runResult) else {
            throw ElectricalSignoffFoundationBoundaryError.invalidArtifact(
                path: "electrical-signoff-run",
                reason: "No execution metadata was produced."
            )
        }
        let designRevision: ContentDigest?
        do {
            designRevision = try ContentDigest(
                algorithm: .sha256,
                hexadecimalValue: request.design.designDigest
            )
        } catch {
            designRevision = nil
        }
        return try ExecutionProvenance(
            producer: metadata.producer,
            supportingTools: metadata.supportingTools,
            inputs: try foundationInputReferences(from: request),
            invocation: metadata.invocation,
            environment: metadata.environment,
            configurationDigest: metadata.configurationDigest,
            designRevision: designRevision,
            randomSeed: metadata.randomSeed,
            startedAt: metadata.startedAt,
            completedAt: metadata.completedAt
        )
    }

    private func foundationInputReferences(
        from request: ElectricalSignoffRequest
    ) throws -> [ArtifactReference] {
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
        if let topologyArtifact = request.topologyArtifact {
            references.append(topologyArtifact)
        }
        if let topologyProfileArtifact = request.topologyProfileArtifact {
            references.append(topologyProfileArtifact)
        }
        if let processRuleArtifact = request.processRuleArtifact {
            references.append(processRuleArtifact)
        }

        var referencesByPath: [String: ArtifactReference] = [:]
        for reference in references {
            if let existing = referencesByPath[reference.path] {
                guard existing == reference else {
                    throw ElectricalSignoffFoundationBoundaryError.conflictingArtifact(
                        path: reference.path
                    )
                }
            } else {
                referencesByPath[reference.path] = reference
            }
        }
        return referencesByPath.values
            .sorted { $0.path < $1.path }
    }

    private func executionMetadata(
        from runResult: ElectricalSignoffRunResult
    ) -> ExecutionProvenance? {
        let envelopes = runResult.axisResults
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map(\.value)
            + runResult.cornerResults
            .sorted { $0.key < $1.key }
            .flatMap { _, values in
                values.sorted { $0.key.rawValue < $1.key.rawValue }.map(\.value)
            }
        guard let first = envelopes.first else {
            return nil
        }
        let startedAt = envelopes.map(\.provenance.startedAt).min() ?? first.provenance.startedAt
        let completedAt = envelopes.map(\.provenance.completedAt).max() ?? first.provenance.completedAt
        do {
            return try ExecutionProvenance(
                producer: first.provenance.producer,
                supportingTools: first.provenance.supportingTools,
                inputs: first.provenance.inputs,
                invocation: first.provenance.invocation,
                environment: first.provenance.environment,
                configurationDigest: first.provenance.configurationDigest,
                designRevision: first.provenance.designRevision,
                randomSeed: first.provenance.randomSeed,
                startedAt: startedAt,
                completedAt: completedAt
            )
        } catch {
            return nil
        }
    }

    private func failureResult(stageID: String, code: String, message: String) -> FlowStageResult {
        let diagnostic = FlowDiagnostic(severity: .error, code: code, message: message)
        return FlowStageResult(
            stageID: stageID,
            status: .failed,
            diagnostics: [diagnostic],
            gates: [FlowGateResult(gateID: "electrical-signoff", status: .failed, diagnostics: [diagnostic])]
        )
    }
}
