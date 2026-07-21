import DesignFlowKernel
import ReleaseCore

public protocol ReleaseSignoffEvidenceAssembling: Sendable {
    func assemble(
        _ request: ReleaseSignoffEvidenceAssemblyRequest,
        reading artifacts: any FlowArtifactPersisting
    ) async throws -> [ReleaseSignoffEvidenceReference]
}
