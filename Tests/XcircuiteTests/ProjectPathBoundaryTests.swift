import Foundation
import Testing
@testable import Xcircuite
import DesignFlowKernel

@Suite("Project path boundary")
struct ProjectPathBoundaryTests {
    @Test func artifactReferenceAllowsRegularProjectFile() async throws {
        let root = try makeTemporaryRoot("path-boundary-regular")
        defer { removeTemporaryRoot(root) }
        let artifactURL = root.appending(path: "artifact.json")
        try "{}".write(to: artifactURL, atomically: true, encoding: .utf8)

        let reference = try StageArtifactReferenceBuilder().reference(
            for: artifactURL,
            projectRoot: root,
            artifactID: "artifact-json",
            kind: .report,
            format: .json,
        )

        #expect(reference.path == "artifact.json")
        #expect(reference.byteCount == 2)
        #expect(reference.sha256 != nil)
    }

    @Test func artifactReferenceRejectsSymlinkEscapingProjectBeforeHashing() async throws {
        let root = try makeTemporaryRoot("path-boundary-reference")
        defer { removeTemporaryRoot(root) }
        let externalRoot = try makeTemporaryRoot("path-boundary-external")
        defer { removeTemporaryRoot(externalRoot) }
        let missingExternalArtifact = externalRoot.appending(path: "missing-artifact.json")
        let linkURL = root.appending(path: "linked-artifact.json")
        try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: missingExternalArtifact)

        let expected = XcircuiteRuntimeError.artifactOutsideProject(
            path: linkURL.standardizedFileURL.path(percentEncoded: false),
            projectRoot: normalizedDirectoryPath(root.standardizedFileURL.path(percentEncoded: false))
        )
        #expect(throws: expected) {
            _ = try StageArtifactReferenceBuilder().reference(
                for: linkURL,
                projectRoot: root,
                artifactID: "linked-artifact-json",
                kind: .report,
                format: .json,
            )
        }
    }

    @Test func outputPathGuardRejectsSymlinkDirectoryEscapingProject() async throws {
        let root = try makeTemporaryRoot("path-boundary-output")
        defer { removeTemporaryRoot(root) }
        let externalRoot = try makeTemporaryRoot("path-boundary-output-external")
        defer { removeTemporaryRoot(externalRoot) }
        let linkDirectory = root.appending(path: "linked-output")
        try FileManager.default.createSymbolicLink(at: linkDirectory, withDestinationURL: externalRoot)

        let anchorURL = linkDirectory.appending(path: "artifact.json")
        let expected = XcircuiteRuntimeError.artifactOutsideProject(
            path: linkDirectory.standardizedFileURL.path(percentEncoded: false),
            projectRoot: root.standardizedFileURL.path(percentEncoded: false)
        )
        #expect(throws: expected) {
            _ = try StageArtifactOutputPathGuard().validateOutputDirectory(
                for: anchorURL,
                projectRoot: root
            )
        }
    }

    @Test func boundaryAllowsResolvedProjectRootSymlink() async throws {
        let actualRoot = try makeTemporaryRoot("path-boundary-actual")
        defer { removeTemporaryRoot(actualRoot) }
        let linkRoot = FileManager.default.temporaryDirectory
            .appending(path: "path-boundary-root-link-\(UUID().uuidString)")
        defer { removeTemporaryRoot(linkRoot) }
        try FileManager.default.createSymbolicLink(at: linkRoot, withDestinationURL: actualRoot)
        let artifactURL = actualRoot.appending(path: "artifact.json")
        try "{}".write(to: artifactURL, atomically: true, encoding: .utf8)

        let relativePath = try ProjectPathBoundary().relativePath(
            for: artifactURL,
            projectRoot: linkRoot
        )

        #expect(relativePath == "artifact.json")
    }

    private func makeTemporaryRoot(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func removeTemporaryRoot(_ root: URL) {
        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            Issue.record("Failed to remove temporary root \(root.path(percentEncoded: false)): \(error)")
        }
    }

    private func normalizedDirectoryPath(_ path: String) -> String {
        var result = path
        while result.count > 1, result.hasSuffix("/") {
            result.removeLast()
        }
        return result
    }
}
