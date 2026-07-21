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
        axes: [ElectricalSignoffAnalysisAxis] = ElectricalSignoffEngine.supportedAxes,
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
        try await context.checkCancellation()
        guard stage.stageID == stageID else {
            return failureResult(stageID: stage.stageID, code: "ELECTRICAL_SIGNOFF_STAGE_MISMATCH", message: "The configured electrical signoff stage does not match the requested stage.")
        }
        guard request.runID == context.runID else {
            return failureResult(stageID: stage.stageID, code: "ELECTRICAL_SIGNOFF_RUN_MISMATCH", message: "The electrical signoff request run ID does not match the flow run.")
        }
        do {
            try FlowIdentifierValidator().validate(stageID, kind: .stageID)
            try FlowIdentifierValidator().validate(toolID, kind: .toolID)
            guard !axes.isEmpty, Set(axes).count == axes.count else {
                throw ElectricalSignoffError.invalidConfiguration(
                    "electrical signoff axes must be non-empty and unique"
                )
            }
        } catch {
            return failureResult(stageID: stage.stageID, code: "ELECTRICAL_SIGNOFF_IDENTIFIER_INVALID", message: error.localizedDescription)
        }

        let runResult: ElectricalSignoffRunResult
        do {
            runResult = try await engine.execute(request, axes: axes)
            try runResult.validate()
            try await context.checkCancellation()
        } catch let cancellationError as FlowRunCancellationError {
            throw cancellationError
        } catch {
            return failureResult(stageID: stage.stageID, code: "ELECTRICAL_SIGNOFF_EXECUTION_ERROR", message: error.localizedDescription)
        }

        var diagnostics: [FlowDiagnostic] = []
        var gates: [FlowGateResult] = []
        let requestArtifact = try await persistRequest(context: context)
        let persistedRunResult = try await persistRunResult(runResult, context: context)
        var artifacts = runResult.artifacts + [requestArtifact, persistedRunResult]
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
            diagnostics.append(contentsOf: evidenceDiagnostics.isEmpty ? axisDiagnostics : evidenceDiagnostics)
            let gateDiagnostics = evidenceDiagnostics.isEmpty ? axisDiagnostics : evidenceDiagnostics
            if axis == .powerIntegrity {
                gates.append(FlowGateResult(
                    gateID: "electromigration",
                    status: powerIntegrityGateStatus(
                        for: evidenceEnvelopes,
                        metricNames: ["segment-current-density", "via-current-density"],
                        findingPrefix: "electrical.em."
                    ),
                    diagnostics: gateDiagnostics.filter { $0.code.hasPrefix("electrical.em.") }
                ))
                gates.append(FlowGateResult(
                    gateID: "ir-drop",
                    status: powerIntegrityGateStatus(
                        for: evidenceEnvelopes,
                        metricNames: ["static-ir-drop", "dynamic-ir-drop"],
                        findingPrefix: "electrical.ir."
                    ),
                    diagnostics: gateDiagnostics.filter { $0.code.hasPrefix("electrical.ir.") }
                ))
            } else {
                gates.append(FlowGateResult(
                    gateID: axis.rawValue,
                    status: gateStatus(for: envelope),
                    diagnostics: gateDiagnostics
                ))
            }
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
            let repairPlanReference = try await persistRepairPlan(repairPlan, context: context)
            artifacts.append(repairPlanReference)
            diagnostics.append(FlowDiagnostic(
                severity: .warning,
                code: "ELECTRICAL_SIGNOFF_REPAIR_PLAN_AVAILABLE",
                message: "Typed electrical repair candidates were retained for human or agent review; applying one requires a new immutable design revision."
            ))
        }
        let integrityGate = StageArtifactIntegrityGateBuilder().gate(
            for: artifacts,
            projectRoot: try context.xcircuiteProjectRoot()
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

    private func powerIntegrityGateStatus(
        for results: [ElectricalSignoffResult],
        metricNames: Set<String>,
        findingPrefix: String
    ) -> FlowGateStatus {
        if results.contains(where: { $0.status == .blocked || $0.status == .cancelled }) {
            return .blocked
        }
        if results.contains(where: { $0.status == .failed }) {
            return .failed
        }
        for result in results {
            let metrics = result.payload.metrics.filter { metricNames.contains($0.name) }
            guard Set(metrics.map(\.name)) == metricNames else {
                return .blocked
            }
            if metrics.contains(where: { $0.passed != true })
                || result.payload.findings.contains(where: { $0.code.hasPrefix(findingPrefix) }) {
                return .failed
            }
        }
        return .passed
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
    ) async throws -> ArtifactReference {
        try await persist(
            plan,
            artifactID: "electrical-signoff-repair-plan",
            fileName: "repair-plan.json",
            context: context
        )
    }

    private func persistRunResult(
        _ runResult: ElectricalSignoffRunResult,
        context: FlowExecutionContext
    ) async throws -> ArtifactReference {
        try await persist(
            runResult,
            artifactID: "electrical-signoff-run-result",
            fileName: "run-result.json",
            context: context,
            producer: runResult.provenance.producer,
            mode: .replaceable
        )
    }

    private func persistRequest(
        context: FlowExecutionContext
    ) async throws -> ArtifactReference {
        try await persist(
            request,
            artifactID: "electrical-signoff-request",
            fileName: "request.json",
            context: context,
            mode: .immutable,
            role: .input,
            kind: .request
        )
    }

    private func persist<Value: Encodable>(
        _ value: Value,
        artifactID: String,
        fileName: String,
        context: FlowExecutionContext,
        producer: ProducerIdentity? = nil,
        mode: FlowArtifactPersistenceMode = .replaceable,
        role: ArtifactRole = .output,
        kind: ArtifactKind = .report
    ) async throws -> ArtifactReference {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let content = try encoder.encode(value)
        let locator = ArtifactLocator(
            location: try ArtifactLocation(
                workspaceRelativePath: ".xcircuite/runs/\(context.runID)/electrical-signoff/\(fileName)"
            ),
            role: role,
            kind: kind,
            format: .json
        )
        if let producer {
            return try await context.infrastructure.persistArtifact(
                content: content,
                id: ArtifactID(rawValue: artifactID),
                locator: locator,
                runID: context.runID,
                producer: producer,
                mode: mode
            )
        }
        return try await context.infrastructure.persistArtifact(
            content: content,
            id: ArtifactID(rawValue: artifactID),
            locator: locator,
            runID: context.runID,
            mode: mode
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
