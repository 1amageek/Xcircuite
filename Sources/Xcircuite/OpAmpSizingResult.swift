import Foundation

public struct OpAmpSizingResult: Sendable, Hashable, Codable {
    public enum Status: String, Sendable, Hashable, Codable {
        case sized
        case needsReview
        case failed
    }

    public var schemaVersion: Int
    public var resultID: String
    public var specID: String
    public var topology: OpAmpTopologyCandidate
    public var technology: OpAmpSizingTechnologyModel
    public var status: Status
    public var devices: [OpAmpSizedDevice]
    public var estimatedMetrics: [OpAmpEstimatedMetric]
    public var layoutConstraintPlan: OpAmpLayoutConstraintPlan
    public var netlist: String
    public var diagnostics: [OpAmpDesignDiagnostic]
    public var metadata: [String: String]

    public init(
        schemaVersion: Int = 1,
        resultID: String,
        specID: String,
        topology: OpAmpTopologyCandidate,
        technology: OpAmpSizingTechnologyModel,
        status: Status,
        devices: [OpAmpSizedDevice],
        estimatedMetrics: [OpAmpEstimatedMetric],
        layoutConstraintPlan: OpAmpLayoutConstraintPlan,
        netlist: String,
        diagnostics: [OpAmpDesignDiagnostic] = [],
        metadata: [String: String] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.resultID = resultID
        self.specID = specID
        self.topology = topology
        self.technology = technology
        self.status = status
        self.devices = devices
        self.estimatedMetrics = estimatedMetrics
        self.layoutConstraintPlan = layoutConstraintPlan
        self.netlist = netlist
        self.diagnostics = diagnostics
        self.metadata = metadata
    }
}
