import Foundation

public struct XcircuiteGeneratedLayoutFailureLadderRequest: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var ladderID: String
    public var runID: String
    public var expectedStageFamilies: [String: XcircuiteGeneratedLayoutSignoffStageFamily]

    public init(
        schemaVersion: Int = 1,
        ladderID: String,
        runID: String,
        expectedStageFamilies: [String: XcircuiteGeneratedLayoutSignoffStageFamily] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.ladderID = ladderID
        self.runID = runID
        self.expectedStageFamilies = expectedStageFamilies
    }
}
