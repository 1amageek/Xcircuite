public struct XcircuiteLVSExtractionArtifacts: Sendable, Hashable, Codable {
    public var profileInput: XcircuiteFlowInputReference
    public var deckInput: XcircuiteFlowInputReference
    public var processProfileID: String

    public init(
        profileInput: XcircuiteFlowInputReference,
        deckInput: XcircuiteFlowInputReference,
        processProfileID: String
    ) {
        self.profileInput = profileInput
        self.deckInput = deckInput
        self.processProfileID = processProfileID
    }
}
