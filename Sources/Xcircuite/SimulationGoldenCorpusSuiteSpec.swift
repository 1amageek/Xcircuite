import Foundation

public struct SimulationGoldenCorpusSuiteSpec: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var suiteID: String
    public var description: String?
    public var cases: [SimulationGoldenCorpusCaseSpec]

    public init(
        schemaVersion: Int = 1,
        suiteID: String,
        description: String? = nil,
        cases: [SimulationGoldenCorpusCaseSpec]
    ) {
        self.schemaVersion = schemaVersion
        self.suiteID = suiteID
        self.description = description
        self.cases = cases
    }

    public static func load(from url: URL) throws -> SimulationGoldenCorpusSuiteSpec {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(SimulationGoldenCorpusSuiteSpec.self, from: data)
    }
}
