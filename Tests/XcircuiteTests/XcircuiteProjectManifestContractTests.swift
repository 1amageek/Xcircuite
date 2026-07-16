import Foundation
import Testing
@testable import Xcircuite

@Suite("Xcircuite project manifest contract")
struct XcircuiteProjectManifestContractTests {
    @Test
    func canonicalFixtureDecodesAndRoundTrips() throws {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "Fixtures/ProjectManifest/xcircuite-project-manifest-v2.json")
        let data = try Data(contentsOf: fixtureURL)
        let manifest = try JSONDecoder().decode(XcircuiteProjectManifest.self, from: data)

        #expect(manifest.schemaVersion == XcircuiteProjectManifest.currentSchemaVersion)
        #expect(manifest.files.count == 1)
        #expect(manifest.files[0].id.rawValue == "source-netlist")
        #expect(manifest.files[0].locator.role == .input)
        #expect(manifest.files[0].locator.location.value == "netlists/top.spice")

        let encoded = try JSONEncoder().encode(manifest)
        #expect(try JSONDecoder().decode(XcircuiteProjectManifest.self, from: encoded) == manifest)
    }

    @Test
    func obsoleteFlatArtifactSchemaIsRejected() throws {
        let obsolete = Data(
            """
            {
              "schemaVersion": 1,
              "identity": {
                "projectID": "obsolete-project",
                "displayName": "Obsolete",
                "topDesignName": "TOP"
              },
              "files": [],
              "runs": []
            }
            """.utf8
        )

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(XcircuiteProjectManifest.self, from: obsolete)
        }
    }

}
