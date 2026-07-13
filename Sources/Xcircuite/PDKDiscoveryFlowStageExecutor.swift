import DesignFlowKernel
import Foundation
import PDKCore
import PDKDiscovery
import DesignFlowKernel

public struct PDKDiscoveryFlowStageExecutor: FlowStageExecutor {
    public let stageID: String
    public let toolID: String
    private let searchRoots: [XcircuiteFlowInputReference]
    private let requiredProcessID: String?
    private let engine: any PDKDiscovering
    private let support: PDKStageExecutionSupport

    public init(
        stageID: String = "pdk.discover",
        toolID: String = "pdk-discovery",
        searchRoots: [XcircuiteFlowInputReference],
        requiredProcessID: String? = nil,
        engine: any PDKDiscovering
    ) {
        self.stageID = stageID
        self.toolID = toolID
        self.searchRoots = searchRoots
        self.requiredProcessID = requiredProcessID
        self.engine = engine
        self.support = PDKStageExecutionSupport()
    }

    public static func local(
        stageID: String = "pdk.discover",
        searchRoots: [XcircuiteFlowInputReference],
        requiredProcessID: String? = nil
    ) -> PDKDiscoveryFlowStageExecutor {
        PDKDiscoveryFlowStageExecutor(
            stageID: stageID,
            searchRoots: searchRoots,
            requiredProcessID: requiredProcessID,
            engine: LocalPDKDiscoverer()
        )
    }

    public func execute(
        stage: FlowStageDefinition,
        context: FlowExecutionContext
    ) async throws -> FlowStageResult {
        do {
            try context.checkCancellation()
            try support.validate(stage: stage, stageID: stageID, toolID: toolID)
            let resolvedRoots = try resolveSearchRoots(context: context)
            let request = PDKDiscoveryRequest(
                runID: context.runID,
                inputs: [],
                searchRoots: resolvedRoots,
                requiredProcessID: requiredProcessID
            )
            let result = try await engine.execute(request)
            try context.checkCancellation()
            let artifact = try support.persistResult(result, stageID: stageID, context: context)
            return support.stageResult(result: result, stageID: stageID, artifact: artifact)
        } catch let cancellationError as FlowRunCancellationError {
            throw cancellationError
        } catch {
            return support.failureResult(
                stageID: stageID,
                code: "PDK_DISCOVERY_EXECUTION_ERROR",
                message: error.localizedDescription
            )
        }
    }

    private func resolveSearchRoots(context: FlowExecutionContext) throws -> [String] {
        var paths: [String] = []
        for input in searchRoots {
            let url = try input.resolveExisting(
                projectRoot: context.projectRoot,
                runDirectory: context.runDirectory
            )
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw XcircuiteRuntimeError.invalidInputReference("PDK search root is not a directory: \(url.path)")
            }
            paths.append(url.path)
        }
        return paths
    }
}
