import Foundation
import LayoutIO

public struct LayoutCommandStandardLayoutExportSpec: Sendable, Hashable, Codable {
    public var artifactID: String
    public var format: LayoutFileFormat
    public var technologyInput: XcircuiteFlowInputReference

    public init(
        artifactID: String,
        format: LayoutFileFormat,
        technologyInput: XcircuiteFlowInputReference
    ) {
        self.artifactID = artifactID
        self.format = format
        self.technologyInput = technologyInput
    }
}
