import DesignFlowKernel
import Foundation
import LVSEngine
import XcircuitePackage

public struct LVSFlowStageExecutor: FlowStageExecutor {
    public let stageID: String
    public let toolID: String
    private let request: LVSRequest
    private let engine: any LVSExecuting
    private let artifactBuilder: StageArtifactReferenceBuilder

    public init(
        stageID: String,
        toolID: String,
        request: LVSRequest,
        engine: any LVSExecuting
    ) {
        self.stageID = stageID
        self.toolID = toolID
        self.request = request
        self.engine = engine
        self.artifactBuilder = StageArtifactReferenceBuilder()
    }

    public static func pureSwift(
        stageID: String,
        layoutNetlistURL: URL,
        schematicNetlistURL: URL,
        topCell: String,
        options: LVSOptions = LVSOptions()
    ) -> LVSFlowStageExecutor {
        LVSFlowStageExecutor(
            stageID: stageID,
            toolID: "pure-swift-lvs",
            request: LVSRequest(
                layoutNetlistURL: layoutNetlistURL,
                schematicNetlistURL: schematicNetlistURL,
                topCell: topCell,
                backendSelection: LVSBackendSelection(backendID: "pure-swift"),
                options: options
            ),
            engine: DefaultLVSEngine(backend: nil, layoutNetlistExtractor: nil)
        )
    }

    public func execute(
        stage: FlowStageDefinition,
        context: FlowExecutionContext
    ) async throws -> FlowStageResult {
        do {
            try validate(stage: stage)
            let rawDirectory = context.runDirectory
                .appending(path: "stages")
                .appending(path: stage.stageID)
                .appending(path: "raw")
            try context.packageStore.ensureDirectory(at: rawDirectory)

            let executionResult = try await engine.run(preparedRequest(workingDirectory: rawDirectory))
            let artifacts = try artifactReferences(from: executionResult, context: context)
            let gateStatus = gateStatus(from: executionResult.result)
            let stageStatus: FlowStageStatus = gateStatus == .passed ? .succeeded : .failed

            return FlowStageResult(
                stageID: stage.stageID,
                status: stageStatus,
                diagnostics: executionResult.result.diagnostics.map(flowDiagnostic),
                gates: [
                    FlowGateResult(
                        gateID: "lvs",
                        status: gateStatus,
                        diagnostics: executionResult.result.diagnostics.map(flowDiagnostic)
                    ),
                ],
                artifacts: artifacts
            )
        } catch {
            return FlowStageResult(
                stageID: stage.stageID,
                status: .failed,
                diagnostics: [
                    FlowDiagnostic(
                        severity: .error,
                        code: "LVS_EXECUTION_ERROR",
                        message: error.localizedDescription
                    ),
                ],
                gates: [
                    FlowGateResult(
                        gateID: "lvs",
                        status: .failed,
                        diagnostics: [
                            FlowDiagnostic(
                                severity: .error,
                                code: "LVS_EXECUTION_ERROR",
                                message: error.localizedDescription
                            ),
                        ]
                    ),
                ]
            )
        }
    }

    private func preparedRequest(workingDirectory: URL) -> LVSRequest {
        LVSRequest(
            layoutNetlistURL: request.layoutNetlistURL,
            layoutGDSURL: request.layoutGDSURL,
            schematicNetlistURL: request.schematicNetlistURL,
            topCell: request.topCell,
            workingDirectory: workingDirectory,
            backendSelection: request.backendSelection,
            options: request.options
        )
    }

    private func validate(stage: FlowStageDefinition) throws {
        guard stage.stageID == stageID else {
            throw XcircuiteRuntimeError.stageMismatch(expected: stageID, actual: stage.stageID)
        }
        let validator = XcircuiteIdentifierValidator()
        try validator.validate(stage.stageID, kind: .stageID)
        try validator.validate(toolID, kind: .toolID)
    }

    private func artifactReferences(
        from executionResult: LVSExecutionResult,
        context: FlowExecutionContext
    ) throws -> [XcircuiteFileReference] {
        var artifacts: [XcircuiteFileReference] = []
        if let reportURL = executionResult.reportURL {
            artifacts.append(try artifactBuilder.reference(
                for: reportURL,
                projectRoot: context.projectRoot,
                kind: .report,
                format: .json,
                producedByRunID: context.runID
            ))
        }
        if let log = try artifactBuilder.optionalReference(
            for: executionResult.result.logPath,
            projectRoot: context.projectRoot,
            kind: .report,
            format: .text,
            producedByRunID: context.runID
        ) {
            artifacts.append(log)
        }
        if let extracted = executionResult.extractedLayoutNetlistURL {
            artifacts.append(try artifactBuilder.reference(
                for: extracted,
                projectRoot: context.projectRoot,
                kind: .netlist,
                format: .spice,
                producedByRunID: context.runID
            ))
        }
        return artifacts
    }

    private func gateStatus(from result: LVSResult) -> FlowGateStatus {
        if result.passed {
            return .passed
        }
        if !result.completed {
            return .incomplete
        }
        return .failed
    }

    private func flowDiagnostic(_ diagnostic: LVSDiagnostic) -> FlowDiagnostic {
        FlowDiagnostic(
            severity: flowSeverity(diagnostic.severity),
            code: diagnostic.ruleID ?? "LVS_DIAGNOSTIC",
            message: diagnostic.message
        )
    }

    private func flowSeverity(_ severity: LVSDiagnostic.Severity) -> FlowDiagnosticSeverity {
        switch severity {
        case .info:
            .info
        case .warning:
            .warning
        case .error:
            .error
        }
    }
}
