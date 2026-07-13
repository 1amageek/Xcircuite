import DesignFlowKernel
import DFTCore
import DRCEngine
import ElectricalSignoffCore
import ElectricalSignoffEngine
import ElectricalSignoffQualification
import Foundation
import LayoutCommands
import LayoutCore
import LayoutIO
import LVSEngine
import PDKKit
import PEXEngine
import PhysicalDesignCore
import ToolQualification

public enum XcircuiteFlowStageExecutorSpec: Sendable, Hashable, Codable {
    case layoutCommand(LayoutCommand)
    case nativeDRC(NativeDRC)
    case nativeLVS(NativeLVS)
    case pex(PEX)
    case mockPEX(MockPEX)
    case coreSpiceSimulation(CoreSpiceSimulation)
    case postLayoutComparison(PostLayoutComparison)
    case rtlVerification(RTLVerification)
    case logicSynthesis(LogicSynthesis)
    case logicEquivalence(LogicEquivalence)
    case logicQualification(LogicQualification)
    case dft(DFT)
    case physicalReview(PhysicalReview)
    case pdkDiscovery(PDKDiscovery)
    case pdkValidation(PDKValidation)
    case pdkCorpus(PDKCorpus)
    case pdkStandardView(PDKStandardView)
    case pdkRuleDeck(PDKRuleDeck)
    case pdkOracle(PDKOracle)
    case pdkQualification(PDKQualification)
    case releaseQualification(ReleaseQualification)
    case releaseSignoff(ReleaseSignoff)
    case releaseTapeout(ReleaseTapeout)
    case releaseProfile(ReleaseProfile)
    case electricalStandardLayoutImport(ElectricalStandardLayoutImport)
    case electricalSignoff(ElectricalSignoff)
    case electricalSignoffQualification(ElectricalSignoffQualification)
    case electricalSignoffReleaseGate(ElectricalSignoffReleaseGate)
    case electricalRepairRevision(ElectricalRepairRevision)

    public struct PDKDiscovery: Sendable, Hashable, Codable {
        public var stageID: String
        public var searchRoots: [XcircuiteFlowInputReference]
        public var requiredProcessID: String?
        public var tool: XcircuiteFlowToolSpec

        public init(
            stageID: String = PDKKitAPI.discoveryStageID,
            searchRoots: [XcircuiteFlowInputReference],
            requiredProcessID: String? = nil,
            tool: XcircuiteFlowToolSpec = XcircuiteFlowToolSpec()
        ) {
            self.stageID = stageID
            self.searchRoots = searchRoots
            self.requiredProcessID = requiredProcessID
            self.tool = tool
        }
    }

    public struct PDKValidation: Sendable, Hashable, Codable {
        public var stageID: String
        public var manifestInput: XcircuiteFlowInputReference
        public var requiredAssetRoles: [PDKAssetRole]
        public var validateCrossViews: Bool
        public var tool: XcircuiteFlowToolSpec

        public init(
            stageID: String = PDKKitAPI.validationStageID,
            manifestInput: XcircuiteFlowInputReference,
            requiredAssetRoles: [PDKAssetRole] = [],
            validateCrossViews: Bool = true,
            tool: XcircuiteFlowToolSpec = XcircuiteFlowToolSpec()
        ) {
            self.stageID = stageID
            self.manifestInput = manifestInput
            self.requiredAssetRoles = requiredAssetRoles
            self.validateCrossViews = validateCrossViews
            self.tool = tool
        }
    }

    public struct PDKCorpus: Sendable, Hashable, Codable {
        public var stageID: String
        public var suiteInput: XcircuiteFlowInputReference
        public var rootInput: XcircuiteFlowInputReference
        public var tool: XcircuiteFlowToolSpec

        public init(
            stageID: String = PDKKitAPI.corpusValidationStageID,
            suiteInput: XcircuiteFlowInputReference,
            rootInput: XcircuiteFlowInputReference,
            tool: XcircuiteFlowToolSpec = XcircuiteFlowToolSpec()
        ) {
            self.stageID = stageID
            self.suiteInput = suiteInput
            self.rootInput = rootInput
            self.tool = tool
        }
    }

    public struct PDKStandardView: Sendable, Hashable, Codable {
        public var stageID: String
        public var manifestInput: XcircuiteFlowInputReference
        public var assetID: String
        public var format: PDKStandardViewFormat
        public var externalProcess: PDKExternalInspectionProcessConfiguration?
        public var tool: XcircuiteFlowToolSpec

        public init(
            stageID: String = PDKKitAPI.standardViewInspectionStageID,
            manifestInput: XcircuiteFlowInputReference,
            assetID: String,
            format: PDKStandardViewFormat,
            externalProcess: PDKExternalInspectionProcessConfiguration? = nil,
            tool: XcircuiteFlowToolSpec = XcircuiteFlowToolSpec()
        ) {
            self.stageID = stageID
            self.manifestInput = manifestInput
            self.assetID = assetID
            self.format = format
            self.externalProcess = externalProcess
            self.tool = tool
        }
    }

    public struct PDKRuleDeck: Sendable, Hashable, Codable {
        public var stageID: String
        public var manifestInput: XcircuiteFlowInputReference
        public var assetID: String
        public var externalProcess: PDKExternalInspectionProcessConfiguration?
        public var tool: XcircuiteFlowToolSpec

        public init(
            stageID: String = PDKKitAPI.ruleDeckInspectionStageID,
            manifestInput: XcircuiteFlowInputReference,
            assetID: String,
            externalProcess: PDKExternalInspectionProcessConfiguration? = nil,
            tool: XcircuiteFlowToolSpec = XcircuiteFlowToolSpec()
        ) {
            self.stageID = stageID
            self.manifestInput = manifestInput
            self.assetID = assetID
            self.externalProcess = externalProcess
            self.tool = tool
        }
    }

    public struct PDKOracle: Sendable, Hashable, Codable {
        public var stageID: String
        public var manifestInput: XcircuiteFlowInputReference
        public var oracleInput: XcircuiteFlowInputReference
        public var tool: XcircuiteFlowToolSpec

        public init(
            stageID: String = PDKKitAPI.oracleComparisonStageID,
            manifestInput: XcircuiteFlowInputReference,
            oracleInput: XcircuiteFlowInputReference,
            tool: XcircuiteFlowToolSpec = XcircuiteFlowToolSpec()
        ) {
            self.stageID = stageID
            self.manifestInput = manifestInput
            self.oracleInput = oracleInput
            self.tool = tool
        }
    }

    public struct PDKQualification: Sendable, Hashable, Codable {
        public var stageID: String
        public var manifestInput: XcircuiteFlowInputReference
        public var corpusInput: XcircuiteFlowInputReference
        public var oracleInput: XcircuiteFlowInputReference
        public var tool: XcircuiteFlowToolSpec

        public init(
            stageID: String = PDKKitAPI.qualificationStageID,
            manifestInput: XcircuiteFlowInputReference,
            corpusInput: XcircuiteFlowInputReference,
            oracleInput: XcircuiteFlowInputReference,
            tool: XcircuiteFlowToolSpec = XcircuiteFlowToolSpec()
        ) {
            self.stageID = stageID
            self.manifestInput = manifestInput
            self.corpusInput = corpusInput
            self.oracleInput = oracleInput
            self.tool = tool
        }
    }

    public struct DFT: Sendable, Hashable, Codable {
        public var stageID: String
        public var requestPath: String
        public var qualificationCorpusPath: String?
        public var qualificationObservationsPath: String?
        public var qualificationEvidencePath: String?
        public var releaseResultPath: String?
        public var releaseDownstreamEvidencePath: String?
        public var releaseApprovalPath: String?
        public var tool: XcircuiteFlowToolSpec

        public init(
            stageID: String,
            requestPath: String,
            qualificationCorpusPath: String? = nil,
            qualificationObservationsPath: String? = nil,
            qualificationEvidencePath: String? = nil,
            releaseResultPath: String? = nil,
            releaseDownstreamEvidencePath: String? = nil,
            releaseApprovalPath: String? = nil,
            tool: XcircuiteFlowToolSpec = XcircuiteFlowToolSpec()
        ) {
            self.stageID = stageID
            self.requestPath = requestPath
            self.qualificationCorpusPath = qualificationCorpusPath
            self.qualificationObservationsPath = qualificationObservationsPath
            self.qualificationEvidencePath = qualificationEvidencePath
            self.releaseResultPath = releaseResultPath
            self.releaseDownstreamEvidencePath = releaseDownstreamEvidencePath
            self.releaseApprovalPath = releaseApprovalPath
            self.tool = tool
        }
    }

    public struct PhysicalReview: Sendable, Hashable, Codable {
        public var stageID: String
        public var manifestInput: XcircuiteFlowInputReference
        public var decisionScope: [String]
        public var tool: XcircuiteFlowToolSpec

        public init(
            stageID: String = "physical.review",
            manifestInput: XcircuiteFlowInputReference,
            decisionScope: [String] = ["proposed_layout", "design_diff", "implementation_configuration"],
            tool: XcircuiteFlowToolSpec = XcircuiteFlowToolSpec()
        ) {
            self.stageID = stageID
            self.manifestInput = manifestInput
            self.decisionScope = decisionScope
            self.tool = tool
        }
    }

    public struct ElectricalRepairRevision: Sendable, Hashable, Codable {
        public var stageID: String
        public var requestPath: String
        public var tool: XcircuiteFlowToolSpec

        public init(
            stageID: String = "electrical-signoff.repair-revision",
            requestPath: String,
            tool: XcircuiteFlowToolSpec = XcircuiteFlowToolSpec()
        ) {
            self.stageID = stageID
            self.requestPath = requestPath
            self.tool = tool
        }
    }

    public struct ElectricalStandardLayoutImport: Sendable, Hashable, Codable {
        public var stageID: String
        public var layoutInput: XcircuiteFlowInputReference
        public var layoutFormat: LayoutFileFormat
        public var technologyInput: XcircuiteFlowInputReference
        public var technologyFormat: LayoutFileFormat
        public var connectivityInput: XcircuiteFlowInputReference?
        public var connectivityFormat: LayoutFileFormat
        public var topCellName: String?
        public var tool: XcircuiteFlowToolSpec

        public init(
            stageID: String = "electrical-signoff.standard-layout-import",
            layoutInput: XcircuiteFlowInputReference,
            layoutFormat: LayoutFileFormat,
            technologyInput: XcircuiteFlowInputReference,
            technologyFormat: LayoutFileFormat = .lef,
            connectivityInput: XcircuiteFlowInputReference? = nil,
            connectivityFormat: LayoutFileFormat = .def,
            topCellName: String? = nil,
            tool: XcircuiteFlowToolSpec = XcircuiteFlowToolSpec()
        ) {
            self.stageID = stageID
            self.layoutInput = layoutInput
            self.layoutFormat = layoutFormat
            self.technologyInput = technologyInput
            self.technologyFormat = technologyFormat
            self.connectivityInput = connectivityInput
            self.connectivityFormat = connectivityFormat
            self.topCellName = topCellName
            self.tool = tool
        }
    }

    public struct ElectricalSignoff: Sendable, Hashable, Codable {
        public var stageID: String
        public var requestPath: String
        public var axes: [ElectricalSignoffAnalysisAxis]
        public var tool: XcircuiteFlowToolSpec

        public init(
            stageID: String = "electrical-signoff",
            requestPath: String,
            axes: [ElectricalSignoffAnalysisAxis] = ElectricalSignoffEngineAPI.supportedAxes,
            tool: XcircuiteFlowToolSpec = XcircuiteFlowToolSpec()
        ) {
            self.stageID = stageID
            self.requestPath = requestPath
            self.axes = axes
            self.tool = tool
        }
    }

    public struct ElectricalSignoffQualification: Sendable, Hashable, Codable {
        public var stageID: String
        public var specPath: String
        public var oraclePath: String?
        public var qualificationScope: ToolQualificationScope
        public var tool: XcircuiteFlowToolSpec

        public init(
            stageID: String = "electrical-signoff.qualification",
            specPath: String,
            oraclePath: String? = nil,
            qualificationScope: ToolQualificationScope,
            tool: XcircuiteFlowToolSpec = XcircuiteFlowToolSpec()
        ) {
            self.stageID = stageID
            self.specPath = specPath
            self.oraclePath = oraclePath
            self.qualificationScope = qualificationScope
            self.tool = tool
        }
    }

    public struct ElectricalSignoffReleaseGate: Sendable, Hashable, Codable {
        public var stageID: String
        public var requestInput: XcircuiteFlowInputReference
        public var runResultInput: XcircuiteFlowInputReference
        public var qualificationSpecInput: XcircuiteFlowInputReference
        public var qualificationReportInput: XcircuiteFlowInputReference
        public var policyInput: XcircuiteFlowInputReference
        public var tool: XcircuiteFlowToolSpec

        public init(
            stageID: String = "electrical-signoff.release-gate",
            requestInput: XcircuiteFlowInputReference,
            runResultInput: XcircuiteFlowInputReference,
            qualificationSpecInput: XcircuiteFlowInputReference,
            qualificationReportInput: XcircuiteFlowInputReference,
            policyInput: XcircuiteFlowInputReference,
            tool: XcircuiteFlowToolSpec = XcircuiteFlowToolSpec()
        ) {
            self.stageID = stageID
            self.requestInput = requestInput
            self.runResultInput = runResultInput
            self.qualificationSpecInput = qualificationSpecInput
            self.qualificationReportInput = qualificationReportInput
            self.policyInput = policyInput
            self.tool = tool
        }
    }

    public struct LogicSynthesis: Sendable, Hashable, Codable {
        public var stageID: String
        public var requestPath: String
        public var tool: XcircuiteFlowToolSpec

        public init(
            stageID: String = "logic.synthesize",
            requestPath: String,
            tool: XcircuiteFlowToolSpec = XcircuiteFlowToolSpec()
        ) {
            self.stageID = stageID
            self.requestPath = requestPath
            self.tool = tool
        }
    }

    public struct LogicEquivalence: Sendable, Hashable, Codable {
        public var stageID: String
        public var requestPath: String
        public var tool: XcircuiteFlowToolSpec

        public init(
            stageID: String = "logic.equivalence",
            requestPath: String,
            tool: XcircuiteFlowToolSpec = XcircuiteFlowToolSpec()
        ) {
            self.stageID = stageID
            self.requestPath = requestPath
            self.tool = tool
        }
    }

    public struct LogicQualification: Sendable, Hashable, Codable {
        public var stageID: String
        public var reportPath: String
        public var processEvidencePath: String?
        public var releaseApprovalPath: String?
        public var tool: XcircuiteFlowToolSpec

        public init(
            stageID: String = "logic.qualification",
            reportPath: String,
            processEvidencePath: String? = nil,
            releaseApprovalPath: String? = nil,
            tool: XcircuiteFlowToolSpec = XcircuiteFlowToolSpec()
        ) {
            self.stageID = stageID
            self.reportPath = reportPath
            self.processEvidencePath = processEvidencePath
            self.releaseApprovalPath = releaseApprovalPath
            self.tool = tool
        }
    }

    public struct LayoutCommand: Sendable, Hashable, Codable {
        public var stageID: String
        public var requestPath: String
        public var drcExport: LayoutCommandDRCExportSpec?
        public var standardLayoutExports: [LayoutCommandStandardLayoutExportSpec]
        public var tool: XcircuiteFlowToolSpec

        public init(
            stageID: String,
            requestPath: String,
            drcExport: LayoutCommandDRCExportSpec? = nil,
            standardLayoutExports: [LayoutCommandStandardLayoutExportSpec] = [],
            tool: XcircuiteFlowToolSpec = XcircuiteFlowToolSpec()
        ) {
            self.stageID = stageID
            self.requestPath = requestPath
            self.drcExport = drcExport
            self.standardLayoutExports = standardLayoutExports
            self.tool = tool
        }

        private enum CodingKeys: String, CodingKey {
            case stageID
            case requestPath
            case drcExport
            case standardLayoutExports
            case tool
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            stageID = try container.decode(String.self, forKey: .stageID)
            requestPath = try container.decode(String.self, forKey: .requestPath)
            drcExport = try container.decodeIfPresent(LayoutCommandDRCExportSpec.self, forKey: .drcExport)
            standardLayoutExports = try container.decode(
                [LayoutCommandStandardLayoutExportSpec].self,
                forKey: .standardLayoutExports
            )
            tool = try container.decode(XcircuiteFlowToolSpec.self, forKey: .tool)
        }
    }

    public struct NativeDRC: Sendable, Hashable, Codable {
        public var stageID: String
        public var layoutPath: String?
        public var layoutInput: XcircuiteFlowInputReference?
        public var layoutFormat: DRCLayoutFormat?
        public var topCell: String
        public var technologyPath: String?
        public var technologyInput: XcircuiteFlowInputReference?
        public var options: DRCOptions?
        public var tool: XcircuiteFlowToolSpec

        public init(
            stageID: String,
            layoutPath: String? = nil,
            layoutInput: XcircuiteFlowInputReference? = nil,
            layoutFormat: DRCLayoutFormat? = nil,
            topCell: String,
            technologyPath: String? = nil,
            technologyInput: XcircuiteFlowInputReference? = nil,
            options: DRCOptions? = nil,
            tool: XcircuiteFlowToolSpec = XcircuiteFlowToolSpec()
        ) {
            self.stageID = stageID
            self.layoutPath = layoutPath
            self.layoutInput = layoutInput
            self.layoutFormat = layoutFormat
            self.topCell = topCell
            self.technologyPath = technologyPath
            self.technologyInput = technologyInput
            self.options = options
            self.tool = tool
        }
    }

    public struct NativeLVS: Sendable, Hashable, Codable {
        public var stageID: String
        public var layoutNetlistPath: String?
        public var layoutNetlistInput: XcircuiteFlowInputReference?
        public var layoutGDSPath: String?
        public var layoutGDSInput: XcircuiteFlowInputReference?
        public var layoutFormat: LVSLayoutFormat?
        public var schematicNetlistPath: String?
        public var schematicNetlistInput: XcircuiteFlowInputReference?
        public var topCell: String
        public var technologyPath: String?
        public var technologyInput: XcircuiteFlowInputReference?
        public var terminalEquivalencePath: String?
        public var terminalEquivalenceInput: XcircuiteFlowInputReference?
        public var options: LVSOptions?
        public var tool: XcircuiteFlowToolSpec

        public init(
            stageID: String,
            layoutNetlistPath: String? = nil,
            layoutNetlistInput: XcircuiteFlowInputReference? = nil,
            layoutGDSPath: String? = nil,
            layoutGDSInput: XcircuiteFlowInputReference? = nil,
            layoutFormat: LVSLayoutFormat? = nil,
            schematicNetlistPath: String? = nil,
            schematicNetlistInput: XcircuiteFlowInputReference? = nil,
            topCell: String,
            technologyPath: String? = nil,
            technologyInput: XcircuiteFlowInputReference? = nil,
            terminalEquivalencePath: String? = nil,
            terminalEquivalenceInput: XcircuiteFlowInputReference? = nil,
            options: LVSOptions? = nil,
            tool: XcircuiteFlowToolSpec = XcircuiteFlowToolSpec()
        ) {
            self.stageID = stageID
            self.layoutNetlistPath = layoutNetlistPath
            self.layoutNetlistInput = layoutNetlistInput
            self.layoutGDSPath = layoutGDSPath
            self.layoutGDSInput = layoutGDSInput
            self.layoutFormat = layoutFormat
            self.schematicNetlistPath = schematicNetlistPath
            self.schematicNetlistInput = schematicNetlistInput
            self.topCell = topCell
            self.technologyPath = technologyPath
            self.technologyInput = technologyInput
            self.terminalEquivalencePath = terminalEquivalencePath
            self.terminalEquivalenceInput = terminalEquivalenceInput
            self.options = options
            self.tool = tool
        }
    }

    public struct MockPEX: Sendable, Hashable, Codable {
        public var stageID: String
        public var layoutPath: String?
        public var layoutInput: XcircuiteFlowInputReference?
        public var layoutFormat: LayoutFormat
        public var sourceNetlistPath: String?
        public var sourceNetlistInput: XcircuiteFlowInputReference?
        public var sourceNetlistFormat: NetlistFormat
        public var topCell: String
        public var corners: [PEXCorner]
        public var technology: XcircuitePEXTechnologySpec?
        public var technologyByCorner: [String: XcircuitePEXTechnologySpec]
        public var processProfile: PEXProcessProfileReference?
        public var options: PEXRunOptions?
        public var tool: XcircuiteFlowToolSpec

        public init(
            stageID: String,
            layoutPath: String? = nil,
            layoutInput: XcircuiteFlowInputReference? = nil,
            layoutFormat: LayoutFormat,
            sourceNetlistPath: String? = nil,
            sourceNetlistInput: XcircuiteFlowInputReference? = nil,
            sourceNetlistFormat: NetlistFormat = .spice,
            topCell: String,
            corners: [PEXCorner],
            technology: XcircuitePEXTechnologySpec? = nil,
            technologyByCorner: [String: XcircuitePEXTechnologySpec] = [:],
            processProfile: PEXProcessProfileReference? = nil,
            options: PEXRunOptions? = nil,
            tool: XcircuiteFlowToolSpec = XcircuiteFlowToolSpec()
        ) {
            self.stageID = stageID
            self.layoutPath = layoutPath
            self.layoutInput = layoutInput
            self.layoutFormat = layoutFormat
            self.sourceNetlistPath = sourceNetlistPath
            self.sourceNetlistInput = sourceNetlistInput
            self.sourceNetlistFormat = sourceNetlistFormat
            self.topCell = topCell
            self.corners = corners
            self.technology = technology
            self.technologyByCorner = technologyByCorner
            self.processProfile = processProfile
            self.options = options
            self.tool = tool
        }

        private enum CodingKeys: String, CodingKey {
            case stageID
            case layoutPath
            case layoutInput
            case layoutFormat
            case sourceNetlistPath
            case sourceNetlistInput
            case sourceNetlistFormat
            case topCell
            case corners
            case technology
            case technologyByCorner
            case processProfile
            case options
            case tool
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            stageID = try container.decode(String.self, forKey: .stageID)
            layoutPath = try container.decodeIfPresent(String.self, forKey: .layoutPath)
            layoutInput = try container.decodeIfPresent(XcircuiteFlowInputReference.self, forKey: .layoutInput)
            layoutFormat = try container.decode(LayoutFormat.self, forKey: .layoutFormat)
            sourceNetlistPath = try container.decodeIfPresent(String.self, forKey: .sourceNetlistPath)
            sourceNetlistInput = try container.decodeIfPresent(XcircuiteFlowInputReference.self, forKey: .sourceNetlistInput)
            sourceNetlistFormat = try container.decode(NetlistFormat.self, forKey: .sourceNetlistFormat)
            topCell = try container.decode(String.self, forKey: .topCell)
            corners = try container.decode([PEXCorner].self, forKey: .corners)
            technology = try container.decodeIfPresent(XcircuitePEXTechnologySpec.self, forKey: .technology)
            technologyByCorner = try container.decodeIfPresent(
                [String: XcircuitePEXTechnologySpec].self,
                forKey: .technologyByCorner
            ) ?? [:]
            processProfile = try container.decodeIfPresent(PEXProcessProfileReference.self, forKey: .processProfile)
            options = try container.decodeIfPresent(PEXRunOptions.self, forKey: .options)
            tool = try container.decode(XcircuiteFlowToolSpec.self, forKey: .tool)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(stageID, forKey: .stageID)
            try container.encodeIfPresent(layoutPath, forKey: .layoutPath)
            try container.encodeIfPresent(layoutInput, forKey: .layoutInput)
            try container.encode(layoutFormat, forKey: .layoutFormat)
            try container.encodeIfPresent(sourceNetlistPath, forKey: .sourceNetlistPath)
            try container.encodeIfPresent(sourceNetlistInput, forKey: .sourceNetlistInput)
            try container.encode(sourceNetlistFormat, forKey: .sourceNetlistFormat)
            try container.encode(topCell, forKey: .topCell)
            try container.encode(corners, forKey: .corners)
            try container.encodeIfPresent(technology, forKey: .technology)
            try container.encode(technologyByCorner, forKey: .technologyByCorner)
            try container.encodeIfPresent(processProfile, forKey: .processProfile)
            try container.encodeIfPresent(options, forKey: .options)
            try container.encode(tool, forKey: .tool)
        }
    }

    public struct PEX: Sendable, Hashable, Codable {
        public var stageID: String
        public var layoutPath: String?
        public var layoutInput: XcircuiteFlowInputReference?
        public var layoutFormat: LayoutFormat
        public var sourceNetlistPath: String?
        public var sourceNetlistInput: XcircuiteFlowInputReference?
        public var sourceNetlistFormat: NetlistFormat
        public var topCell: String
        public var corners: [PEXCorner]
        public var technology: XcircuitePEXTechnologySpec?
        public var technologyByCorner: [String: XcircuitePEXTechnologySpec]
        public var processProfile: PEXProcessProfileReference?
        public var backendSelection: PEXBackendSelection
        public var options: PEXRunOptions?
        public var tool: XcircuiteFlowToolSpec

        public init(
            stageID: String,
            layoutPath: String? = nil,
            layoutInput: XcircuiteFlowInputReference? = nil,
            layoutFormat: LayoutFormat,
            sourceNetlistPath: String? = nil,
            sourceNetlistInput: XcircuiteFlowInputReference? = nil,
            sourceNetlistFormat: NetlistFormat = .spice,
            topCell: String,
            corners: [PEXCorner],
            technology: XcircuitePEXTechnologySpec? = nil,
            technologyByCorner: [String: XcircuitePEXTechnologySpec] = [:],
            processProfile: PEXProcessProfileReference? = nil,
            backendSelection: PEXBackendSelection,
            options: PEXRunOptions? = nil,
            tool: XcircuiteFlowToolSpec = XcircuiteFlowToolSpec()
        ) {
            self.stageID = stageID
            self.layoutPath = layoutPath
            self.layoutInput = layoutInput
            self.layoutFormat = layoutFormat
            self.sourceNetlistPath = sourceNetlistPath
            self.sourceNetlistInput = sourceNetlistInput
            self.sourceNetlistFormat = sourceNetlistFormat
            self.topCell = topCell
            self.corners = corners
            self.technology = technology
            self.technologyByCorner = technologyByCorner
            self.processProfile = processProfile
            self.backendSelection = backendSelection
            self.options = options
            self.tool = tool
        }

        private enum CodingKeys: String, CodingKey {
            case stageID
            case layoutPath
            case layoutInput
            case layoutFormat
            case sourceNetlistPath
            case sourceNetlistInput
            case sourceNetlistFormat
            case topCell
            case corners
            case technology
            case technologyByCorner
            case processProfile
            case backendSelection
            case options
            case tool
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            stageID = try container.decode(String.self, forKey: .stageID)
            layoutPath = try container.decodeIfPresent(String.self, forKey: .layoutPath)
            layoutInput = try container.decodeIfPresent(XcircuiteFlowInputReference.self, forKey: .layoutInput)
            layoutFormat = try container.decode(LayoutFormat.self, forKey: .layoutFormat)
            sourceNetlistPath = try container.decodeIfPresent(String.self, forKey: .sourceNetlistPath)
            sourceNetlistInput = try container.decodeIfPresent(XcircuiteFlowInputReference.self, forKey: .sourceNetlistInput)
            sourceNetlistFormat = try container.decode(NetlistFormat.self, forKey: .sourceNetlistFormat)
            topCell = try container.decode(String.self, forKey: .topCell)
            corners = try container.decode([PEXCorner].self, forKey: .corners)
            technology = try container.decodeIfPresent(XcircuitePEXTechnologySpec.self, forKey: .technology)
            technologyByCorner = try container.decodeIfPresent(
                [String: XcircuitePEXTechnologySpec].self,
                forKey: .technologyByCorner
            ) ?? [:]
            processProfile = try container.decodeIfPresent(PEXProcessProfileReference.self, forKey: .processProfile)
            backendSelection = try container.decode(PEXBackendSelection.self, forKey: .backendSelection)
            options = try container.decodeIfPresent(PEXRunOptions.self, forKey: .options)
            tool = try container.decode(XcircuiteFlowToolSpec.self, forKey: .tool)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(stageID, forKey: .stageID)
            try container.encodeIfPresent(layoutPath, forKey: .layoutPath)
            try container.encodeIfPresent(layoutInput, forKey: .layoutInput)
            try container.encode(layoutFormat, forKey: .layoutFormat)
            try container.encodeIfPresent(sourceNetlistPath, forKey: .sourceNetlistPath)
            try container.encodeIfPresent(sourceNetlistInput, forKey: .sourceNetlistInput)
            try container.encode(sourceNetlistFormat, forKey: .sourceNetlistFormat)
            try container.encode(topCell, forKey: .topCell)
            try container.encode(corners, forKey: .corners)
            try container.encodeIfPresent(technology, forKey: .technology)
            try container.encode(technologyByCorner, forKey: .technologyByCorner)
            try container.encodeIfPresent(processProfile, forKey: .processProfile)
            try container.encode(backendSelection, forKey: .backendSelection)
            try container.encodeIfPresent(options, forKey: .options)
            try container.encode(tool, forKey: .tool)
        }
    }


    public struct CoreSpiceSimulation: Sendable, Hashable, Codable {
        public var stageID: String
        public var netlistPath: String
        public var expectations: [SimulationMeasurementExpectation]
        public var tool: XcircuiteFlowToolSpec

        public init(
            stageID: String,
            netlistPath: String,
            expectations: [SimulationMeasurementExpectation] = [],
            tool: XcircuiteFlowToolSpec = XcircuiteFlowToolSpec()
        ) {
            self.stageID = stageID
            self.netlistPath = netlistPath
            self.expectations = expectations
            self.tool = tool
        }
    }

    public struct PostLayoutComparison: Sendable, Hashable, Codable {
        public var stageID: String
        public var preLayoutWaveformPath: String?
        public var postLayoutWaveformPath: String?
        public var preLayoutWaveformInput: XcircuiteFlowInputReference?
        public var postLayoutWaveformInput: XcircuiteFlowInputReference?
        public var options: PostLayoutComparisonOptions
        public var tool: XcircuiteFlowToolSpec

        public init(
            stageID: String,
            preLayoutWaveformPath: String,
            postLayoutWaveformPath: String,
            options: PostLayoutComparisonOptions = PostLayoutComparisonOptions(),
            tool: XcircuiteFlowToolSpec = XcircuiteFlowToolSpec()
        ) {
            self.stageID = stageID
            self.preLayoutWaveformPath = preLayoutWaveformPath
            self.postLayoutWaveformPath = postLayoutWaveformPath
            self.preLayoutWaveformInput = nil
            self.postLayoutWaveformInput = nil
            self.options = options
            self.tool = tool
        }

        public init(
            stageID: String,
            preLayoutWaveformInput: XcircuiteFlowInputReference,
            postLayoutWaveformInput: XcircuiteFlowInputReference,
            options: PostLayoutComparisonOptions = PostLayoutComparisonOptions(),
            tool: XcircuiteFlowToolSpec = XcircuiteFlowToolSpec()
        ) {
            self.stageID = stageID
            self.preLayoutWaveformPath = nil
            self.postLayoutWaveformPath = nil
            self.preLayoutWaveformInput = preLayoutWaveformInput
            self.postLayoutWaveformInput = postLayoutWaveformInput
            self.options = options
            self.tool = tool
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case value
    }

    private enum Kind: String, Codable {
        case layoutCommand
        case nativeDRC
        case nativeLVS
        case pex
        case mockPEX
        case coreSpiceSimulation
        case postLayoutComparison
        case rtlVerification
        case logicSynthesis
        case logicEquivalence
        case logicQualification
        case dft
        case physicalReview
        case pdkDiscovery
        case pdkValidation
        case pdkCorpus
        case pdkStandardView
        case pdkRuleDeck
        case pdkOracle
        case pdkQualification
        case releaseQualification
        case releaseSignoff
        case releaseTapeout
        case releaseProfile
        case electricalStandardLayoutImport
        case electricalSignoff
        case electricalSignoffQualification
        case electricalSignoffReleaseGate
        case electricalRepairRevision
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .layoutCommand:
            self = .layoutCommand(try container.decode(LayoutCommand.self, forKey: .value))
        case .nativeDRC:
            self = .nativeDRC(try container.decode(NativeDRC.self, forKey: .value))
        case .nativeLVS:
            self = .nativeLVS(try container.decode(NativeLVS.self, forKey: .value))
        case .pex:
            self = .pex(try container.decode(PEX.self, forKey: .value))
        case .mockPEX:
            self = .mockPEX(try container.decode(MockPEX.self, forKey: .value))
        case .coreSpiceSimulation:
            self = .coreSpiceSimulation(try container.decode(CoreSpiceSimulation.self, forKey: .value))
        case .postLayoutComparison:
            self = .postLayoutComparison(try container.decode(PostLayoutComparison.self, forKey: .value))
        case .rtlVerification:
            self = .rtlVerification(try container.decode(RTLVerification.self, forKey: .value))
        case .logicSynthesis:
            self = .logicSynthesis(try container.decode(LogicSynthesis.self, forKey: .value))
        case .logicEquivalence:
            self = .logicEquivalence(try container.decode(LogicEquivalence.self, forKey: .value))
        case .logicQualification:
            self = .logicQualification(try container.decode(LogicQualification.self, forKey: .value))
        case .dft:
            self = .dft(try container.decode(DFT.self, forKey: .value))
        case .physicalReview:
            self = .physicalReview(try container.decode(PhysicalReview.self, forKey: .value))
        case .pdkDiscovery:
            self = .pdkDiscovery(try container.decode(PDKDiscovery.self, forKey: .value))
        case .pdkValidation:
            self = .pdkValidation(try container.decode(PDKValidation.self, forKey: .value))
        case .pdkCorpus:
            self = .pdkCorpus(try container.decode(PDKCorpus.self, forKey: .value))
        case .pdkStandardView:
            self = .pdkStandardView(try container.decode(PDKStandardView.self, forKey: .value))
        case .pdkRuleDeck:
            self = .pdkRuleDeck(try container.decode(PDKRuleDeck.self, forKey: .value))
        case .pdkOracle:
            self = .pdkOracle(try container.decode(PDKOracle.self, forKey: .value))
        case .pdkQualification:
            self = .pdkQualification(try container.decode(PDKQualification.self, forKey: .value))
        case .releaseQualification:
            self = .releaseQualification(try container.decode(ReleaseQualification.self, forKey: .value))
        case .releaseSignoff:
            self = .releaseSignoff(try container.decode(ReleaseSignoff.self, forKey: .value))
        case .releaseTapeout:
            self = .releaseTapeout(try container.decode(ReleaseTapeout.self, forKey: .value))
        case .releaseProfile:
            self = .releaseProfile(try container.decode(ReleaseProfile.self, forKey: .value))
        case .electricalStandardLayoutImport:
            self = .electricalStandardLayoutImport(try container.decode(ElectricalStandardLayoutImport.self, forKey: .value))
        case .electricalSignoff:
            self = .electricalSignoff(try container.decode(ElectricalSignoff.self, forKey: .value))
        case .electricalSignoffQualification:
            self = .electricalSignoffQualification(try container.decode(ElectricalSignoffQualification.self, forKey: .value))
        case .electricalSignoffReleaseGate:
            self = .electricalSignoffReleaseGate(try container.decode(ElectricalSignoffReleaseGate.self, forKey: .value))
        case .electricalRepairRevision:
            self = .electricalRepairRevision(try container.decode(ElectricalRepairRevision.self, forKey: .value))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .layoutCommand(let value):
            try container.encode(Kind.layoutCommand, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .nativeDRC(let value):
            try container.encode(Kind.nativeDRC, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .nativeLVS(let value):
            try container.encode(Kind.nativeLVS, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .pex(let value):
            try container.encode(Kind.pex, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .mockPEX(let value):
            try container.encode(Kind.mockPEX, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .coreSpiceSimulation(let value):
            try container.encode(Kind.coreSpiceSimulation, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .postLayoutComparison(let value):
            try container.encode(Kind.postLayoutComparison, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .rtlVerification(let value):
            try container.encode(Kind.rtlVerification, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .logicSynthesis(let value):
            try container.encode(Kind.logicSynthesis, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .logicEquivalence(let value):
            try container.encode(Kind.logicEquivalence, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .logicQualification(let value):
            try container.encode(Kind.logicQualification, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .dft(let value):
            try container.encode(Kind.dft, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .physicalReview(let value):
            try container.encode(Kind.physicalReview, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .pdkDiscovery(let value):
            try container.encode(Kind.pdkDiscovery, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .pdkValidation(let value):
            try container.encode(Kind.pdkValidation, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .pdkCorpus(let value):
            try container.encode(Kind.pdkCorpus, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .pdkStandardView(let value):
            try container.encode(Kind.pdkStandardView, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .pdkRuleDeck(let value):
            try container.encode(Kind.pdkRuleDeck, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .pdkOracle(let value):
            try container.encode(Kind.pdkOracle, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .pdkQualification(let value):
            try container.encode(Kind.pdkQualification, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .releaseQualification(let value):
            try container.encode(Kind.releaseQualification, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .releaseSignoff(let value):
            try container.encode(Kind.releaseSignoff, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .releaseTapeout(let value):
            try container.encode(Kind.releaseTapeout, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .releaseProfile(let value):
            try container.encode(Kind.releaseProfile, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .electricalStandardLayoutImport(let value):
            try container.encode(Kind.electricalStandardLayoutImport, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .electricalSignoff(let value):
            try container.encode(Kind.electricalSignoff, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .electricalSignoffQualification(let value):
            try container.encode(Kind.electricalSignoffQualification, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .electricalSignoffReleaseGate(let value):
            try container.encode(Kind.electricalSignoffReleaseGate, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .electricalRepairRevision(let value):
            try container.encode(Kind.electricalRepairRevision, forKey: .kind)
            try container.encode(value, forKey: .value)
        }
    }

    func makeExecutor(
        projectRoot: URL,
        toolchainProfile: XcircuiteFlowToolchainProfile? = nil
    ) throws -> any FlowStageExecutor {
        switch self {
        case .layoutCommand(let spec):
            return LayoutCommandFlowStageExecutor(
                stageID: spec.stageID,
                requestURL: try XcircuiteFlowRuntimeSpec.resolvePath(spec.requestPath, projectRoot: projectRoot),
                drcExport: spec.drcExport,
                standardLayoutExports: spec.standardLayoutExports
            )
        case .nativeDRC(let spec):
            return DRCFlowStageExecutor.native(
                stageID: spec.stageID,
                layoutInput: try spec.resolvedLayoutInput(),
                topCell: spec.topCell,
                layoutFormat: spec.layoutFormat,
                technologyInput: spec.resolvedTechnologyInput(toolchainProfile: toolchainProfile),
                options: spec.options ?? DRCOptions()
            )
        case .nativeLVS(let spec):
            return LVSFlowStageExecutor.native(
                stageID: spec.stageID,
                layoutNetlistInput: spec.resolvedLayoutNetlistInput(),
                layoutGDSInput: spec.resolvedLayoutGDSInput(),
                layoutFormat: spec.layoutFormat,
                schematicNetlistInput: try spec.resolvedSchematicNetlistInput(),
                topCell: spec.topCell,
                technologyInput: spec.resolvedTechnologyInput(toolchainProfile: toolchainProfile),
                terminalEquivalenceInput: spec.resolvedTerminalEquivalenceInput(),
                options: spec.options ?? LVSOptions()
            )
        case .pex(let spec):
            return PEXFlowStageExecutor(
                stageID: spec.stageID,
                toolID: SignoffToolDescriptors.pexToolID(backendID: spec.backendSelection.backendID),
                layoutInput: try spec.resolvedLayoutInput(),
                layoutFormat: spec.layoutFormat,
                sourceNetlistInput: try spec.resolvedSourceNetlistInput(),
                sourceNetlistFormat: spec.sourceNetlistFormat,
                topCell: spec.topCell,
                corners: spec.corners,
                technology: try spec.resolvedTechnology(toolchainProfile: toolchainProfile),
                technologyByCorner: try spec.resolvedTechnologyByCorner(toolchainProfile: toolchainProfile),
                processProfile: try spec.resolvedProcessProfile(projectRoot: projectRoot),
                backendSelection: spec.backendSelection,
                options: spec.options ?? .default,
                engine: DefaultPEXEngine.withDefaults()
            )
        case .mockPEX(let spec):
            return PEXFlowStageExecutor.mock(
                stageID: spec.stageID,
                layoutInput: try spec.resolvedLayoutInput(),
                layoutFormat: spec.layoutFormat,
                sourceNetlistInput: try spec.resolvedSourceNetlistInput(),
                sourceNetlistFormat: spec.sourceNetlistFormat,
                topCell: spec.topCell,
                corners: spec.corners,
                technology: try spec.resolvedTechnology(toolchainProfile: toolchainProfile),
                technologyByCorner: try spec.resolvedTechnologyByCorner(toolchainProfile: toolchainProfile),
                processProfile: try spec.resolvedProcessProfile(projectRoot: projectRoot),
                options: spec.options ?? .default
            )
        case .coreSpiceSimulation(let spec):
            return SimulationFlowStageExecutor(
                stageID: spec.stageID,
                netlistURL: try XcircuiteFlowRuntimeSpec.resolvePath(spec.netlistPath, projectRoot: projectRoot),
                expectations: spec.expectations
            )
        case .postLayoutComparison(let spec):
            return PostLayoutComparisonFlowStageExecutor(
                stageID: spec.stageID,
                preLayoutWaveformInput: try spec.resolvedPreLayoutWaveformInput(),
                postLayoutWaveformInput: try spec.resolvedPostLayoutWaveformInput(),
                options: spec.options
            )
        case .rtlVerification(let spec):
            return RTLVerificationFlowStageExecutor(
                stageID: spec.stageID,
                analysis: spec.analysis,
                rtlInput: spec.rtlInput,
                additionalRTLInputs: spec.additionalRTLInputs,
                referenceInput: spec.referenceInput,
                additionalReferenceInputs: spec.additionalReferenceInputs,
                constraintsInput: spec.constraintsInput,
                qualificationInput: spec.qualificationInput,
                topModuleName: spec.topModuleName,
                policy: spec.policy,
                frontend: spec.frontend,
                proofView: spec.proofView,
                assumptions: spec.assumptions
            )
        case .logicSynthesis(let spec):
            return LogicSynthesisFlowStageExecutor(
                stageID: spec.stageID,
                requestInput: .path(spec.requestPath)
            )
        case .logicEquivalence(let spec):
            return LogicEquivalenceFlowStageExecutor(
                stageID: spec.stageID,
                requestInput: .path(spec.requestPath)
            )
        case .logicQualification(let spec):
            return LogicQualificationFlowStageExecutor(
                stageID: spec.stageID,
                reportInput: .path(spec.reportPath),
                processEvidenceInput: spec.processEvidencePath.map { .path($0) },
                releaseApprovalInput: spec.releaseApprovalPath.map { .path($0) }
            )
        case .dft(let spec):
            if let corpusPath = spec.qualificationCorpusPath {
                guard let observationsPath = spec.qualificationObservationsPath else {
                    throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                        stageID: spec.stageID,
                        field: "qualificationObservationsPath"
                    )
                }
                return DFTQualificationFlowStageExecutor(
                    stageID: spec.stageID,
                    corpusInput: .path(corpusPath),
                    observationsInput: .path(observationsPath),
                    qualificationEvidenceInput: spec.qualificationEvidencePath.map { .path($0) }
                )
            }
            if let resultPath = spec.releaseResultPath {
                guard let downstreamEvidencePath = spec.releaseDownstreamEvidencePath else {
                    throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                        stageID: spec.stageID,
                        field: "releaseDownstreamEvidencePath"
                    )
                }
                return DFTReleaseFlowStageExecutor(
                    stageID: spec.stageID,
                    requestInput: .path(spec.requestPath),
                    resultInput: .path(resultPath),
                    downstreamEvidenceInput: .path(downstreamEvidencePath),
                    approvalInput: spec.releaseApprovalPath.map { .path($0) }
                )
            }
            return DFTFlowStageExecutor(
                stageID: spec.stageID,
                toolID: "dft-engine",
                requestInput: .path(spec.requestPath)
            )
        case .physicalReview(let spec):
            return PhysicalDesignReviewFlowStageExecutor(
                stageID: spec.stageID,
                manifestInput: spec.manifestInput,
                decisionScope: spec.decisionScope
            )
        case .pdkDiscovery(let spec):
            return PDKDiscoveryFlowStageExecutor.local(
                stageID: spec.stageID,
                searchRoots: spec.searchRoots,
                requiredProcessID: spec.requiredProcessID
            )
        case .pdkValidation(let spec):
            return PDKValidationFlowStageExecutor.local(
                stageID: spec.stageID,
                manifestInput: spec.manifestInput,
                requiredAssetRoles: spec.requiredAssetRoles,
                validateCrossViews: spec.validateCrossViews
            )
        case .pdkCorpus(let spec):
            return PDKCorpusValidationFlowStageExecutor.local(
                stageID: spec.stageID,
                suiteInput: spec.suiteInput,
                rootInput: spec.rootInput
            )
        case .pdkStandardView(let spec):
            if let externalProcess = spec.externalProcess {
                return PDKStandardViewInspectionFlowStageExecutor.external(
                    configuration: externalProcess,
                    stageID: spec.stageID,
                    manifestInput: spec.manifestInput,
                    assetID: spec.assetID,
                    format: spec.format
                )
            }
            return PDKStandardViewInspectionFlowStageExecutor.local(
                stageID: spec.stageID,
                manifestInput: spec.manifestInput,
                assetID: spec.assetID,
                format: spec.format
            )
        case .pdkRuleDeck(let spec):
            if let externalProcess = spec.externalProcess {
                return PDKRuleDeckInspectionFlowStageExecutor.external(
                    configuration: externalProcess,
                    stageID: spec.stageID,
                    manifestInput: spec.manifestInput,
                    assetID: spec.assetID
                )
            }
            return PDKRuleDeckInspectionFlowStageExecutor.local(
                stageID: spec.stageID,
                manifestInput: spec.manifestInput,
                assetID: spec.assetID
            )
        case .pdkOracle(let spec):
            return PDKOracleFlowStageExecutor.local(
                stageID: spec.stageID,
                manifestInput: spec.manifestInput,
                oracleInput: spec.oracleInput
            )
        case .pdkQualification(let spec):
            return PDKQualificationFlowStageExecutor.local(
                stageID: spec.stageID,
                manifestInput: spec.manifestInput,
                corpusInput: spec.corpusInput,
                oracleInput: spec.oracleInput
            )
        case .releaseQualification(let spec):
            return ReleaseQualificationFlowStageExecutor(
                stageID: spec.stageID,
                requestInput: .path(spec.requestPath)
            )
        case .releaseSignoff(let spec):
            return ReleaseSignoffFlowStageExecutor(
                stageID: spec.stageID,
                requestInput: .path(spec.requestPath)
            )
        case .releaseTapeout(let spec):
            return ReleaseTapeoutFlowStageExecutor(
                stageID: spec.stageID,
                requestInput: .path(spec.requestPath)
            )
        case .releaseProfile(let spec):
            return ReleaseProfileEligibilityFlowStageExecutor(
                stageID: spec.stageID,
                requestInput: .path(spec.requestPath)
            )
        case .electricalStandardLayoutImport(let spec):
            return ElectricalStandardLayoutImportFlowStageExecutor(
                stageID: spec.stageID,
                toolID: "native-electrical-standard-layout-import",
                layoutInput: spec.layoutInput,
                layoutFormat: spec.layoutFormat,
                technologyInput: spec.technologyInput,
                technologyFormat: spec.technologyFormat,
                connectivityInput: spec.connectivityInput,
                connectivityFormat: spec.connectivityFormat,
                topCellName: spec.topCellName
            )
        case .electricalSignoff(let spec):
            let request: ElectricalSignoffRequest = try loadJSON(
                ElectricalSignoffRequest.self,
                path: spec.requestPath,
                projectRoot: projectRoot,
                stageID: spec.stageID
            )
            return ElectricalSignoffFlowStageExecutor(
                stageID: spec.stageID,
                toolID: "native-electrical-signoff",
                request: request,
                axes: spec.axes,
                engine: ElectricalSignoffEngine(
                    support: ElectricalSignoffExecutionSupport(projectRoot: projectRoot)
                )
            )
        case .electricalSignoffQualification(let spec):
            let oracle: (any ElectricalSignoffQualificationOracle)?
            if let oraclePath = spec.oraclePath {
                let oracleURL = try XcircuiteFlowRuntimeSpec.resolvePath(oraclePath, projectRoot: projectRoot)
                oracle = try LocalElectricalSignoffQualificationOracle(contentsOf: oracleURL)
            } else {
                oracle = nil
            }
            return ElectricalSignoffQualificationFlowStageExecutor(
                stageID: spec.stageID,
                toolID: "native-electrical-signoff-qualification",
                requestInput: .path(spec.specPath),
                qualificationScope: spec.qualificationScope,
                runner: ElectricalSignoffQualificationRunner(
                    engine: ElectricalSignoffEngine(
                        support: ElectricalSignoffExecutionSupport(projectRoot: projectRoot)
                    ),
                    oracle: oracle
                )
            )
        case .electricalSignoffReleaseGate(let spec):
            return ElectricalSignoffReleaseGateFlowStageExecutor(
                stageID: spec.stageID,
                toolID: "native-electrical-signoff-release-gate",
                requestInput: spec.requestInput,
                runResultInput: spec.runResultInput,
                qualificationSpecInput: spec.qualificationSpecInput,
                qualificationReportInput: spec.qualificationReportInput,
                policyInput: spec.policyInput
            )
        case .electricalRepairRevision(let spec):
            let requestURL = try XcircuiteFlowRuntimeSpec.resolvePath(spec.requestPath, projectRoot: projectRoot)
            let data: Data
            do {
                data = try Data(contentsOf: requestURL)
            } catch {
                throw XcircuiteFlowRuntimeSpecError.invalidPath(
                    "\(spec.stageID).requestPath: \(error.localizedDescription)"
                )
            }
            let request: XcircuiteElectricalRepairRevisionRequest
            do {
                request = try JSONDecoder().decode(XcircuiteElectricalRepairRevisionRequest.self, from: data)
            } catch {
                throw XcircuiteFlowRuntimeSpecError.invalidPath(
                    "\(spec.stageID).requestPath: \(error.localizedDescription)"
                )
            }
            return ElectricalSignoffRepairRevisionFlowStageExecutor(
                stageID: spec.stageID,
                toolID: "native-electrical-signoff-repair-revision",
                request: request
            )
        }
    }

    private func loadJSON<Value: Decodable>(
        _ type: Value.Type,
        path: String,
        projectRoot: URL,
        stageID: String
    ) throws -> Value {
        let url: URL
        do {
            url = try XcircuiteFlowRuntimeSpec.resolvePath(path, projectRoot: projectRoot)
        } catch {
            throw XcircuiteFlowRuntimeSpecError.invalidPath(
                "(stageID).requestPath: (error.localizedDescription)"
            )
        }
        do {
            return try JSONDecoder().decode(Value.self, from: Data(contentsOf: url))
        } catch {
            throw XcircuiteFlowRuntimeSpecError.invalidPath(
                "(stageID).requestPath: (error.localizedDescription)"
            )
        }
    }

    public func makeDescriptor() -> ToolDescriptor {
        switch self {
        case .layoutCommand(let spec):
            SignoffToolDescriptors.layoutCommand(level: spec.tool.qualificationLevel)
        case .nativeDRC(let spec):
            SignoffToolDescriptors.nativeDRC(level: spec.tool.qualificationLevel)
        case .nativeLVS(let spec):
            SignoffToolDescriptors.nativeLVS(level: spec.tool.qualificationLevel)
        case .pex(let spec):
            SignoffToolDescriptors.pexBackend(
                backendID: spec.backendSelection.backendID,
                level: spec.tool.qualificationLevel
            )
        case .mockPEX(let spec):
            SignoffToolDescriptors.mockPEX(level: spec.tool.qualificationLevel)
        case .coreSpiceSimulation(let spec):
            SignoffToolDescriptors.coreSpiceSimulation(level: spec.tool.qualificationLevel)
        case .postLayoutComparison(let spec):
            SignoffToolDescriptors.postLayoutComparison(level: spec.tool.qualificationLevel)
        case .rtlVerification(let spec):
            RTLToolDescriptors.native(level: spec.tool.qualificationLevel)
        case .logicSynthesis(let spec):
            LogicToolDescriptors.synthesis(level: spec.tool.qualificationLevel)
        case .logicEquivalence(let spec):
            LogicToolDescriptors.equivalence(level: spec.tool.qualificationLevel)
        case .logicQualification(let spec):
            LogicToolDescriptors.qualification(level: spec.tool.qualificationLevel)
        case .dft(let spec):
            if spec.qualificationCorpusPath != nil || spec.qualificationObservationsPath != nil {
                DFTToolDescriptors.qualification(level: spec.tool.qualificationLevel)
            } else {
                DFTToolDescriptors.engine(level: spec.tool.qualificationLevel)
            }
        case .physicalReview(let spec):
            PhysicalDesignToolDescriptors.review(level: spec.tool.qualificationLevel)
        case .pdkDiscovery(let spec):
            PDKToolDescriptors.discovery(level: spec.tool.qualificationLevel)
        case .pdkValidation(let spec):
            PDKToolDescriptors.validation(level: spec.tool.qualificationLevel)
        case .pdkCorpus(let spec):
            PDKToolDescriptors.corpus(level: spec.tool.qualificationLevel)
        case .pdkStandardView(let spec):
            PDKToolDescriptors.standardView(level: spec.tool.qualificationLevel)
        case .pdkRuleDeck(let spec):
            PDKToolDescriptors.ruleDeck(level: spec.tool.qualificationLevel)
        case .pdkOracle(let spec):
            PDKToolDescriptors.oracle(level: spec.tool.qualificationLevel)
        case .pdkQualification(let spec):
            PDKToolDescriptors.qualification(level: spec.tool.qualificationLevel)
        case .releaseQualification(let spec):
            ReleaseToolDescriptors.qualification(level: spec.tool.qualificationLevel)
        case .releaseSignoff(let spec):
            ReleaseToolDescriptors.signoff(level: spec.tool.qualificationLevel)
        case .releaseTapeout(let spec):
            ReleaseToolDescriptors.tapeout(level: spec.tool.qualificationLevel)
        case .releaseProfile(let spec):
            ReleaseToolDescriptors.profile(level: spec.tool.qualificationLevel)
        case .electricalStandardLayoutImport(let spec):
            SignoffToolDescriptors.nativeElectricalStandardLayoutImport(level: spec.tool.qualificationLevel)
        case .electricalSignoff(let spec):
            SignoffToolDescriptors.nativeElectricalSignoff(level: spec.tool.qualificationLevel)
        case .electricalSignoffQualification(let spec):
            SignoffToolDescriptors.nativeElectricalQualification(level: spec.tool.qualificationLevel)
        case .electricalSignoffReleaseGate(let spec):
            SignoffToolDescriptors.nativeElectricalReleaseGate(level: spec.tool.qualificationLevel)
        case .electricalRepairRevision(let spec):
            SignoffToolDescriptors.nativeElectricalRepairRevision(level: spec.tool.qualificationLevel)
        }
    }

    func makeHealthResult() -> ToolHealthCheckResult {
        let descriptor = makeDescriptor()
        return ToolHealthCheckResult(
            toolID: descriptor.toolID,
            status: toolSpec.healthStatus,
            evidence: toolSpec.evidence
        )
    }

    private var toolSpec: XcircuiteFlowToolSpec {
        switch self {
        case .layoutCommand(let spec):
            spec.tool
        case .nativeDRC(let spec):
            spec.tool
        case .nativeLVS(let spec):
            spec.tool
        case .pex(let spec):
            spec.tool
        case .mockPEX(let spec):
            spec.tool
        case .coreSpiceSimulation(let spec):
            spec.tool
        case .postLayoutComparison(let spec):
            spec.tool
        case .rtlVerification(let spec):
            spec.tool
        case .logicSynthesis(let spec):
            spec.tool
        case .logicEquivalence(let spec):
            spec.tool
        case .logicQualification(let spec):
            spec.tool
        case .dft(let spec):
            spec.tool
        case .physicalReview(let spec):
            spec.tool
        case .pdkDiscovery(let spec):
            spec.tool
        case .pdkValidation(let spec):
            spec.tool
        case .pdkCorpus(let spec):
            spec.tool
        case .pdkStandardView(let spec):
            spec.tool
        case .pdkRuleDeck(let spec):
            spec.tool
        case .pdkOracle(let spec):
            spec.tool
        case .pdkQualification(let spec):
            spec.tool
        case .releaseQualification(let spec):
            spec.tool
        case .releaseSignoff(let spec):
            spec.tool
        case .releaseTapeout(let spec):
            spec.tool
        case .releaseProfile(let spec):
            spec.tool
        case .electricalStandardLayoutImport(let spec):
            spec.tool
        case .electricalSignoff(let spec):
            spec.tool
        case .electricalSignoffQualification(let spec):
            spec.tool
        case .electricalSignoffReleaseGate(let spec):
            spec.tool
        case .electricalRepairRevision(let spec):
            spec.tool
        }
    }
}

private extension XcircuiteFlowStageExecutorSpec.PostLayoutComparison {
    func resolvedPreLayoutWaveformInput() throws -> XcircuiteFlowInputReference {
        if let preLayoutWaveformInput {
            return preLayoutWaveformInput
        }
        if let preLayoutWaveformPath {
            return .path(preLayoutWaveformPath)
        }
        throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
            stageID: stageID,
            field: "preLayoutWaveformPath or preLayoutWaveformInput"
        )
    }

    func resolvedPostLayoutWaveformInput() throws -> XcircuiteFlowInputReference {
        if let postLayoutWaveformInput {
            return postLayoutWaveformInput
        }
        if let postLayoutWaveformPath {
            return .path(postLayoutWaveformPath)
        }
        throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
            stageID: stageID,
            field: "postLayoutWaveformPath or postLayoutWaveformInput"
        )
    }
}

private extension XcircuiteFlowStageExecutorSpec.NativeDRC {
    func resolvedLayoutInput() throws -> XcircuiteFlowInputReference {
        if let layoutInput {
            return layoutInput
        }
        if let layoutPath {
            return .path(layoutPath)
        }
        throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(stageID: stageID, field: "layoutPath or layoutInput")
    }

    func resolvedTechnologyInput(toolchainProfile: XcircuiteFlowToolchainProfile?) -> XcircuiteFlowInputReference? {
        if let technologyInput {
            return technologyInput
        }
        if let technologyPath {
            return .path(technologyPath)
        }
        return toolchainProfile?.drcTechnologyInput
    }

}

private extension XcircuiteFlowStageExecutorSpec.NativeLVS {
    func resolvedLayoutNetlistInput() -> XcircuiteFlowInputReference? {
        if let layoutNetlistInput {
            return layoutNetlistInput
        }
        return layoutNetlistPath.map { .path($0) }
    }

    func resolvedLayoutGDSInput() -> XcircuiteFlowInputReference? {
        if let layoutGDSInput {
            return layoutGDSInput
        }
        return layoutGDSPath.map { .path($0) }
    }

    func resolvedSchematicNetlistInput() throws -> XcircuiteFlowInputReference {
        if let schematicNetlistInput {
            return schematicNetlistInput
        }
        if let schematicNetlistPath {
            return .path(schematicNetlistPath)
        }
        throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
            stageID: stageID,
            field: "schematicNetlistPath or schematicNetlistInput"
        )
    }

    func resolvedTechnologyInput(toolchainProfile: XcircuiteFlowToolchainProfile?) -> XcircuiteFlowInputReference? {
        if let technologyInput {
            return technologyInput
        }
        if let technologyPath {
            return .path(technologyPath)
        }
        return toolchainProfile?.lvsTechnologyInput
    }

    func resolvedTerminalEquivalenceInput() -> XcircuiteFlowInputReference? {
        if let terminalEquivalenceInput {
            return terminalEquivalenceInput
        }
        return terminalEquivalencePath.map { .path($0) }
    }
}

private extension XcircuiteFlowStageExecutorSpec.MockPEX {
    func resolvedLayoutInput() throws -> XcircuiteFlowInputReference {
        if let layoutInput {
            return layoutInput
        }
        if let layoutPath {
            return .path(layoutPath)
        }
        throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(stageID: stageID, field: "layoutPath or layoutInput")
    }

    func resolvedSourceNetlistInput() throws -> XcircuiteFlowInputReference {
        if let sourceNetlistInput {
            return sourceNetlistInput
        }
        if let sourceNetlistPath {
            return .path(sourceNetlistPath)
        }
        throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
            stageID: stageID,
            field: "sourceNetlistPath or sourceNetlistInput"
        )
    }

    func resolvedTechnology(toolchainProfile: XcircuiteFlowToolchainProfile?) throws -> XcircuitePEXTechnologySpec {
        if let technology {
            return technology
        }
        if let technology = toolchainProfile?.pexTechnology {
            return technology
        }
        throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
            stageID: stageID,
            field: "technology or toolchainProfile.pexTechnology"
        )
    }

    func resolvedTechnologyByCorner(
        toolchainProfile: XcircuiteFlowToolchainProfile?
    ) throws -> [String: XcircuitePEXTechnologySpec] {
        var resolved = toolchainProfile?.pexTechnologyByCorner ?? [:]
        for (cornerID, technology) in technologyByCorner {
            resolved[cornerID] = technology
        }
        return resolved
    }

    func resolvedProcessProfile(projectRoot: URL) throws -> PEXProcessProfileReference? {
        try processProfile.map { try $0.resolved(projectRoot: projectRoot) }
    }
}

private extension XcircuiteFlowStageExecutorSpec.PEX {
    func resolvedLayoutInput() throws -> XcircuiteFlowInputReference {
        if let layoutInput {
            return layoutInput
        }
        if let layoutPath {
            return .path(layoutPath)
        }
        throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(stageID: stageID, field: "layoutPath or layoutInput")
    }

    func resolvedSourceNetlistInput() throws -> XcircuiteFlowInputReference {
        if let sourceNetlistInput {
            return sourceNetlistInput
        }
        if let sourceNetlistPath {
            return .path(sourceNetlistPath)
        }
        throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
            stageID: stageID,
            field: "sourceNetlistPath or sourceNetlistInput"
        )
    }

    func resolvedTechnology(toolchainProfile: XcircuiteFlowToolchainProfile?) throws -> XcircuitePEXTechnologySpec {
        if let technology {
            return technology
        }
        if let technology = toolchainProfile?.pexTechnology {
            return technology
        }
        throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
            stageID: stageID,
            field: "technology or toolchainProfile.pexTechnology"
        )
    }

    func resolvedTechnologyByCorner(
        toolchainProfile: XcircuiteFlowToolchainProfile?
    ) throws -> [String: XcircuitePEXTechnologySpec] {
        var resolved = toolchainProfile?.pexTechnologyByCorner ?? [:]
        for (cornerID, technology) in technologyByCorner {
            resolved[cornerID] = technology
        }
        return resolved
    }

    func resolvedProcessProfile(projectRoot: URL) throws -> PEXProcessProfileReference? {
        try processProfile.map { try $0.resolved(projectRoot: projectRoot) }
    }
}

private extension PEXProcessProfileReference {
    func resolved(projectRoot: URL) throws -> PEXProcessProfileReference {
        func resolve(_ path: String?) throws -> String? {
            guard let path else {
                return nil
            }
            if path.hasPrefix("/") {
                return path
            }
            return try XcircuiteFlowRuntimeSpec.resolvePath(path, projectRoot: projectRoot)
                .path(percentEncoded: false)
        }

        var resolvedCornerDeckPaths: [String: String] = [:]
        for (cornerID, path) in cornerDeckPaths {
            if let resolvedPath = try resolve(path) {
                resolvedCornerDeckPaths[cornerID] = resolvedPath
            }
        }
        return PEXProcessProfileReference(
            profileID: profileID,
            pdkID: pdkID,
            source: source,
            requirementID: requirementID,
            pdkRoot: try resolve(pdkRoot),
            primaryDeckPath: try resolve(primaryDeckPath),
            cornerDeckPaths: resolvedCornerDeckPaths,
            metadata: metadata
        )
    }
}
