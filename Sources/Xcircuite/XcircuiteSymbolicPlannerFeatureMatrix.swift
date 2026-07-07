public struct XcircuiteSymbolicPlannerFeatureMatrix: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var matrixID: String
    public var requiredForCorpusTrustTags: [String]
    public var implementedCoverageTags: [String]
    public var plannedCoverageTags: [String]
    public var features: [XcircuiteSymbolicPlannerFeature]

    public init(
        schemaVersion: Int = 1,
        matrixID: String,
        requiredForCorpusTrustTags: [String],
        implementedCoverageTags: [String],
        plannedCoverageTags: [String],
        features: [XcircuiteSymbolicPlannerFeature]
    ) {
        self.schemaVersion = schemaVersion
        self.matrixID = matrixID
        self.requiredForCorpusTrustTags = requiredForCorpusTrustTags
        self.implementedCoverageTags = implementedCoverageTags
        self.plannedCoverageTags = plannedCoverageTags
        self.features = features
    }
}
