import Foundation
import PEXEngine

public struct PlanningPEXInputs: Sendable, Hashable, Codable {
    public var layoutReferenceID: String
    public var sourceNetlistReferenceID: String
    public var technologyReferenceID: String
    public var topCell: String?
    public var layoutFormat: String?
    public var sourceNetlistFormat: String?
    public var backendID: String
    public var allowMockBackend: Bool
    public var executablePath: String?
    public var environmentOverrides: [String: String]
    public var cornerIDs: [String]
    public var options: PEXRunOptions?
    public var topNetCount: Int?

    public init(
        layoutReferenceID: String,
        sourceNetlistReferenceID: String,
        technologyReferenceID: String,
        topCell: String? = nil,
        layoutFormat: String? = nil,
        sourceNetlistFormat: String? = nil,
        backendID: String,
        allowMockBackend: Bool = false,
        executablePath: String? = nil,
        environmentOverrides: [String: String] = [:],
        cornerIDs: [String],
        options: PEXRunOptions? = nil,
        topNetCount: Int? = nil
    ) {
        self.layoutReferenceID = layoutReferenceID
        self.sourceNetlistReferenceID = sourceNetlistReferenceID
        self.technologyReferenceID = technologyReferenceID
        self.topCell = topCell
        self.layoutFormat = layoutFormat
        self.sourceNetlistFormat = sourceNetlistFormat
        self.backendID = backendID
        self.allowMockBackend = allowMockBackend
        self.executablePath = executablePath
        self.environmentOverrides = environmentOverrides
        self.cornerIDs = cornerIDs
        self.options = options
        self.topNetCount = topNetCount
    }
}
