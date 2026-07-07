import DRCEngine
import Foundation

public struct LayoutCommandDRCExportSpec: Sendable, Hashable, Codable {
    public var technologyID: String
    public var topCell: String
    public var unit: String
    public var viaDefinitions: [LayoutCommandDRCViaDefinition]
    public var rules: [NativeDRCRule]

    public init(
        technologyID: String,
        topCell: String,
        unit: String = "micrometer",
        viaDefinitions: [LayoutCommandDRCViaDefinition] = [],
        rules: [NativeDRCRule]
    ) {
        self.technologyID = technologyID
        self.topCell = topCell
        self.unit = unit
        self.viaDefinitions = viaDefinitions
        self.rules = rules
    }

    private enum CodingKeys: String, CodingKey {
        case technologyID
        case topCell
        case unit
        case viaDefinitions
        case rules
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        technologyID = try container.decode(String.self, forKey: .technologyID)
        topCell = try container.decode(String.self, forKey: .topCell)
        unit = try container.decodeIfPresent(String.self, forKey: .unit) ?? "micrometer"
        viaDefinitions = try container.decodeIfPresent(
            [LayoutCommandDRCViaDefinition].self,
            forKey: .viaDefinitions
        ) ?? []
        rules = try container.decode([NativeDRCRule].self, forKey: .rules)
    }
}

public struct LayoutCommandDRCViaDefinition: Sendable, Hashable, Codable {
    public var id: String
    public var cutLayer: String
    public var bottomLayer: String
    public var topLayer: String
    public var cutWidth: Double
    public var cutHeight: Double

    public init(
        id: String,
        cutLayer: String,
        bottomLayer: String,
        topLayer: String,
        cutWidth: Double,
        cutHeight: Double
    ) {
        self.id = id
        self.cutLayer = cutLayer
        self.bottomLayer = bottomLayer
        self.topLayer = topLayer
        self.cutWidth = cutWidth
        self.cutHeight = cutHeight
    }
}
