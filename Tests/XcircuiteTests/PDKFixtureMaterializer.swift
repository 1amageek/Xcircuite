import Foundation
import Testing

enum PDKFixtureMaterializer {
    private static let relativePaths = [
        "invalid-pdk/pdk.json",
        "pdk-corpus.json",
        "standard-view-oracle.json",
        "valid-pdk/cells.lef",
        "valid-pdk/layer-map.json",
        "valid-pdk/layout.gds",
        "valid-pdk/models.spice",
        "valid-pdk/pdk.json",
        "valid-pdk/rules.deck",
        "valid-pdk/timing.lib",
    ]

    static func materialize(in destination: URL) throws {
        let resourceRoot = try #require(Bundle.module.url(
            forResource: "PDKKit",
            withExtension: nil,
            subdirectory: "Fixtures"
        ))

        for relativePath in relativePaths {
            let source = resourceRoot.appending(path: relativePath)
            let output = destination.appending(path: relativePath)
            try FileManager.default.createDirectory(
                at: output.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try Data(contentsOf: source)
            try data.write(to: output, options: .atomic)
        }
    }
}
