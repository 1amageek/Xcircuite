import DesignFlowKernel
import ElectricalSignoffCore
import ElectricalSignoffEngine
import Foundation
import XcircuitePackage

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
        var artifacts: [XcircuiteFileReference] = [try persistRunResult(runResult, context: context)]
        for axis in axes {
            guard let envelope = runResult.axisResults[axis] else {
                let diagnostic = FlowDiagnostic(severity: .error, code: "ELECTRICAL_SIGNOFF_AXIS_MISSING", message: "The electrical signoff result did not contain the requested axis \(axis.rawValue).")
                diagnostics.append(diagnostic)
                gates.append(FlowGateResult(gateID: axis.rawValue, status: .blocked, diagnostics: [diagnostic]))
                continue
            }
            let axisDiagnostics = envelope.diagnostics.map { diagnostic in
                FlowDiagnostic(severity: flowSeverity(for: diagnostic.severity), code: diagnostic.code, message: diagnostic.message)
            }
            let cornerEnvelopes = runResult.cornerResults.values.compactMap { $0[axis] }
            let evidenceEnvelopes = cornerEnvelopes.isEmpty ? [envelope] : cornerEnvelopes
            let evidenceDiagnostics = evidenceEnvelopes.flatMap { candidate in
                candidate.diagnostics.map { diagnostic in
                    FlowDiagnostic(severity: flowSeverity(for: diagnostic.severity), code: diagnostic.code, message: diagnostic.message)
                }
            }
            let gateStatus = gateStatus(for: envelope)
            diagnostics.append(contentsOf: evidenceDiagnostics.isEmpty ? axisDiagnostics : evidenceDiagnostics)
            gates.append(FlowGateResult(gateID: axis.rawValue, status: gateStatus, diagnostics: evidenceDiagnostics.isEmpty ? axisDiagnostics : evidenceDiagnostics))
            artifacts.append(contentsOf: evidenceEnvelopes.flatMap(\.artifacts))
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
        let stageStatus: FlowStageStatus
        if gates.contains(where: { $0.status == .blocked }) {
            stageStatus = .blocked
        } else if gates.contains(where: { $0.status == .failed }) {
            stageStatus = .failed
        } else {
            stageStatus = .succeeded
        }
        return FlowStageResult(
            stageID: stage.stageID,
            status: stageStatus,
            diagnostics: diagnostics,
            gates: gates,
            artifacts: artifacts
        )
    }

    private func gateStatus(for envelope: XcircuiteEngineResultEnvelope<ElectricalSignoffPayload>) -> FlowGateStatus {
        switch envelope.status {
        case .completed:
            return envelope.payload.violationCount == 0 ? .passed : .failed
        case .blocked:
            return .blocked
        case .failed, .cancelled:
            return .failed
        }
    }

    private func flowSeverity(for severity: XcircuiteEngineDiagnosticSeverity) -> FlowDiagnosticSeverity {
        switch severity {
        case .info: return .info
        case .warning: return .warning
        case .error: return .error
        }
    }

    private func persistRepairPlan(
        _ plan: ElectricalSignoffRepairPlan,
        context: FlowExecutionContext
    ) throws -> XcircuiteFileReference {
        let relativeDirectory = ".xcircuite/runs/\(context.runID)/electrical-signoff"
        let relativePath = "\(relativeDirectory)/repair-plan.json"
        let fileURL = try context.packageStore.url(
            forProjectRelativePath: relativePath,
            inProjectAt: context.projectRoot
        )
        try context.packageStore.ensureDirectory(at: fileURL.deletingLastPathComponent())
        try context.packageStore.writeJSON(plan, to: fileURL, forProjectAt: context.projectRoot)
        return try context.packageStore.fileReference(
            forProjectRelativePath: relativePath,
            artifactID: "electrical-signoff-repair-plan",
            kind: .report,
            format: .json,
            inProjectAt: context.projectRoot,
            producedByRunID: context.runID,
            verifiedByRunID: context.runID
        )
    }

    private func persistRunResult(
        _ runResult: ElectricalSignoffRunResult,
        context: FlowExecutionContext
    ) throws -> XcircuiteFileReference {
        let relativeDirectory = ".xcircuite/runs/\(context.runID)/electrical-signoff"
        let relativePath = "\(relativeDirectory)/run-result.json"
        let fileURL = try context.packageStore.url(
            forProjectRelativePath: relativePath,
            inProjectAt: context.projectRoot
        )
        try context.packageStore.ensureDirectory(at: fileURL.deletingLastPathComponent())
        try context.packageStore.writeJSON(runResult, to: fileURL, forProjectAt: context.projectRoot)
        return try context.packageStore.fileReference(
            forProjectRelativePath: relativePath,
            artifactID: "electrical-signoff-run-result",
            kind: .report,
            format: .json,
            inProjectAt: context.projectRoot,
            producedByRunID: context.runID,
            verifiedByRunID: context.runID
        )
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
