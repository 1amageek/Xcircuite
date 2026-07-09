import Foundation

public struct OpAmpTopologyCandidate: Sendable, Hashable, Codable {
    public struct DeviceRole: Sendable, Hashable, Codable {
        public enum DeviceKind: String, Sendable, Hashable, Codable {
            case nmos
            case pmos
            case capacitor
            case resistor
            case currentSource
        }

        public var roleID: String
        public var deviceKind: DeviceKind
        public var count: Int
        public var matchedGroupID: String?
        public var symmetryGroupID: String?
        public var notes: [String]

        public init(
            roleID: String,
            deviceKind: DeviceKind,
            count: Int,
            matchedGroupID: String? = nil,
            symmetryGroupID: String? = nil,
            notes: [String] = []
        ) {
            self.roleID = roleID
            self.deviceKind = deviceKind
            self.count = count
            self.matchedGroupID = matchedGroupID
            self.symmetryGroupID = symmetryGroupID
            self.notes = notes
        }
    }

    public struct Capability: Sendable, Hashable, Codable {
        public var metricID: OpAmpMetricID
        public var rating: Double
        public var rationale: String

        public init(metricID: OpAmpMetricID, rating: Double, rationale: String) {
            self.metricID = metricID
            self.rating = rating
            self.rationale = rationale
        }
    }

    public var topologyID: String
    public var kind: OpAmpTopologyKind
    public var label: String
    public var stageCount: Int
    public var deviceRoles: [DeviceRole]
    public var capabilities: [Capability]
    public var requiredBiases: [String]
    public var layoutIntentIDs: [String]
    public var diagnostics: [String]

    public init(
        topologyID: String,
        kind: OpAmpTopologyKind,
        label: String,
        stageCount: Int,
        deviceRoles: [DeviceRole],
        capabilities: [Capability],
        requiredBiases: [String],
        layoutIntentIDs: [String],
        diagnostics: [String] = []
    ) {
        self.topologyID = topologyID
        self.kind = kind
        self.label = label
        self.stageCount = stageCount
        self.deviceRoles = deviceRoles
        self.capabilities = capabilities
        self.requiredBiases = requiredBiases
        self.layoutIntentIDs = layoutIntentIDs
        self.diagnostics = diagnostics
    }
}
