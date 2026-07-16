import Foundation
import Testing
import CircuiteFoundation
import DesignFlowKernel
@testable import Xcircuite

@Suite("XcircuiteWorkspaceStore")
struct XcircuiteWorkspaceStoreTests {
    @Test
    func writesAndReadsProjectLocalArtifacts() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { remove(root) }

        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        try await store.write(Data("artifact".utf8), to: ".xcircuite/runs/run-1/report.json")
        #expect(try await store.read(from: ".xcircuite/runs/run-1/report.json") == Data("artifact".utf8))
    }

    @Test
    func writesAndReadsJSONWithIdiomaticLabels() async throws {
        let root = try makeTemporaryRoot()
        defer { remove(root) }

        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let value = ["count": 3]
        try await store.writeJSON(value, to: ".xcircuite/runs/run-1/summary.json")
        let decoded = try await store.readJSON([String: Int].self, from: ".xcircuite/runs/run-1/summary.json")

        #expect(decoded == value)
    }

    @Test
    func rejectsTraversalAndAbsolutePaths() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { remove(root) }

        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        await #expect(throws: XcircuiteWorkspaceStoreError.invalidArtifactLocation("../outside")) {
            try await store.write(Data(), to: "../outside")
        }
        await #expect(throws: XcircuiteWorkspaceStoreError.invalidArtifactLocation("/tmp/outside")) {
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
        await #expect(throws: XcircuiteWorkspaceStoreError.pathOutsideWorkspace(".xcircuite/escape/file")) {
            try await store.write(Data(), to: ".xcircuite/escape/file")
        }
    }

    @Test
    func rejectsSymbolicWorkspaceRoot() async throws {
        let root = try makeTemporaryRoot()
        let outside = try makeTemporaryRoot()
        defer {
            remove(root)
            remove(outside)
        }

        let workspace = root.appending(path: ".xcircuite", directoryHint: .isDirectory)
        try FileManager.default.createSymbolicLink(at: workspace, withDestinationURL: outside)
        let store = try XcircuiteWorkspaceStore(projectRoot: root)

        await #expect(throws: XcircuiteWorkspaceStoreError.symbolicWorkspaceRoot(workspace.path())) {
            try await store.write(Data("artifact".utf8), to: ".xcircuite/runs/run-1/report.json")
        }
    }

    @Test
    func immutableArtifactRejectsReplacement() async throws {
        let root = try makeTemporaryRoot()
        defer { remove(root) }

        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let path = ".xcircuite/runs/run-1/report.json"
        try await store.writeImmutable(Data("original".utf8), to: path)
        try await store.writeImmutable(Data("original".utf8), to: path)

        await #expect(throws: XcircuiteWorkspaceStoreError.immutableArtifactConflict(path)) {
            try await store.writeImmutable(Data("replacement".utf8), to: path)
        }
        #expect(try await store.read(from: path) == Data("original".utf8))
    }

    @Test
    func createOnlyArtifactRejectsAnIdenticalSecondWrite() async throws {
        let root = try makeTemporaryRoot()
        defer { remove(root) }

        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let runID = "run-create-only"
        let path = ".xcircuite/runs/\(runID)/archive.json"
        let content = Data("archive".utf8)
        let locator = ArtifactLocator(
            location: try ArtifactLocation(workspaceRelativePath: path),
            role: .output,
            kind: .report,
            format: .json
        )
        try await prepareTestRun(runID: runID, store: store)
        _ = try await store.persistArtifact(
            content: content,
            id: try ArtifactID(rawValue: "archive"),
            locator: locator,
            runID: runID,
            mode: .createOnly
        )

        await #expect(throws: XcircuiteWorkspaceStoreError.artifactAlreadyExists(path)) {
            _ = try await store.persistArtifact(
                content: content,
                id: try ArtifactID(rawValue: "archive"),
                locator: locator,
                runID: runID,
                mode: .createOnly
            )
        }
        #expect(try await store.read(from: path) == content)
    }

    @Test
    func independentStoresSerializeConcurrentWrites() async throws {
        let root = try makeTemporaryRoot()
        defer { remove(root) }

        let first = try XcircuiteWorkspaceStore(projectRoot: root)
        let second = try XcircuiteWorkspaceStore(projectRoot: root)
        let path = ".xcircuite/runs/run-1/ledger.json"

        async let firstWrite: Void = first.write(Data(repeating: 0x41, count: 65_536), to: path)
        async let secondWrite: Void = second.write(Data(repeating: 0x42, count: 65_536), to: path)
        _ = try await (firstWrite, secondWrite)

        let retained = try await first.read(from: path)
        #expect(
            retained == Data(repeating: 0x41, count: 65_536)
                || retained == Data(repeating: 0x42, count: 65_536)
        )
    }

    @Test
    func verifiesArtifactDigestAndByteCount() async throws {
        let root = try makeTemporaryRoot()
        defer { remove(root) }

        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let path = ".xcircuite/runs/run-1/report.json"
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
        let path = ".xcircuite/runs/run-1/report.json"
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
        let path = ".xcircuite/runs/run-1/report.json"
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
        let path = ".xcircuite/runs/run-1/missing.json"
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
            relativeTo: await store.projectRoot
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
