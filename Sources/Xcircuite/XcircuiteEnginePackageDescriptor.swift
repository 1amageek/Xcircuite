import Foundation

public struct XcircuiteEnginePackageDescriptor: Sendable, Hashable, Codable {
    public var packageID: String
    public var products: [String]
    public var stageIDs: [String]
    public var inputArtifactRoles: [String]
    public var outputArtifactRoles: [String]

    public init(
        packageID: String,
        products: [String],
        stageIDs: [String],
        inputArtifactRoles: [String],
        outputArtifactRoles: [String]
    ) {
        self.packageID = packageID
        self.products = products
        self.stageIDs = stageIDs
        self.inputArtifactRoles = inputArtifactRoles
        self.outputArtifactRoles = outputArtifactRoles
    }
}
