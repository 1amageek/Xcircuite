import DesignFlowKernel
import PEXEngine

public struct XcircuiteFlowToolchainProfile: Sendable, Hashable, Codable {
    public var profileID: String?
    public var pdkID: String?
    public var technologyCatalogID: String?
    public var technologyCatalogPath: String?
    public var drcTechnologyInput: XcircuiteFlowInputReference?
    public var lvsTechnologyInput: XcircuiteFlowInputReference?
    public var pexTechnology: XcircuitePEXTechnologySpec?
    public var metadata: [String: String]?

    public init(
        profileID: String? = nil,
        pdkID: String? = nil,
        technologyCatalogID: String? = nil,
        technologyCatalogPath: String? = nil,
        drcTechnologyInput: XcircuiteFlowInputReference? = nil,
        lvsTechnologyInput: XcircuiteFlowInputReference? = nil,
        pexTechnology: XcircuitePEXTechnologySpec? = nil,
        metadata: [String: String]? = nil
    ) {
        self.profileID = profileID
        self.pdkID = pdkID
        self.technologyCatalogID = technologyCatalogID
        self.technologyCatalogPath = technologyCatalogPath
        self.drcTechnologyInput = drcTechnologyInput
        self.lvsTechnologyInput = lvsTechnologyInput
        self.pexTechnology = pexTechnology
        self.metadata = metadata
    }

    public func flowToolchainRecord(profileArtifactPath: String? = nil) -> FlowToolchainProfileRecord {
        FlowToolchainProfileRecord(
            profileID: profileID,
            pdkID: pdkID,
            technologyCatalogID: technologyCatalogID,
            technologyCatalogPath: technologyCatalogPath,
            profileArtifactPath: profileArtifactPath,
            drcTechnologyInput: drcTechnologyInput?.flowToolchainInputRecord(),
            lvsTechnologyInput: lvsTechnologyInput?.flowToolchainInputRecord(),
            pexTechnology: pexTechnology?.flowToolchainTechnologyRecord(),
            metadata: metadata
        )
    }
}

private extension XcircuiteFlowInputReference {
    func flowToolchainInputRecord() -> FlowToolchainInputReferenceRecord {
        switch self {
        case .path(let path):
            .path(path)
        case .stageArtifact(let artifact):
            .stageArtifact(
                FlowToolchainStageArtifactSelectorRecord(
                    stageID: artifact.stageID,
                    artifactID: artifact.artifactID,
                    kind: artifact.kind,
                    format: artifact.format,
                    pathSuffix: artifact.pathSuffix
                )
            )
        case .stageRawArtifact(let artifact):
            .stageRawArtifact(
                FlowToolchainStageRawArtifactRecord(
                    stageID: artifact.stageID,
                    relativePath: artifact.relativePath
                )
            )
        }
    }
}

private extension XcircuitePEXTechnologySpec {
    func flowToolchainTechnologyRecord() -> FlowToolchainTechnologyRecord {
        switch self {
        case .jsonFile(let path):
            .jsonFile(path: path)
        case .input(let input):
            .input(input.flowToolchainInputRecord())
        case .inline(let technology):
            .inline(
                FlowToolchainInlineTechnologyRecord(
                    processName: technology.processName,
                    layerCount: technology.stack.count,
                    viaCount: technology.vias.count,
                    logicalLayerCount: technology.logicalToPhysicalLayerMap.count,
                    backendHintKeys: technology.backendHints.keys.sorted()
                )
            )
        }
    }
}
