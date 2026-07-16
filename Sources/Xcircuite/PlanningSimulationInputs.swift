import Foundation

public struct PlanningSimulationInputs: Sendable, Hashable, Codable {
    public var netlistReferenceID: String
    public var measurementExpectations: [SimulationMeasurementExpectation]

    public init(
        netlistReferenceID: String,
        measurementExpectations: [SimulationMeasurementExpectation]
    ) {
        self.netlistReferenceID = netlistReferenceID
        self.measurementExpectations = measurementExpectations
    }
}
