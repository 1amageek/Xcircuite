import DesignFlowKernel
import Foundation
import XcircuitePackage

public protocol XcircuiteEngineStageAdapting: FlowStageExecutor {
    associatedtype Engine: XcircuiteEngineExecuting

    var engine: Engine { get }

    func makeRequest(
        stage: FlowStageDefinition,
        context: FlowExecutionContext
    ) async throws -> Engine.Request

    func makeStageResult(
        envelope: XcircuiteEngineResultEnvelope<Engine.Payload>,
        stage: FlowStageDefinition,
        context: FlowExecutionContext
    ) async throws -> FlowStageResult
}
