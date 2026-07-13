import DesignFlowKernel
import Foundation
import PhysicalDesignCore
import PhysicalDesignEngine
import XcircuitePackage

public struct PhysicalDesignFlowStageExecutor: FlowStageExecutor {
    public let stageID: String
    public let toolID: String
    private let requestInput: XcircuiteFlowInputReference
    private let allowedStages: Set<PhysicalDesignStage>
    private let injectedEngine: (any PhysicalDesignStageExecuting)?

    public init(
        stageID: String,
        requestInput: XcircuiteFlowInputReference,
        allowedStages: Set<PhysicalDesignStage>,
        toolID: String = "physical-design",
        engine: (any PhysicalDesignStageExecuting)? = nil
    ) {
        self.stageID = stageID
        self.toolID = toolID
        self.requestInput = requestInput
        self.allowedStages = allowedStages
        self.injectedEngine = engine
    }

    public static func local(
        stageID: String,
        requestInput: XcircuiteFlowInputReference,
        toolID: String = "physical-design"
    ) -> PhysicalDesignFlowStageExecutor {
        PhysicalDesignFlowStageExecutor(
            stageID: stageID,
            requestInput: requestInput,
            allowedStages: stages(for: stageID),
            toolID: toolID
        )
    }

    public func execute(
        stage: FlowStageDefinition,
        context: FlowExecutionContext
    ) async throws -> FlowStageResult {
        do {
            try context.checkCancellation()
            try validate(stage: stage)
            let requestURL = try requestInput.resolveExisting(
                projectRoot: context.projectRoot,
                runDirectory: context.runDirectory
            )
            let requestData = try Data(contentsOf: requestURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let request = try decoder.decode(PhysicalDesignRequest.self, from: requestData)
            guard request.runID == context.runID else {
                return blockedResult(
                    stageID: stage.stageID,
                    code: "PHYSICAL_DESIGN_RUN_ID_MISMATCH",
                    message: "Physical design request run ID \(request.runID) does not match flow run \(context.runID)."
                )
            }
            guard allowedStages.contains(request.stage) else {
                return blockedResult(
                    stageID: stage.stageID,
                    code: "PHYSICAL_DESIGN_STAGE_MISMATCH",
                    message: "Request stage \(request.stage.rawValue) is not allowed for flow stage \(stage.stageID)."
                )
            }
            let engine = injectedEngine ?? PhysicalDesignEngine(
                artifactStore: FileSystemPhysicalDesignArtifactStore(projectRoot: context.projectRoot)
            )
            let envelope = try await engine.execute(request)
            try context.checkCancellation()
            let diagnostics = envelope.diagnostics.map(flowDiagnostic)
            let integrityGate = StageArtifactIntegrityGateBuilder().gate(
                for: envelope.artifacts,
                projectRoot: context.projectRoot
            )
            let allDiagnostics = diagnostics + integrityGate.diagnostics
            let stageStatus: FlowStageStatus
            switch envelope.status {
            case .completed:
                stageStatus = integrityGate.status == .passed ? .succeeded : .failed
            case .blocked:
                stageStatus = .blocked
            case .failed:
                stageStatus = .failed
            case .cancelled:
                stageStatus = .blocked
            }
            return FlowStageResult(
                stageID: stage.stageID,
                status: stageStatus,
                diagnostics: allDiagnostics,
                gates: [
                    FlowGateResult(
                        gateID: "physical-design",
                        status: gateStatus(for: envelope.status),
                        diagnostics: diagnostics
                    ),
                    integrityGate,
                ],
                artifacts: envelope.artifacts
            )
        } catch let cancellationError as FlowRunCancellationError {
            throw cancellationError
        } catch {
            return failureResult(stageID: stageID, code: "PHYSICAL_DESIGN_EXECUTION_ERROR", message: error.localizedDescription)
        }
    }

    private func validate(stage: FlowStageDefinition) throws {
        guard stage.stageID == stageID else {
            throw XcircuiteRuntimeError.stageMismatch(expected: stageID, actual: stage.stageID)
        }
        try XcircuiteIdentifierValidator().validate(stageID, kind: .stageID)
        try XcircuiteIdentifierValidator().validate(toolID, kind: .toolID)
    }

    private func flowDiagnostic(_ diagnostic: XcircuiteEngineDiagnostic) -> FlowDiagnostic {
        let entity = diagnostic.entity.map { " entity=\($0)" } ?? ""
        return FlowDiagnostic(
            severity: flowSeverity(diagnostic.severity),
            code: diagnostic.code,
            message: diagnostic.message + entity
        )
    }

    private func flowSeverity(_ severity: XcircuiteEngineDiagnosticSeverity) -> FlowDiagnosticSeverity {
        switch severity {
        case .info: .info
        case .warning: .warning
        case .error: .error
        }
    }

    private func gateStatus(for status: XcircuiteEngineExecutionStatus) -> FlowGateStatus {
        switch status {
        case .completed: .passed
        case .blocked: .blocked
        case .failed: .failed
        case .cancelled: .incomplete
        }
    }

    private func blockedResult(stageID: String, code: String, message: String) -> FlowStageResult {
        let diagnostic = FlowDiagnostic(severity: .error, code: code, message: message)
        return FlowStageResult(
            stageID: stageID,
            status: .blocked,
            diagnostics: [diagnostic],
            gates: [FlowGateResult(gateID: "physical-design", status: .blocked, diagnostics: [diagnostic])]
        )
    }

    private func failureResult(stageID: String, code: String, message: String) -> FlowStageResult {
        let diagnostic = FlowDiagnostic(severity: .error, code: code, message: message)
        return FlowStageResult(
            stageID: stageID,
            status: .failed,
            diagnostics: [diagnostic],
            gates: [FlowGateResult(gateID: "physical-design", status: .failed, diagnostics: [diagnostic])]
        )
    }

    private static func stages(for stageID: String) -> Set<PhysicalDesignStage> {
        switch stageID {
        case "physical.floorplan": [.floorplan]
        case "physical.place": [.placement]
        case "physical.power": [.powerPlanning]
        case "physical.cts": [.clockTreeSynthesis]
        case "physical.global-route": [.globalRouting]
        case "physical.detailed-route": [.detailedRouting]
        case "physical.route": [.globalRouting, .detailedRouting]
        case "physical.eco": [.timingECO, .drcRepair]
        case "physical.drc-repair": [.drcRepair]
        case "physical.antenna": [.antennaRepair]
        case "physical.dfm": [.fillInsertion, .redundantViaInsertion]
        case "physical.hotspot-repair": [.hotspotRepair]
        default: []
        }
    }
}
