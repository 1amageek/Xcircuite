import Foundation
import CircuiteFoundation
import DesignFlowKernel
import Testing
@testable import Xcircuite

@Suite("Xcircuite project manifest contract")
struct XcircuiteProjectManifestContractTests {
    @Test
    func canonicalFixtureDecodesAndRoundTrips() throws {
        let fixtureURL = try #require(Bundle.module.url(
            forResource: "xcircuite-project-manifest-v2",
            withExtension: "json",
            subdirectory: "Fixtures/ProjectManifest"
        ))
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

    @Test
    func sharedPhysicalFileCanHaveDistinctArtifactRoles() throws {
        let location = try ArtifactLocation(workspaceRelativePath: "waveforms/shared.csv")
        let digest = try SHA256ContentDigester().digest(
            data: Data("waveform".utf8),
            using: .sha256
        )
        let input = ArtifactReference(
            id: try ArtifactID(rawValue: "waveform-input"),
            locator: ArtifactLocator(
                location: location,
                role: .input,
                kind: .waveform,
                format: .csv
            ),
            digest: digest,
            byteCount: 8
        )
        let output = ArtifactReference(
            id: try ArtifactID(rawValue: "waveform-output"),
            locator: ArtifactLocator(
                location: location,
                role: .output,
                kind: .waveform,
                format: .csv
            ),
            digest: digest,
            byteCount: 8
        )
        let manifest = XcircuiteProjectManifest(
            identity: FlowProjectIdentity(
                projectID: "shared-role-project",
                displayName: "Shared role project",
                topDesignName: "TOP"
            ),
            files: [input, output]
        )

        try manifest.validate()
        #expect(try JSONDecoder().decode(
            XcircuiteProjectManifest.self,
            from: JSONEncoder().encode(manifest)
        ) == manifest)
    }

}
