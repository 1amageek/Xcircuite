import DFTCore
import DFTEngine
import CircuiteFoundation
import Foundation
import DesignFlowKernel

public struct DFTFlowStageExecutor: FlowStageExecutor {
    public let stageID: String
    public let toolID: String
    public let expectedOperation: DFTOperation
    private let requestInput: XcircuiteFlowInputReference
    private let injectedEngine: (any DFTEngineExecuting)?

    public init(
        stageID: String,
        toolID: String = "dft-engine",
        requestInput: XcircuiteFlowInputReference,
        expectedOperation: DFTOperation,
        engine: (any DFTEngineExecuting)? = nil
    ) {
        self.stageID = stageID
        self.expectedOperation = expectedOperation
        self.toolID = toolID
        self.requestInput = requestInput
        self.injectedEngine = engine
    }

    public func execute(
        stage: FlowStageDefinition,
        context: FlowExecutionContext
    ) async throws -> FlowStageResult {
        do {
            try await context.checkCancellation()
            try validate(stage: stage)
            let requestURL = try await requestInput.resolveExisting(
                projectRoot: try context.xcircuiteProjectRoot(),
                runDirectory: try context.xcircuiteRunDirectory(),
                infrastructure: context.infrastructure
            )
            let requestData = try Data(contentsOf: requestURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let request = try decoder.decode(DFTRequest.self, from: requestData)
            guard request.runID == context.runID else {
                return blockedResult(
                    stageID: stage.stageID,
                    code: "DFT_RUN_ID_MISMATCH",
                    message: "DFT request run ID \(request.runID) does not match flow run \(context.runID)."
                )
            }
            guard request.operation == expectedOperation else {
                return blockedResult(
                    stageID: stage.stageID,
                    code: "DFT_OPERATION_MISMATCH",
                    message: "DFT stage \(stage.stageID) requires \(expectedOperation.rawValue), but the request declares \(request.operation.rawValue)."
                )
            }
            let inputArtifacts = uniqueArtifacts(request.executionInputArtifacts)
            for artifact in inputArtifacts {
                _ = try await context.infrastructure.loadArtifactContent(for: artifact)
            }
            let requestArtifact = try await context.persistJSONArtifact(
                request,
                artifactID: "dft-request",
                stageID: stageID,
                fileName: "dft-request.json",
                role: .input,
                kind: .request,
                mode: .immutable
            )
            let engine: any DFTEngineExecuting
            if let injectedEngine {
                engine = injectedEngine
            } else {
                engine = DefaultDFTEngine(
                    artifactStore: FileSystemDFTArtifactStore(rootURL: try context.xcircuiteProjectRoot()),
                    designLoader: FileSystemDFTDesignLoader(rootURL: try context.xcircuiteProjectRoot()),
                    cellLibraryLoader: FileSystemDFTCellLibraryLoader(rootURL: try context.xcircuiteProjectRoot()),
                    timingLibraryLoader: FileSystemDFTTimingLibraryLoader(rootURL: try context.xcircuiteProjectRoot()),
                    constraintLoader: FileSystemDFTConstraintLoader(rootURL: try context.xcircuiteProjectRoot()),
                    logicBISTCellMappingLoader: FileSystemDFTLogicBISTCellMappingLoader(
                        rootURL: try context.xcircuiteProjectRoot()
                    )
                )
            }
            let result = try await engine.execute(request)
            try DFTResultValidator().validate(result, for: request)
            if result.status == .completed {
                try await DFTResultSemanticVerifier().validate(
                    result,
                    for: request,
                    reading: FlowDFTArtifactReader(
                        infrastructure: context.infrastructure
                    )
                )
            }
            try await context.checkCancellation()
            let diagnostics = result.dftDiagnostics.map(flowDiagnostic)
            let gateStatus = gateStatus(for: result.status)
            let support = ReleaseStageExecutionSupport()
            let resultArtifact = try await support.persistResult(
                result,
                stageID: stage.stageID,
                artifactID: "dft-result",
                context: context,
                producer: result.provenance.producer,
                mode: .replaceable
            )
            let persistedArtifacts = uniqueArtifacts(
                inputArtifacts + result.artifacts + [requestArtifact, resultArtifact]
            )
            let integrityGate = StageArtifactIntegrityGateBuilder().gate(
                for: persistedArtifacts,
                projectRoot: try context.xcircuiteProjectRoot()
            )
            let allDiagnostics = diagnostics + integrityGate.diagnostics
            let status: FlowStageStatus
            switch result.status {
            case .completed:
                status = integrityGate.status == .passed ? .succeeded : .failed
            case .blocked, .cancelled:
                status = .blocked
            case .failed:
                status = .failed
            }
            return FlowStageResult(
                stageID: stage.stageID,
                status: status,
                diagnostics: allDiagnostics,
                gates: [
                    FlowGateResult(
                        gateID: "dft",
                        status: gateStatus,
                        diagnostics: diagnostics
                    ),
                    integrityGate,
                ],
                artifacts: persistedArtifacts
            )
        } catch let cancellationError as FlowRunCancellationError {
            throw cancellationError
        } catch {
            return FlowStageResult(
                stageID: stage.stageID,
                status: .failed,
                diagnostics: [
                    FlowDiagnostic(
                        severity: .error,
                        code: "DFT_EXECUTION_ERROR",
                        message: error.localizedDescription
                    )
                ],
                gates: [
                    FlowGateResult(
                        gateID: "dft",
                        status: .failed,
                        diagnostics: [
                            FlowDiagnostic(
                                severity: .error,
                                code: "DFT_EXECUTION_ERROR",
                                message: error.localizedDescription
                            )
                        ]
                    )
                ]
            )
        }
    }

    private func validate(stage: FlowStageDefinition) throws {
        guard stage.stageID == stageID else {
            throw XcircuiteRuntimeError.stageMismatch(expected: stageID, actual: stage.stageID)
        }
        try FlowIdentifierValidator().validate(stage.stageID, kind: .stageID)
        try FlowIdentifierValidator().validate(toolID, kind: .toolID)
    }

    private func flowDiagnostic(_ diagnostic: DFTDiagnostic) -> FlowDiagnostic {
        let severity: FlowDiagnosticSeverity
        switch diagnostic.severity {
        case .info: severity = .info
        case .warning: severity = .warning
        case .error: severity = .error
        }
        return FlowDiagnostic(
            severity: severity,
            code: diagnostic.code,
            message: diagnostic.message + (diagnostic.entity.map { " entity=\($0)" } ?? "")
        )
    }

    private func gateStatus(for status: DFTExecutionStatus) -> FlowGateStatus {
        switch status {
        case .completed:
            return .passed
        case .blocked:
            return .blocked
        case .cancelled:
            return .incomplete
        case .failed:
            return .failed
        }
    }

    private func uniqueArtifacts(_ artifacts: [ArtifactReference]) -> [ArtifactReference] {
        Array(Set(artifacts)).sorted { $0.path < $1.path }
    }

    private func blockedResult(
        stageID: String,
        code: String,
        message: String
    ) -> FlowStageResult {
        let diagnostic = FlowDiagnostic(severity: .error, code: code, message: message)
        return FlowStageResult(
            stageID: stageID,
            status: .blocked,
            diagnostics: [diagnostic],
            gates: [FlowGateResult(gateID: "dft", status: .blocked, diagnostics: [diagnostic])]
        )
    }
}

private struct FlowDFTArtifactReader: DFTArtifactReading {
    let infrastructure: any FlowRunInfrastructure

    func data(for reference: ArtifactReference) async throws -> Data {
        try await infrastructure.loadArtifactContent(for: reference)
    }
}
