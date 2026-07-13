import Foundation
import Testing
import CircuiteFoundation
@testable import Xcircuite

@Suite("XcircuiteWorkspaceStore")
struct XcircuiteWorkspaceStoreTests {
    @Test
    func writesAndReadsProjectLocalArtifacts() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { remove(root) }

        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        try await store.write(Data("artifact".utf8), to: "runs/run-1/report.json")
        #expect(try await store.read(from: "runs/run-1/report.json") == Data("artifact".utf8))
    }

    @Test
    func rejectsTraversalAndAbsolutePaths() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { remove(root) }

        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        await #expect(throws: XcircuiteWorkspaceStoreError.invalidRelativePath("../outside")) {
            try await store.write(Data(), to: "../outside")
        }
        await #expect(throws: XcircuiteWorkspaceStoreError.invalidRelativePath("/tmp/outside")) {
            try await store.write(Data(), to: "/tmp/outside")
        }
    }

    @Test
    func rejectsSymlinkEscape() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let outside = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer {
            remove(root)
            remove(outside)
        }

        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        try await store.ensureWorkspace()
        let link = root.appending(path: ".xcircuite/escape", directoryHint: .isDirectory)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        await #expect(throws: XcircuiteWorkspaceStoreError.pathOutsideWorkspace("escape/file")) {
            try await store.write(Data(), to: "escape/file")
        }
    }

    @Test
    func verifiesArtifactDigestAndByteCount() async throws {
        let root = try makeTemporaryRoot()
        defer { remove(root) }

        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let path = "runs/run-1/report.json"
        let data = Data("artifact".utf8)
        try await store.write(data, to: path)
        let reference = try await makeReference(for: path, store: store)

        let integrity = try await store.verify(reference)
        #expect(integrity.isVerified)
        #expect(integrity.issues.isEmpty)
    }

    @Test
    func rejectsArtifactDigestMismatch() async throws {
        let root = try makeTemporaryRoot()
        defer { remove(root) }

        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let path = "runs/run-1/report.json"
        try await store.write(Data("artifact".utf8), to: path)
        let reference = try await makeReference(for: path, store: store)
        try await store.write(Data("tampered".utf8), to: path)

        do {
            _ = try await store.verify(reference)
            Issue.record("Expected digest verification to fail.")
        } catch let error as XcircuiteWorkspaceStoreError {
            guard case .artifactIntegrityFailed(_, let issues) = error else {
                Issue.record("Unexpected workspace error: \(error.localizedDescription)")
                return
            }
            #expect(issues.contains { $0.code == .digestMismatch })
        }
    }

    @Test
    func rejectsArtifactByteCountMismatch() async throws {
        let root = try makeTemporaryRoot()
        defer { remove(root) }

        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let path = "runs/run-1/report.json"
        let data = Data("artifact".utf8)
        try await store.write(data, to: path)
        let reference = try await makeReference(for: path, store: store)
        try await store.write(Data("changed-byte-count".utf8), to: path)

        do {
            _ = try await store.verify(reference)
            Issue.record("Expected byte-count verification to fail.")
        } catch let error as XcircuiteWorkspaceStoreError {
            guard case .artifactIntegrityFailed(_, let issues) = error else {
                Issue.record("Unexpected workspace error: \(error.localizedDescription)")
                return
            }
            #expect(issues.contains { $0.code == .byteCountMismatch })
        }
    }

    @Test
    func rejectsMissingArtifact() async throws {
        let root = try makeTemporaryRoot()
        defer { remove(root) }

        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let path = "runs/run-1/missing.json"
        let locator = ArtifactLocator(
            location: try ArtifactLocation(workspaceRelativePath: path),
            role: .output,
            kind: .report,
            format: .json
        )
        let digest = try ContentDigest(
            algorithm: .sha256,
            hexadecimalValue: String(repeating: "0", count: 64)
        )
        let reference = ArtifactReference(
            locator: locator,
            digest: digest,
            byteCount: 0
        )

        await #expect(throws: XcircuiteWorkspaceStoreError.missingArtifact(path)) {
            _ = try await store.verify(reference)
        }
    }

    private func makeTemporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeReference(
        for path: String,
        store: XcircuiteWorkspaceStore
    ) async throws -> ArtifactReference {
        let locator = ArtifactLocator(
            location: try ArtifactLocation(workspaceRelativePath: path),
            role: .output,
            kind: .report,
            format: .json
        )
        return try LocalArtifactReferencer().reference(
            locator,
            relativeTo: await store.workspaceRoot
        )
    }

    private func remove(_ url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Issue.record("Failed to clean up temporary workspace: \(error.localizedDescription)")
        }
    }
}
