import Foundation

public struct XcircuiteVerifiedImprovementCorpusSuiteSpec: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var suiteID: String
    public var requiredFamilies: [XcircuiteVerifiedImprovementCorpusFamily]
    public var cases: [CaseSpec]

    public init(
        schemaVersion: Int = 1,
        suiteID: String,
        requiredFamilies: [XcircuiteVerifiedImprovementCorpusFamily] = XcircuiteVerifiedImprovementCorpusFamily.allCases,
        cases: [CaseSpec]
    ) {
        self.schemaVersion = schemaVersion
        self.suiteID = suiteID
        self.requiredFamilies = requiredFamilies
        self.cases = cases
    }

    public struct CaseSpec: Codable, Sendable, Hashable {
        public var caseID: String
        public var runID: String
        public var family: XcircuiteVerifiedImprovementCorpusFamily
        public var expectedStatus: String
        public var expectedAccepted: Bool?
        public var requiredDiagnosticCodes: [String]
        public var requiredFailedGateIDs: [String]
        public var requiredArtifactIDs: [String]
        public var numericRepairLoopPath: String?
        public var improvementLoopPath: String?

        public init(
            caseID: String,
            runID: String,
            family: XcircuiteVerifiedImprovementCorpusFamily,
            expectedStatus: String,
            expectedAccepted: Bool? = nil,
            requiredDiagnosticCodes: [String] = [],
            requiredFailedGateIDs: [String] = [],
            requiredArtifactIDs: [String] = [],
            numericRepairLoopPath: String? = nil,
            improvementLoopPath: String? = nil
        ) {
            self.caseID = caseID
            self.runID = runID
            self.family = family
            self.expectedStatus = expectedStatus
            self.expectedAccepted = expectedAccepted
            self.requiredDiagnosticCodes = requiredDiagnosticCodes
            self.requiredFailedGateIDs = requiredFailedGateIDs
            self.requiredArtifactIDs = requiredArtifactIDs
            self.numericRepairLoopPath = numericRepairLoopPath
            self.improvementLoopPath = improvementLoopPath
        }
    }
}
