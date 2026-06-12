import DesignFlowKernel
import DRCEngine
import Foundation
import XcircuitePackage

public struct DRCFlowStageExecutor: FlowStageExecutor {
    public let stageID: String
    public let toolID: String
    private let request: DRCRequest
    private let engine: any DRCExecuting
    private let artifactBuilder: StageArtifactReferenceBuilder

    public init(
        stageID: String,
        toolID: String,
        request: DRCRequest,
        engine: any DRCExecuting
    ) {
        self.stageID = stageID
        self.toolID = toolID
        self.request = request
        self.engine = engine
        self.artifactBuilder = StageArtifactReferenceBuilder()
    }

    public static func pureSwift(
        stageID: String,
        layoutURL: URL,
        topCell: String,
        options: DRCOptions = DRCOptions()
    ) -> DRCFlowStageExecutor {
        DRCFlowStageExecutor(
            stageID: stageID,
            toolID: "pure-swift-drc",
            request: DRCRequest(
                layoutURL: layoutURL,
                topCell: topCell,
                backendSelection: DRCBackendSelection(backendID: "pure-swift"),
                options: options
            ),
            engine: DefaultDRCEngine(backend: nil)
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
                        gateID: "drc",
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
                        code: "DRC_EXECUTION_ERROR",
                        message: error.localizedDescription
                    ),
                ],
                gates: [
                    FlowGateResult(
                        gateID: "drc",
                        status: .failed,
                        diagnostics: [
                            FlowDiagnostic(
                                severity: .error,
                                code: "DRC_EXECUTION_ERROR",
                                message: error.localizedDescription
                            ),
                        ]
                    ),
                ]
            )
        }
    }

    private func preparedRequest(workingDirectory: URL) -> DRCRequest {
        DRCRequest(
            layoutURL: request.layoutURL,
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
        try XcircuiteIdentifierValidator().validate(stage.stageID, kind: .stageID)
        try XcircuiteIdentifierValidator().validate(toolID, kind: .toolID)
    }

    private func artifactReferences(
        from executionResult: DRCExecutionResult,
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
        return artifacts
    }

    private func gateStatus(from result: DRCResult) -> FlowGateStatus {
        if result.passed {
            return .passed
        }
        if !result.completed {
            return .incomplete
        }
        return .failed
    }

    private func flowDiagnostic(_ diagnostic: DRCDiagnostic) -> FlowDiagnostic {
        FlowDiagnostic(
            severity: flowSeverity(diagnostic.severity),
            code: diagnostic.ruleID ?? "DRC_DIAGNOSTIC",
            message: diagnostic.message
        )
    }

    private func flowSeverity(_ severity: DRCDiagnostic.Severity) -> FlowDiagnosticSeverity {
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
