public struct XcircuiteSymbolicPlannerCoverageTagValidator: Sendable {
    public var featureMatrix: XcircuiteSymbolicPlannerFeatureMatrix

    public init(
        featureMatrix: XcircuiteSymbolicPlannerFeatureMatrix = XcircuiteSymbolicPlannerFeatureMatrixProvider().currentMatrix()
    ) {
        self.featureMatrix = featureMatrix
    }

    public func validateCoverageTags(_ coverageTags: [String]) throws {
        let knownTags = featureMatrix.features.map(\.coverageTag).sorted()
        let knownTagSet = Set(knownTags)
        let unknownTags = unique(coverageTags).filter { !knownTagSet.contains($0) }
        if !unknownTags.isEmpty {
            throw XcircuiteSymbolicPlannerSolverError.unknownCoverageTags(
                tags: unknownTags,
                knownTags: knownTags
            )
        }
    }

    public func validateImplementedCoverageTags(_ coverageTags: [String]) throws {
        try validateCoverageTags(coverageTags)
        let implementedTags = featureMatrix.implementedCoverageTags.sorted()
        let implementedTagSet = Set(implementedTags)
        let unimplementedTags = unique(coverageTags).filter { !implementedTagSet.contains($0) }
        if !unimplementedTags.isEmpty {
            throw XcircuiteSymbolicPlannerSolverError.unimplementedCoverageTags(
                tags: unimplementedTags,
                implementedTags: implementedTags
            )
        }
    }

    private func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }
}
