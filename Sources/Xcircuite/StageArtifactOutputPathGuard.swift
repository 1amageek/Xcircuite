import Foundation

struct StageArtifactOutputPathGuard: Sendable {
    private let pathBoundary = ProjectPathBoundary()

    func validateOutputDirectory(for anchorURL: URL, projectRoot: URL) throws -> URL {
        let directoryURL = anchorURL.deletingLastPathComponent()
        guard pathBoundary.contains(directoryURL, projectRoot: projectRoot) else {
            throw XcircuiteRuntimeError.artifactOutsideProject(
                path: directoryURL.standardizedFileURL.path(percentEncoded: false),
                projectRoot: projectRoot.standardizedFileURL.path(percentEncoded: false)
            )
        }
        return directoryURL
    }
}
