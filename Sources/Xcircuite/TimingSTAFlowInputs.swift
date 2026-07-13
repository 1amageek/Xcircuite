import Foundation
import STAEngine

public struct TimingSTAFlowInputs: Sendable, Hashable, Codable {
    public var design: XcircuiteFlowInputReference
    public var libraries: [XcircuiteFlowInputReference]
    public var constraints: XcircuiteFlowInputReference
    public var pdkManifest: XcircuiteFlowInputReference
    public var parasitics: XcircuiteFlowInputReference?
    public var topDesignName: String
    public var processID: String
    public var pdkVersion: String
    public var pdkDigest: String
    public var modeIDs: [String]
    public var cornerIDs: [String]
    public var analysisKinds: [STAAnalysisKind]
    public var requiresSignoff: Bool

    public init(
        design: XcircuiteFlowInputReference,
        libraries: [XcircuiteFlowInputReference],
        constraints: XcircuiteFlowInputReference,
        pdkManifest: XcircuiteFlowInputReference,
        parasitics: XcircuiteFlowInputReference? = nil,
        topDesignName: String,
        processID: String,
        pdkVersion: String,
        pdkDigest: String,
        modeIDs: [String] = ["default"],
        cornerIDs: [String] = ["default"],
        analysisKinds: [STAAnalysisKind] = [.setup, .hold],
        requiresSignoff: Bool = false
    ) {
        self.design = design
        self.libraries = libraries
        self.constraints = constraints
        self.pdkManifest = pdkManifest
        self.parasitics = parasitics
        self.topDesignName = topDesignName
        self.processID = processID
        self.pdkVersion = pdkVersion
        self.pdkDigest = pdkDigest
        self.modeIDs = modeIDs
        self.cornerIDs = cornerIDs
        self.analysisKinds = analysisKinds
        self.requiresSignoff = requiresSignoff
    }
}
