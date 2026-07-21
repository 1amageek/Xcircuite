import Foundation
import CircuiteFoundation
import DesignFlowKernel
import LogicIR
import PDKCore
import PhysicalDesignCore
import PhysicalDesignEngine

public struct PhysicalDesignFlowStageExecutor: FlowStageExecutor {
    public let stageID: String
    public let toolID: String
    private let requestInput: XcircuiteFlowInputReference
    private let designInput: XcircuiteFlowInputReference?
    private let constraintsInput: XcircuiteFlowInputReference?
    private let pdkInput: XcircuiteFlowInputReference?
    private let inputLayoutInput: XcircuiteFlowInputReference?
    private let allowedStages: Set<PhysicalDesignStage>
    private let injectedEngine: (any PhysicalDesignStageExecuting)?

    public init(
        stageID: String,
        requestInput: XcircuiteFlowInputReference,
        designInput: XcircuiteFlowInputReference? = nil,
        constraintsInput: XcircuiteFlowInputReference? = nil,
        pdkInput: XcircuiteFlowInputReference? = nil,
        inputLayoutInput: XcircuiteFlowInputReference? = nil,
        allowedStages: Set<PhysicalDesignStage>,
        toolID: String = "physical-design",
        engine: (any PhysicalDesignStageExecuting)? = nil
    ) {
        self.stageID = stageID
        self.toolID = toolID
        self.requestInput = requestInput
        self.designInput = designInput
        self.constraintsInput = constraintsInput
        self.pdkInput = pdkInput
        self.inputLayoutInput = inputLayoutInput
        self.allowedStages = allowedStages
        self.injectedEngine = engine
    }

    public static func local(
        stageID: String,
        requestInput: XcircuiteFlowInputReference,
        designInput: XcircuiteFlowInputReference? = nil,
        constraintsInput: XcircuiteFlowInputReference? = nil,
        pdkInput: XcircuiteFlowInputReference? = nil,
        inputLayoutInput: XcircuiteFlowInputReference? = nil,
        toolID: String = "physical-design"
    ) -> PhysicalDesignFlowStageExecutor {
        PhysicalDesignFlowStageExecutor(
            stageID: stageID,
            requestInput: requestInput,
            designInput: designInput,
            constraintsInput: constraintsInput,
            pdkInput: pdkInput,
            inputLayoutInput: inputLayoutInput,
            allowedStages: stages(for: stageID),
            toolID: toolID
        )
    }

    public func execute(
        stage: FlowStageDefinition,
        context: FlowExecutionContext
    ) async throws -> FlowStageResult {
        do {
            try await context.checkCancellation()
            try validate(stage: stage)
            let requestURL = try requestInput.resolveExisting(
                projectRoot: try context.xcircuiteProjectRoot(),
                runDirectory: try context.xcircuiteRunDirectory()
            )
            let requestData = try Data(contentsOf: requestURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let template = try decoder.decode(PhysicalDesignRequest.self, from: requestData)
            let request = try boundRequest(
                template,
                projectRoot: try context.xcircuiteProjectRoot(),
                runDirectory: try context.xcircuiteRunDirectory()
            )
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
            let requestArtifact = try await context.persistJSONArtifact(
                request,
                artifactID: "\(stageID)-request",
                stageID: stageID,
                fileName: "physical-design-request.json",
                role: .input,
                kind: .request,
                mode: .immutable
            )
            let engine: any PhysicalDesignStageExecuting
            if let injectedEngine {
                engine = injectedEngine
            } else {
                engine = PhysicalDesignEngine(
                    artifactStore: FileSystemPhysicalDesignArtifactStore(
                        projectRoot: try context.xcircuiteProjectRoot()
                    )
                )
            }
            let result = try await engine.execute(request)
            try await context.checkCancellation()
            let diagnostics = result.diagnostics.map { diagnostic in
                let severity: FlowDiagnosticSeverity
                switch diagnostic.severity {
                case .information: severity = .info
                case .warning: severity = .warning
                case .error: severity = .error
                }
                let detail = diagnostic.detail.map { value in " (\(value))" } ?? ""
                return FlowDiagnostic(
                    severity: severity,
                    code: diagnostic.code.rawValue,
                    message: diagnostic.summary + detail
                )
            }
            let resultArtifact = try await context.persistJSONArtifact(
                result,
                artifactID: "\(stageID)-domain-result",
                stageID: stageID,
                fileName: "physical-design-result.json",
                producer: result.provenance.producer,
                mode: .replaceable
            )
            let artifacts = result.artifacts + [requestArtifact, resultArtifact]
            let integrityGate = StageArtifactIntegrityGateBuilder().gate(
                for: artifacts,
                projectRoot: try context.xcircuiteProjectRoot()
            )
            let allDiagnostics = diagnostics + integrityGate.diagnostics
            let stageStatus: FlowStageStatus
            switch result.status {
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
                        status: gateStatus(for: result.status),
                        diagnostics: diagnostics
                    ),
                    integrityGate,
                ],
                artifacts: artifacts
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
        try FlowIdentifierValidator().validate(stageID, kind: .stageID)
        try FlowIdentifierValidator().validate(toolID, kind: .toolID)
    }

    private func boundRequest(
        _ template: PhysicalDesignRequest,
        projectRoot: URL,
        runDirectory: URL
    ) throws -> PhysicalDesignRequest {
        let designArtifact = try designInput?.resolveArtifactReference(
            projectRoot: projectRoot,
            runDirectory: runDirectory,
            artifactID: "physical-design-logic-input",
            kind: .netlist,
            format: .json
        ) ?? template.design.artifact
        let constraintsArtifact = try constraintsInput?.resolveArtifactReference(
            projectRoot: projectRoot,
            runDirectory: runDirectory,
            artifactID: "physical-design-constraints-input",
            kind: .constraint,
            format: .sdc
        ) ?? template.constraints
        let pdkArtifact = try pdkInput?.resolveArtifactReference(
            projectRoot: projectRoot,
            runDirectory: runDirectory,
            artifactID: "physical-design-pdk-input",
            kind: .technology,
            format: .json
        ) ?? template.pdk.manifest
        let inputLayoutArtifact = try inputLayoutInput?.resolveArtifactReference(
            projectRoot: projectRoot,
            runDirectory: runDirectory,
            artifactID: "physical-design-layout-input",
            kind: .layout
        )
        let inputLayout = inputLayoutArtifact.map {
            PhysicalDesignReference(
                layoutArtifact: $0,
                topCell: template.inputLayout?.topCell
                    ?? template.initialSnapshot?.topCell
                    ?? template.design.topDesignName,
                layoutDigest: $0.digest.hexadecimalValue
            )
        } ?? template.inputLayout
        let replacedInputs = Set([
            template.design.artifact,
            template.constraints,
            template.pdk.manifest,
        ] + (template.inputLayout.map { [$0.layoutArtifact] } ?? []))
        let additionalInputs = template.inputs.filter { !replacedInputs.contains($0) }
        return PhysicalDesignRequest(
            runID: template.runID,
            inputs: additionalInputs,
            design: LogicDesignReference(
                artifact: designArtifact,
                topDesignName: template.design.topDesignName,
                designDigest: designArtifact.digest.hexadecimalValue,
                provenance: template.design.provenance
            ),
            constraints: constraintsArtifact,
            requestedModeIDs: template.requestedModeIDs,
            pdk: PDKReference(
                manifest: pdkArtifact,
                processID: template.pdk.processID,
                version: template.pdk.version,
                digest: pdkArtifact.digest.hexadecimalValue
            ),
            inputLayout: inputLayout,
            stage: template.stage,
            configuration: template.configuration,
            initialSnapshot: template.initialSnapshot,
            executionIntent: template.executionIntent,
            clockTimingModel: template.clockTimingModel,
            productionConfiguration: template.productionConfiguration
        )
    }

    private func gateStatus(for status: PhysicalDesignExecutionStatus) -> FlowGateStatus {
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
