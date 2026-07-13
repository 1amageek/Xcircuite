import Foundation

public struct XcircuiteMigrationReport: Sendable, Hashable, Codable {
    public let migratedFiles: [String]
    public let skippedFiles: [String]

    public init(migratedFiles: [String], skippedFiles: [String]) {
        self.migratedFiles = migratedFiles.sorted()
        self.skippedFiles = skippedFiles.sorted()
    }
}
