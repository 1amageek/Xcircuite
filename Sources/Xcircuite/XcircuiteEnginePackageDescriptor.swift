import Foundation
import CircuiteFoundation

public struct XcircuiteEnginePackageDescriptor: Sendable, Hashable, Codable {
    public var packageID: String
    public var products: [String]
    public var stageIDs: [String]
    public var inputArtifactRoles: [ArtifactRole]
    public var outputArtifactRoles: [ArtifactRole]

    public init(
        packageID: String,
        products: [String],
        stageIDs: [String],
        inputArtifactRoles: [ArtifactRole],
        outputArtifactRoles: [ArtifactRole]
    ) {
        self.packageID = packageID
        self.products = products
        self.stageIDs = stageIDs
        self.inputArtifactRoles = inputArtifactRoles
        self.outputArtifactRoles = outputArtifactRoles
    }
}
