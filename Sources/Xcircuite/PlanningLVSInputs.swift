import Foundation

public struct PlanningLVSInputs: Sendable, Hashable, Codable {
    public var layoutNetlistReferenceID: String?
    public var layoutGDSReferenceID: String?
    public var schematicNetlistReferenceID: String
    public var technologyReferenceID: String?
    public var extractionProfileReferenceID: String?
    public var extractionDeckReferenceID: String?
    public var processProfileID: String?
    public var waiverReferenceID: String?
    public var modelEquivalenceReferenceID: String?
    public var terminalEquivalenceReferenceID: String?
    public var topCell: String
    public var layoutFormat: String?
    public var backendID: String?

    public init(
        layoutNetlistReferenceID: String? = nil,
        layoutGDSReferenceID: String? = nil,
        schematicNetlistReferenceID: String,
        technologyReferenceID: String? = nil,
        extractionProfileReferenceID: String? = nil,
        extractionDeckReferenceID: String? = nil,
        processProfileID: String? = nil,
        waiverReferenceID: String? = nil,
        modelEquivalenceReferenceID: String? = nil,
        terminalEquivalenceReferenceID: String? = nil,
        topCell: String,
        layoutFormat: String? = nil,
        backendID: String? = nil
    ) {
        self.layoutNetlistReferenceID = layoutNetlistReferenceID
        self.layoutGDSReferenceID = layoutGDSReferenceID
        self.schematicNetlistReferenceID = schematicNetlistReferenceID
        self.technologyReferenceID = technologyReferenceID
        self.extractionProfileReferenceID = extractionProfileReferenceID
        self.extractionDeckReferenceID = extractionDeckReferenceID
        self.processProfileID = processProfileID
        self.waiverReferenceID = waiverReferenceID
        self.modelEquivalenceReferenceID = modelEquivalenceReferenceID
        self.terminalEquivalenceReferenceID = terminalEquivalenceReferenceID
        self.topCell = topCell
        self.layoutFormat = layoutFormat
        self.backendID = backendID
    }
}
