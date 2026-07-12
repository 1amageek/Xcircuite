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
    public var pexTechnologyByCorner: [String: XcircuitePEXTechnologySpec]
    public var metadata: [String: String]?

    private enum CodingKeys: String, CodingKey {
        case profileID
        case pdkID
        case technologyCatalogID
        case technologyCatalogPath
        case drcTechnologyInput
        case lvsTechnologyInput
        case pexTechnology
        case pexTechnologyByCorner
        case metadata
    }

    public init(
        profileID: String? = nil,
        pdkID: String? = nil,
        technologyCatalogID: String? = nil,
        technologyCatalogPath: String? = nil,
        drcTechnologyInput: XcircuiteFlowInputReference? = nil,
        lvsTechnologyInput: XcircuiteFlowInputReference? = nil,
        pexTechnology: XcircuitePEXTechnologySpec? = nil,
        pexTechnologyByCorner: [String: XcircuitePEXTechnologySpec] = [:],
        metadata: [String: String]? = nil
    ) {
        self.profileID = profileID
        self.pdkID = pdkID
        self.technologyCatalogID = technologyCatalogID
        self.technologyCatalogPath = technologyCatalogPath
        self.drcTechnologyInput = drcTechnologyInput
        self.lvsTechnologyInput = lvsTechnologyInput
        self.pexTechnology = pexTechnology
        self.pexTechnologyByCorner = pexTechnologyByCorner
        self.metadata = metadata
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        profileID = try container.decodeIfPresent(String.self, forKey: .profileID)
        pdkID = try container.decodeIfPresent(String.self, forKey: .pdkID)
        technologyCatalogID = try container.decodeIfPresent(String.self, forKey: .technologyCatalogID)
        technologyCatalogPath = try container.decodeIfPresent(String.self, forKey: .technologyCatalogPath)
        drcTechnologyInput = try container.decodeIfPresent(
            XcircuiteFlowInputReference.self,
            forKey: .drcTechnologyInput
        )
        lvsTechnologyInput = try container.decodeIfPresent(
            XcircuiteFlowInputReference.self,
            forKey: .lvsTechnologyInput
        )
        pexTechnology = try container.decodeIfPresent(
            XcircuitePEXTechnologySpec.self,
            forKey: .pexTechnology
        )
        pexTechnologyByCorner = try container.decodeIfPresent(
            [String: XcircuitePEXTechnologySpec].self,
            forKey: .pexTechnologyByCorner
        ) ?? [:]
        metadata = try container.decodeIfPresent([String: String].self, forKey: .metadata)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(profileID, forKey: .profileID)
        try container.encodeIfPresent(pdkID, forKey: .pdkID)
        try container.encodeIfPresent(technologyCatalogID, forKey: .technologyCatalogID)
        try container.encodeIfPresent(technologyCatalogPath, forKey: .technologyCatalogPath)
        try container.encodeIfPresent(drcTechnologyInput, forKey: .drcTechnologyInput)
        try container.encodeIfPresent(lvsTechnologyInput, forKey: .lvsTechnologyInput)
        try container.encodeIfPresent(pexTechnology, forKey: .pexTechnology)
        try container.encode(pexTechnologyByCorner, forKey: .pexTechnologyByCorner)
        try container.encodeIfPresent(metadata, forKey: .metadata)
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
            pexTechnologyByCorner: pexTechnologyByCorner.mapValues { $0.flowToolchainTechnologyRecord() },
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
