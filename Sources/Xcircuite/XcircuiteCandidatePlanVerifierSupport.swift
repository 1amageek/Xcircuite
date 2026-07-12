import Foundation
import LVSEngine
import PEXEngine
import XcircuitePackage

struct ActionDomainSnapshotContext: Sendable, Hashable {
    var snapshot: XcircuitePlanningActionDomainSnapshot
    var reference: XcircuiteFileReference
}

struct SymbolicVerificationSummary: Sendable, Hashable {
    var stepResults: [XcircuitePlanVerificationStepResult]
    var initialSymbolicState: [String]
    var finalSymbolicState: [String]
}

struct PostExecutionGateEvaluation: Sendable, Hashable {
    var gateResults: [XcircuitePlanVerificationGateResult]
    var artifactRefs: [XcircuiteFileReference]
}

struct GateExecutionEvaluation: Sendable, Hashable {
    var gateResult: XcircuitePlanVerificationGateResult
    var artifactRefs: [XcircuiteFileReference]
}

enum StandardLayoutSupport: Sendable, Hashable {
    case lvs
    case pex
}

struct NativeLVSExecutionSpec: Sendable, Hashable {
    var layoutNetlistRef: XcircuitePlanningReference?
    var layoutGDSRef: XcircuitePlanningReference?
    var layoutFormat: LVSLayoutFormat?
    var schematicNetlistRef: XcircuitePlanningReference
    var topCell: String
    var technologyRef: XcircuitePlanningReference?
    var extractionDeckRef: XcircuitePlanningReference?
    var processProfileID: String?
    var waiverRef: XcircuitePlanningReference?
    var modelEquivalenceRef: XcircuitePlanningReference?
    var terminalEquivalenceRef: XcircuitePlanningReference?
    var backendID: String
}

struct PEXExecutionSpec: Sendable, Hashable {
    var layoutRef: XcircuitePlanningReference?
    var layoutFormat: LayoutFormat?
    var sourceNetlistRef: XcircuitePlanningReference
    var sourceNetlistFormat: NetlistFormat
    var topCell: String
    var corners: [PEXCorner]
    var technologyRef: XcircuitePlanningReference
    var backendSelection: PEXBackendSelection
    var options: PEXRunOptions
    var topNets: Int
}

struct SimulationMetricExecutionSpec: Sendable, Hashable {
    var netlistRef: XcircuitePlanningReference?
    var metricReportRef: XcircuitePlanningReference?
    var expectations: [SimulationMeasurementExpectation]
}

struct CandidatePlanLVSInputHint: Sendable, Hashable, Codable {
    var layoutNetlistRef: String?
    var layoutNetlistRefID: String?
    var layoutGDSRef: String?
    var layoutGDSRefID: String?
    var schematicNetlistRef: String?
    var schematicNetlistRefID: String?
    var technologyRef: String?
    var technologyRefID: String?
    var extractionDeckRef: String?
    var extractionDeckRefID: String?
    var processProfileID: String?
    var waiverRef: String?
    var waiverRefID: String?
    var modelEquivalenceRef: String?
    var modelEquivalenceRefID: String?
    var terminalEquivalenceRef: String?
    var terminalEquivalenceRefID: String?
    var topCell: String?
    var layoutFormat: String?
    var backendID: String?

    init(
        layoutNetlistRef: String? = nil,
        layoutNetlistRefID: String? = nil,
        layoutGDSRef: String? = nil,
        layoutGDSRefID: String? = nil,
        schematicNetlistRef: String? = nil,
        schematicNetlistRefID: String? = nil,
        technologyRef: String? = nil,
        technologyRefID: String? = nil,
        extractionDeckRef: String? = nil,
        extractionDeckRefID: String? = nil,
        processProfileID: String? = nil,
        waiverRef: String? = nil,
        waiverRefID: String? = nil,
        modelEquivalenceRef: String? = nil,
        modelEquivalenceRefID: String? = nil,
        terminalEquivalenceRef: String? = nil,
        terminalEquivalenceRefID: String? = nil,
        topCell: String? = nil,
        layoutFormat: String? = nil,
        backendID: String? = nil
    ) {
        self.layoutNetlistRef = layoutNetlistRef
        self.layoutNetlistRefID = layoutNetlistRefID
        self.layoutGDSRef = layoutGDSRef
        self.layoutGDSRefID = layoutGDSRefID
        self.schematicNetlistRef = schematicNetlistRef
        self.schematicNetlistRefID = schematicNetlistRefID
        self.technologyRef = technologyRef
        self.technologyRefID = technologyRefID
        self.extractionDeckRef = extractionDeckRef
        self.extractionDeckRefID = extractionDeckRefID
        self.processProfileID = processProfileID
        self.waiverRef = waiverRef
        self.waiverRefID = waiverRefID
        self.modelEquivalenceRef = modelEquivalenceRef
        self.modelEquivalenceRefID = modelEquivalenceRefID
        self.terminalEquivalenceRef = terminalEquivalenceRef
        self.terminalEquivalenceRefID = terminalEquivalenceRefID
        self.topCell = topCell
        self.layoutFormat = layoutFormat
        self.backendID = backendID
    }

    mutating func merge(_ other: CandidatePlanLVSInputHint) {
        layoutNetlistRef = other.layoutNetlistRef ?? layoutNetlistRef
        layoutNetlistRefID = other.layoutNetlistRefID ?? layoutNetlistRefID
        layoutGDSRef = other.layoutGDSRef ?? layoutGDSRef
        layoutGDSRefID = other.layoutGDSRefID ?? layoutGDSRefID
        schematicNetlistRef = other.schematicNetlistRef ?? schematicNetlistRef
        schematicNetlistRefID = other.schematicNetlistRefID ?? schematicNetlistRefID
        technologyRef = other.technologyRef ?? technologyRef
        technologyRefID = other.technologyRefID ?? technologyRefID
        extractionDeckRef = other.extractionDeckRef ?? extractionDeckRef
        extractionDeckRefID = other.extractionDeckRefID ?? extractionDeckRefID
        processProfileID = other.processProfileID ?? processProfileID
        waiverRef = other.waiverRef ?? waiverRef
        waiverRefID = other.waiverRefID ?? waiverRefID
        modelEquivalenceRef = other.modelEquivalenceRef ?? modelEquivalenceRef
        modelEquivalenceRefID = other.modelEquivalenceRefID ?? modelEquivalenceRefID
        terminalEquivalenceRef = other.terminalEquivalenceRef ?? terminalEquivalenceRef
        terminalEquivalenceRefID = other.terminalEquivalenceRefID ?? terminalEquivalenceRefID
        topCell = other.topCell ?? topCell
        layoutFormat = other.layoutFormat ?? layoutFormat
        backendID = other.backendID ?? backendID
    }
}

struct CandidatePlanSimulationInputHint: Sendable, Hashable, Codable {
    var netlistRef: String?
    var netlistRefID: String?
    var metricReportRef: String?
    var metricReportRefID: String?
    var expectations: [SimulationMeasurementExpectation]?
    var measurementExpectations: [SimulationMeasurementExpectation]?

    init(
        netlistRef: String? = nil,
        netlistRefID: String? = nil,
        metricReportRef: String? = nil,
        metricReportRefID: String? = nil,
        expectations: [SimulationMeasurementExpectation]? = nil,
        measurementExpectations: [SimulationMeasurementExpectation]? = nil
    ) {
        self.netlistRef = netlistRef
        self.netlistRefID = netlistRefID
        self.metricReportRef = metricReportRef
        self.metricReportRefID = metricReportRefID
        self.expectations = expectations
        self.measurementExpectations = measurementExpectations
    }

    mutating func merge(_ other: CandidatePlanSimulationInputHint) {
        netlistRef = other.netlistRef ?? netlistRef
        netlistRefID = other.netlistRefID ?? netlistRefID
        metricReportRef = other.metricReportRef ?? metricReportRef
        metricReportRefID = other.metricReportRefID ?? metricReportRefID
        expectations = other.expectations ?? expectations
        measurementExpectations = other.measurementExpectations ?? measurementExpectations
    }
}

struct CandidatePlanPEXInputHint: Sendable, Hashable, Codable {
    var layoutRef: String?
    var layoutRefID: String?
    var sourceNetlistRef: String?
    var sourceNetlistRefID: String?
    var technologyRef: String?
    var technologyRefID: String?
    var topCell: String?
    var layoutFormat: String?
    var sourceNetlistFormat: String?
    var backendID: String?
    var pexBackendID: String?
    var allowMockBackend: Bool?
    var executablePath: String?
    var environmentOverrides: [String: String]?
    var corners: [String]?
    var cornerIDs: [String]?
    var options: PEXRunOptions?
    var topNets: Int?

    init(
        layoutRef: String? = nil,
        layoutRefID: String? = nil,
        sourceNetlistRef: String? = nil,
        sourceNetlistRefID: String? = nil,
        technologyRef: String? = nil,
        technologyRefID: String? = nil,
        topCell: String? = nil,
        layoutFormat: String? = nil,
        sourceNetlistFormat: String? = nil,
        backendID: String? = nil,
        pexBackendID: String? = nil,
        allowMockBackend: Bool? = nil,
        executablePath: String? = nil,
        environmentOverrides: [String: String]? = nil,
        corners: [String]? = nil,
        cornerIDs: [String]? = nil,
        options: PEXRunOptions? = nil,
        topNets: Int? = nil
    ) {
        self.layoutRef = layoutRef
        self.layoutRefID = layoutRefID
        self.sourceNetlistRef = sourceNetlistRef
        self.sourceNetlistRefID = sourceNetlistRefID
        self.technologyRef = technologyRef
        self.technologyRefID = technologyRefID
        self.topCell = topCell
        self.layoutFormat = layoutFormat
        self.sourceNetlistFormat = sourceNetlistFormat
        self.backendID = backendID
        self.pexBackendID = pexBackendID
        self.allowMockBackend = allowMockBackend
        self.executablePath = executablePath
        self.environmentOverrides = environmentOverrides
        self.corners = corners
        self.cornerIDs = cornerIDs
        self.options = options
        self.topNets = topNets
    }

    mutating func merge(_ other: CandidatePlanPEXInputHint) {
        layoutRef = other.layoutRef ?? layoutRef
        layoutRefID = other.layoutRefID ?? layoutRefID
        sourceNetlistRef = other.sourceNetlistRef ?? sourceNetlistRef
        sourceNetlistRefID = other.sourceNetlistRefID ?? sourceNetlistRefID
        technologyRef = other.technologyRef ?? technologyRef
        technologyRefID = other.technologyRefID ?? technologyRefID
        topCell = other.topCell ?? topCell
        layoutFormat = other.layoutFormat ?? layoutFormat
        sourceNetlistFormat = other.sourceNetlistFormat ?? sourceNetlistFormat
        backendID = other.backendID ?? backendID
        pexBackendID = other.pexBackendID ?? pexBackendID
        allowMockBackend = other.allowMockBackend ?? allowMockBackend
        executablePath = other.executablePath ?? executablePath
        environmentOverrides = other.environmentOverrides ?? environmentOverrides
        corners = other.corners ?? corners
        cornerIDs = other.cornerIDs ?? cornerIDs
        options = other.options ?? options
        topNets = other.topNets ?? topNets
    }
}

enum CandidatePlanGateExecutionError: LocalizedError, Equatable {
    case layoutCellNotFound(String)
    case unsupportedGeometry(shapeID: UUID)
    case missingViaDefinition(viaID: UUID, definitionID: String)
    case duplicateViaDefinition(String)
    case sourceProblemRunMismatch(expected: String, actual: String)
    case planningReferencePathMissing(String)
    case unsupportedLVSLayoutFormat(String)
    case unsupportedLVSBackend(String)
    case unsupportedPEXLayoutFormat(String)
    case unsupportedPEXNetlistFormat(String)

    var errorDescription: String? {
        switch self {
        case .layoutCellNotFound(let name):
            "Candidate plan gate execution could not find layout cell \(name)."
        case .unsupportedGeometry(let shapeID):
            "Candidate plan gate execution only supports rectangle geometry for DRC export; shape \(shapeID) is unsupported."
        case .missingViaDefinition(let viaID, let definitionID):
            "Candidate plan gate execution cannot expand via \(viaID) because via definition \(definitionID) is missing."
        case .duplicateViaDefinition(let definitionID):
            "Candidate plan gate execution cannot expand vias because via definition \(definitionID) is duplicated."
        case .sourceProblemRunMismatch(let expected, let actual):
            "Candidate plan gate execution expected source problem run \(expected), but found \(actual)."
        case .planningReferencePathMissing(let refID):
            "Candidate plan gate execution cannot resolve planning reference \(refID) because it has no path or indexed artifact ID."
        case .unsupportedLVSLayoutFormat(let value):
            "Candidate plan gate execution does not support LVS layout format \(value)."
        case .unsupportedLVSBackend(let backendID):
            "Candidate plan gate execution does not support LVS backend \(backendID) for the native-lvs gate."
        case .unsupportedPEXLayoutFormat(let value):
            "Candidate plan gate execution does not support PEX layout format \(value)."
        case .unsupportedPEXNetlistFormat(let value):
            "Candidate plan gate execution does not support PEX netlist format \(value)."
        }
    }
}
