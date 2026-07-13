import Foundation

public struct TimingSIFlowInputs: Sendable, Hashable, Codable {
    public var design: XcircuiteFlowInputReference
    public var constraints: XcircuiteFlowInputReference
    public var pdkManifest: XcircuiteFlowInputReference
    public var parasitics: XcircuiteFlowInputReference
    public var topDesignName: String
    public var processID: String
    public var pdkVersion: String
    public var pdkDigest: String
    public var modeIDs: [String]
    public var maxDeltaDelay: Double
    public var maxNoiseRatio: Double

    public init(
        design: XcircuiteFlowInputReference,
        constraints: XcircuiteFlowInputReference,
        pdkManifest: XcircuiteFlowInputReference,
        parasitics: XcircuiteFlowInputReference,
        topDesignName: String,
        processID: String,
        pdkVersion: String,
        pdkDigest: String,
        modeIDs: [String] = ["default"],
        maxDeltaDelay: Double = Double.greatestFiniteMagnitude,
        maxNoiseRatio: Double = Double.greatestFiniteMagnitude
    ) {
        self.design = design
        self.constraints = constraints
        self.pdkManifest = pdkManifest
        self.parasitics = parasitics
        self.topDesignName = topDesignName
        self.processID = processID
        self.pdkVersion = pdkVersion
        self.pdkDigest = pdkDigest
        self.modeIDs = modeIDs
        self.maxDeltaDelay = maxDeltaDelay
        self.maxNoiseRatio = maxNoiseRatio
    }
}
