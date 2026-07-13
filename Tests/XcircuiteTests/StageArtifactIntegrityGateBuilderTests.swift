import Foundation
import Testing
import CircuiteFoundation
@testable import Xcircuite

@Suite("Stage artifact integrity gate")
struct StageArtifactIntegrityGateBuilderTests {
    @Test
    func foundationDiagnosticsPreserveArtifactIdentity() throws {
        let root = try makeTemporaryRoot()
        defer { removeTemporaryRoot(root) }

        let artifactPath = ".xcircuite/runs/run-1/report.json"
        let artifactURL = root.appending(path: artifactPath)
        try FileManager.default.createDirectory(
            at: artifactURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("before".utf8).write(to: artifactURL)

        let locator = ArtifactLocator(
            location: try ArtifactLocation(workspaceRelativePath: artifactPath),
            role: .output,
            kind: .report,
            format: .json
        )
        let reference = try LocalArtifactReferencer().reference(locator, relativeTo: root)
        try Data("change".utf8).write(to: artifactURL)

        let builder = StageArtifactIntegrityGateBuilder()
        let diagnostics = builder.diagnostics(for: [reference], projectRoot: root)
        let diagnostic = try #require(diagnostics.first)

        #expect(diagnostic.code.rawValue == "ARTIFACT_INTEGRITY_SHA256_MISMATCH")
        #expect(diagnostic.artifactID == reference.id)
        #expect(diagnostic.detail?.contains(reference.path) == true)
        #expect(builder.gate(for: [reference], projectRoot: root).status == .failed)
    }

    @Test
    func foundationGatePassesForMatchingArtifact() throws {
        let root = try makeTemporaryRoot()
        defer { removeTemporaryRoot(root) }

        let artifactPath = ".xcircuite/runs/run-1/report.json"
        let artifactURL = root.appending(path: artifactPath)
        try FileManager.default.createDirectory(
            at: artifactURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("stable".utf8).write(to: artifactURL)

        let locator = ArtifactLocator(
            location: try ArtifactLocation(workspaceRelativePath: artifactPath),
            role: .output,
            kind: .report,
            format: .json
        )
        let reference = try LocalArtifactReferencer().reference(locator, relativeTo: root)
        let gate = StageArtifactIntegrityGateBuilder().gate(for: [reference], projectRoot: root)

        #expect(gate.status == .passed)
        #expect(StageArtifactIntegrityGateBuilder().diagnostics(for: [reference], projectRoot: root).isEmpty)
    }

    private func makeTemporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func removeTemporaryRoot(_ root: URL) {
        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            Issue.record("Failed to remove temporary root: \(error.localizedDescription)")
        }
    }
}
