import DesignFlowKernel
import DRCEngine
import Foundation
import LayoutCommands
import LVSEngine
import PEXEngine
import ToolQualification

public enum XcircuiteFlowStageExecutorSpec: Sendable, Hashable, Codable {
    case layoutCommand(LayoutCommand)
    case nativeDRC(NativeDRC)
    case nativeLVS(NativeLVS)
    case pex(PEX)
    case mockPEX(MockPEX)
    case coreSpiceSimulation(CoreSpiceSimulation)
    case postLayoutComparison(PostLayoutComparison)

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
        }
    }

    func makeDescriptor() -> ToolDescriptor {
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
