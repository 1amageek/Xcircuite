import Foundation
import Testing
@testable import Xcircuite

@Suite("Xcircuite workspace project identity")
struct XcircuiteWorkspaceStoreProjectIdentityTests {
    @Test("Updating the top design preserves the remaining project identity")
    func updatesTopDesignName() async throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer {
            do {
                try FileManager.default.removeItem(at: projectRoot)
            } catch {
                Issue.record("Failed to remove test workspace: \(error)")
            }
        }

        let store = try XcircuiteWorkspaceStore(projectRoot: projectRoot)
        try await store.createWorkspace()
        let original = try await store.loadManifest()

        try await store.updateTopDesignName("signal_chain")

        let updated = try await store.loadManifest()
        #expect(updated.identity.projectID == original.identity.projectID)
        #expect(updated.identity.displayName == original.identity.displayName)
        #expect(updated.identity.topDesignName == "signal_chain")
    }

    @Test("An empty top design is rejected without changing the manifest")
    func rejectsEmptyTopDesignName() async throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer {
            do {
                try FileManager.default.removeItem(at: projectRoot)
            } catch {
                Issue.record("Failed to remove test workspace: \(error)")
            }
        }

        let store = try XcircuiteWorkspaceStore(projectRoot: projectRoot)
        try await store.createWorkspace()
        let original = try await store.loadManifest()

        await #expect(throws: XcircuiteWorkspaceStoreError.self) {
            try await store.updateTopDesignName("  \n")
        }
        #expect(try await store.loadManifest() == original)
    }
}
