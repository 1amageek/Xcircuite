import Foundation
import LayoutTech

public struct ElectricalStandardLayoutLayerMapping: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public struct Entry: Sendable, Hashable, Codable {
        public var gdsLayer: Int
        public var gdsDatatype: Int

        public init(gdsLayer: Int, gdsDatatype: Int = 0) {
            self.gdsLayer = gdsLayer
            self.gdsDatatype = gdsDatatype
        }
    }

    public var schemaVersion: Int
    public var layers: [String: Entry]

    public init(
        layers: [String: Entry],
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.layers = layers
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ElectricalStandardLayoutImportError.invalidTechnologyLayerMapping(
                "unsupported layer mapping schema version \(schemaVersion)"
            )
        }
        guard !layers.isEmpty else {
            throw ElectricalStandardLayoutImportError.invalidTechnologyLayerMapping(
                "at least one layer mapping is required"
            )
        }
        guard layers.values.allSatisfy({ $0.gdsLayer > 0 && $0.gdsDatatype >= 0 }) else {
            throw ElectricalStandardLayoutImportError.invalidTechnologyLayerMapping(
                "GDS layer must be positive and datatype must be non-negative"
            )
        }
        let layerKeys = layers.values.map { "\($0.gdsLayer):\($0.gdsDatatype)" }
        guard Set(layerKeys).count == layerKeys.count else {
            throw ElectricalStandardLayoutImportError.invalidTechnologyLayerMapping(
                "GDS layer/datatype pairs must be unique"
            )
        }
    }

    public func apply(to technology: LayoutTechDatabase) throws -> LayoutTechDatabase {
        try validate()
        let missingLayers = technology.layers.compactMap { layer -> String? in
            guard let entry = entry(for: layer) else { return layer.id.name }
            return entry.gdsLayer > 0 ? nil : layer.id.name
        }
        guard missingLayers.isEmpty else {
            throw ElectricalStandardLayoutImportError.missingTechnologyLayerMapping(missingLayers.sorted())
        }

        var mappedTechnology = technology
        for index in mappedTechnology.layers.indices {
            guard let entry = entry(for: mappedTechnology.layers[index]) else {
                continue
            }
            mappedTechnology.layers[index].gdsLayer = entry.gdsLayer
            mappedTechnology.layers[index].gdsDatatype = entry.gdsDatatype
        }
        return mappedTechnology
    }

    private func entry(for layer: LayoutLayerDefinition) -> Entry? {
        layers[layer.id.name] ?? layers[layer.displayName]
    }
}
