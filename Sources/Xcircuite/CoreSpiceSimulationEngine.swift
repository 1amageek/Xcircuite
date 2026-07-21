import CircuiteFoundation
import Foundation
import CoreSpice
import CoreSpiceIO
import CoreSpiceWaveform

/// In-process CoreSpice driver for the simulation flow stage: parse →
/// lower → compile → bind → run the netlist's own first analysis
/// directive (`.op`, `.dc`, `.ac`, `.tran`, `.noise`, `.tf`, `.sens`,
/// `.pz`, `.four`, or `.mc`; nothing defaults to `.op`)
/// → evaluate the netlist's `.measure` statements.
public struct CoreSpiceSimulationEngine: SimulationExecuting {
    private let producerIdentifier: String
    private let producerVersion: String

    public enum EngineError: Error, LocalizedError, Equatable {
        case missingAnalysisDirective
        case unsupportedAnalysis(String)
        case missingDeviceDescriptor(String)

        public var errorDescription: String? {
            switch self {
            case .missingAnalysisDirective:
                return "No simulation analysis directive was found. Add an explicit .op, .dc, .ac, .tran, .noise, .tf, .sens, .pz, .four, or .mc directive."
            case .unsupportedAnalysis(let kind):
                return "The simulation stage supports .op, .dc, .ac, .tran, .noise, .tf, .sens, .pz, .four, and .mc; the netlist asks for \(kind)."
            case .missingDeviceDescriptor(let type):
                return "No device descriptor is registered for '\(type)'."
            }
        }
    }

    public init(
        producerIdentifier: String = "corespice",
        producerVersion: String = "1.0.0"
    ) {
        self.producerIdentifier = producerIdentifier
        self.producerVersion = producerVersion
    }

    public func execute(_ request: SimulationExecutionRequest) async throws -> SimulationStageOutcome {
        let startedAt = Date()
        let analysis = try await runAnalysis(
            netlistSource: request.netlistSource,
            fileName: request.fileName
        )
        let completedAt = Date()
        let execution = try CoreSpiceSimulationExecution(
            artifacts: [],
            invocation: ExecutionInvocation.inProcess(
                entryPoint: "CoreSpiceSimulationEngine.execute"
            ),
            environment: ExecutionEnvironmentFingerprint(
                platform: "macOS",
                architecture: Self.architecture,
                toolchain: "Swift"
            ),
            startedAt: startedAt,
            completedAt: completedAt
        )
        let executableIdentity = try XcircuiteRuntimeProducerIdentity.current()
        let result = try CoreSpiceSimulationResult(
            request: CoreSpiceSimulationRequest(inputs: request.inputs),
            execution: execution,
            producer: ProducerIdentity(
                kind: .engine,
                identifier: producerIdentifier,
                version: producerVersion,
                build: executableIdentity.build
            )
        )
        return SimulationStageOutcome(
            analysisLabel: analysis.analysisLabel,
            measurements: analysis.measurements,
            waveformCSV: analysis.waveformCSV,
            coreSpiceResult: result
        )
    }

    private func runAnalysis(
        netlistSource: String,
        fileName: String?
    ) async throws -> SimulationAnalysisOutput {
        let csvExporter = SimulationWaveformCSVExporter()
        let netlist = try await SPICEIO.parse(netlistSource, fileName: fileName).get()
        let options = try SPICEAnalysisOptions.resolve(from: netlist)
        let ir = try SPICEIO.lower(netlist, configuration: options.loweringConfiguration())
        let plan = try StandardCompiler().compile(ir: ir)
        let devices = try bind(plan: plan)

        let solver = SparseLUSolver()
        let cancellation = CancellationToken()
        let waveform: WaveformData
        let label: String

        guard let analysis = try firstAnalysis(of: netlist) else {
            throw EngineError.missingAnalysisDirective
        }

        switch analysis {
        case .op:
            let result = try await DCAnalysis(config: options.convergence).run(
                plan: plan,
                devices: devices,
                solver: solver,
                observer: nil,
                cancellation: cancellation
            )
            waveform = WaveformData.from(
                dcResult: result,
                topology: plan.topology.circuitTopology,
                title: "Operating Point"
            )
            label = "op"
        case .transient(let spec):
            let config = try transientConfig(from: spec, options: options)
            let result = try await TransientAnalysis(
                config: config,
                convergenceConfig: options.convergence
            ).run(
                plan: plan,
                devices: devices,
                solver: solver,
                observer: nil,
                cancellation: cancellation
            )
            waveform = try WaveformData.from(
                transientResult: result,
                topology: plan.topology.circuitTopology,
                title: "Transient"
            )
            label = "tran"
        case .dc(let spec):
            let start = try requiredNumeric(spec.startValue, label: ".dc start value")
            let stop = try requiredNumeric(spec.stopValue, label: ".dc stop value")
            let step = try requiredNumeric(spec.stepValue, label: ".dc step value")
            guard step != 0, step.isFinite else {
                throw EngineError.unsupportedAnalysis(".dc without a finite non-zero step value")
            }
            let values = strideInclusive(from: start, through: stop, by: step)
            guard !values.isEmpty else {
                throw EngineError.unsupportedAnalysis(".dc sweep produced no points")
            }
            let sourceName = try validatedSweepSource(spec.source, in: plan, label: ".dc")
            var results: [DCResult] = []
            results.reserveCapacity(values.count)
            for value in values {
                let devices = try bind(plan: plan, overrideSource: (sourceName, value))
                let result = try await DCAnalysis(config: options.convergence).run(
                    plan: plan,
                    devices: devices,
                    solver: solver,
                    observer: nil,
                    cancellation: cancellation
                )
                results.append(result)
            }
            let sweepResult = SweepResult(parameterName: spec.source, values: values, results: results)
            waveform = WaveformData.from(
                sweepResult: sweepResult,
                topology: plan.topology.circuitTopology,
                title: "DC Sweep"
            )
            label = "dc"
        case .ac(let spec):
            let sweep = try frequencySweep(from: spec)
            let result = try await ACAnalysis(sweep: sweep, dcConfig: options.convergence).run(
                plan: plan,
                devices: devices,
                solver: solver,
                observer: nil,
                cancellation: cancellation
            )
            waveform = WaveformData.from(
                acResult: result,
                topology: plan.topology.circuitTopology,
                title: "AC"
            )
            label = "ac"
        case .noise(let spec):
            try requireGroundReference(spec.referenceNode, label: ".noise reference node")
            let outputNode = try node(named: spec.outputNode, in: plan)
            let sweep = try frequencySweep(from: spec)
            let result = try await NoiseAnalysis(
                outputNode: outputNode,
                inputSourceName: spec.inputSource,
                sweep: sweep,
                dcConfig: options.convergence
            ).run(
                plan: plan,
                devices: devices,
                solver: solver,
                observer: nil,
                cancellation: cancellation
            )
            waveform = WaveformData.from(noiseResult: result, title: "Noise")
            label = "noise"
        case .transferFunction(let spec):
            let outputNode = try outputNode(from: spec.output, in: plan, label: ".tf output")
            let result = try await TransferFunctionAnalysis(
                outputNode: outputNode,
                inputSourceName: spec.input,
                dcConfig: options.convergence
            ).run(
                plan: plan,
                devices: devices,
                solver: solver,
                observer: nil,
                cancellation: cancellation
            )
            waveform = WaveformData.from(transferFunctionResult: result, title: "Transfer Function")
            label = "tf"
        case .sensitivity(let spec):
            guard spec.acSpec == nil else {
                throw EngineError.unsupportedAnalysis(".sens ac")
            }
            let outputNode = try outputNode(from: spec.output, in: plan, label: ".sens output")
            let result = try await SensitivityAnalysis(
                outputNode: outputNode,
                dcConfig: options.convergence
            ).run(
                plan: plan,
                devices: devices,
                solver: solver,
                observer: nil,
                cancellation: cancellation
            )
            waveform = WaveformData.from(sensitivityResult: result, title: "Sensitivity")
            label = "sens"
        case .poleZero(let spec):
            guard spec.transferType == .voltage else {
                throw EngineError.unsupportedAnalysis(".pz current transfer type")
            }
            try requireGroundReference(spec.outputReference, label: ".pz output reference node")
            let outputNode = try node(named: spec.outputNode, in: plan)
            let inputSourceName = try inputVoltageSourceName(for: spec, in: plan)
            let result = try await PoleZeroAnalysis(
                outputNode: outputNode,
                inputSourceName: inputSourceName,
                dcConfig: options.convergence
            ).run(
                plan: plan,
                devices: devices,
                solver: solver,
                observer: nil,
                cancellation: cancellation
            )
            waveform = WaveformData.from(poleZeroResult: result, title: "Pole-Zero")
            label = "pz"
        case .fourier(let spec, let transientSpec):
            let fundamentalFrequency = try requiredNumeric(spec.frequency, label: ".four frequency")
            guard fundamentalFrequency > 0 else {
                throw EngineError.unsupportedAnalysis(".four requires a positive fundamental frequency")
            }
            let outputNodes = try spec.outputs.map {
                try outputNode(from: $0, in: plan, label: ".four output")
            }
            guard !outputNodes.isEmpty else {
                throw EngineError.unsupportedAnalysis(".four requires at least one voltage output")
            }
            let result = try await FourierAnalysis(
                fundamentalFrequency: fundamentalFrequency,
                outputNodes: outputNodes,
                transientConfig: try transientConfig(from: transientSpec, options: options),
                convergenceConfig: options.convergence
            ).run(
                plan: plan,
                devices: devices,
                solver: solver,
                observer: nil,
                cancellation: cancellation
            )
            waveform = WaveformData.from(fourierResult: result, title: "Fourier")
            label = "four"
        case .monteCarlo(let spec):
            let parametric = try await runMonteCarlo(
                spec: spec,
                netlist: netlist,
                options: options,
                cancellation: cancellation
            )
            return SimulationAnalysisOutput(
                analysisLabel: "mc",
                measurements: [],
                waveformCSV: try csvExporter.csv(from: parametric)
            )
        }

        let measures = netlist.controls.compactMap { control -> MeasureSpec? in
            if case .measure(let measure) = control { return measure }
            return nil
        }
        let measurements = try SPICEMeasureEvaluator()
            .evaluate(measures: measures, waveform: waveform)
            .map { SimulationMeasurementValue(name: $0.name, value: $0.value, unit: $0.unit) }

        return SimulationAnalysisOutput(
            analysisLabel: label,
            measurements: measurements,
            waveformCSV: try csvExporter.csv(from: waveform)
        )
    }

    // MARK: - Internals

    private enum StageAnalysis {
        case op
        case dc(DCAnalysisSpec)
        case ac(ACAnalysisSpec)
        case transient(TransientAnalysisSpec)
        case noise(NoiseAnalysisSpec)
        case transferFunction(TransferFunctionSpec)
        case sensitivity(SensitivitySpec)
        case poleZero(PoleZeroSpec)
        case fourier(FourierSpec, TransientAnalysisSpec)
        case monteCarlo(MonteCarloSpec)
    }

    private struct SimulationAnalysisOutput: Sendable {
        let analysisLabel: String
        let measurements: [SimulationMeasurementValue]
        let waveformCSV: String
    }

    private static var architecture: String {
#if arch(arm64)
        "arm64"
#elseif arch(x86_64)
        "x86_64"
#else
        "unknown"
#endif
    }

    private func numeric(_ value: ParsedParameterValue?) -> Double? {
        switch value {
        case .numeric(let n):
            return n
        case .expression(let expression):
            if case .literal(let n) = expression { return n }
            return nil
        default:
            return nil
        }
    }

    private func requiredNumeric(_ value: ParsedParameterValue, label: String) throws -> Double {
        guard let numericValue = numeric(value), numericValue.isFinite else {
            throw EngineError.unsupportedAnalysis("\(label) must be a finite numeric value")
        }
        return numericValue
    }

    private func firstAnalysis(of netlist: ParsedNetlist) throws -> StageAnalysis? {
        if let monteCarloSpec = netlist.analyses.compactMap({ analysis -> MonteCarloSpec? in
            if case .monteCarlo(let spec) = analysis { return spec }
            return nil
        }).first {
            return .monteCarlo(monteCarloSpec)
        }

        if let fourierSpec = netlist.analyses.compactMap({ analysis -> FourierSpec? in
            if case .fourier(let spec) = analysis { return spec }
            return nil
        }).first {
            guard let transientSpec = netlist.analyses.compactMap({ analysis -> TransientAnalysisSpec? in
                if case .transient(let spec) = analysis { return spec }
                return nil
            }).first else {
                throw EngineError.unsupportedAnalysis(".four without .tran")
            }
            return .fourier(fourierSpec, transientSpec)
        }

        for analysis in netlist.analyses {
            switch analysis {
            case .op:
                return .op
            case .dc(let spec):
                guard spec.source2 == nil else {
                    throw EngineError.unsupportedAnalysis(".dc nested sweeps")
                }
                return .dc(spec)
            case .ac(let spec):
                return .ac(spec)
            case .transient(let spec):
                return .transient(spec)
            case .noise(let spec):
                return .noise(spec)
            case .transferFunction(let spec):
                return .transferFunction(spec)
            case .sensitivity(let spec):
                return .sensitivity(spec)
            case .poleZero(let spec):
                return .poleZero(spec)
            default:
                continue
            }
        }
        return nil
    }

    private func transientConfig(
        from spec: TransientAnalysisSpec,
        options: SPICEAnalysisOptions
    ) throws -> TransientConfig {
        guard let stop = numeric(spec.stopTime), stop > 0, stop.isFinite else {
            throw EngineError.unsupportedAnalysis(".tran without a positive stop time")
        }
        let step = numeric(spec.stepTime) ?? (stop / 50.0)
        guard step > 0, step.isFinite else {
            throw EngineError.unsupportedAnalysis(".tran without a positive time step")
        }
        return try options.transientConfig(
            stopTime: stop,
            stepTime: step,
            startTime: numeric(spec.startTime),
            maxStep: numeric(spec.maxStep),
            useInitialConditions: spec.useInitialConditions
        )
    }

    private func runMonteCarlo(
        spec: MonteCarloSpec,
        netlist: ParsedNetlist,
        options: SPICEAnalysisOptions,
        cancellation: CancellationToken
    ) async throws -> ParametricWaveformData {
        guard spec.iterations > 0 else {
            throw EngineError.unsupportedAnalysis(".mc requires at least one iteration")
        }
        var runs: [ParametricWaveformData.Run] = []
        runs.reserveCapacity(spec.iterations)
        let baseSeed = UInt64(spec.seed ?? 1)

        for index in 0..<spec.iterations {
            if cancellation.isCancelled {
                throw AnalysisError.cancelled
            }
            let seed = baseSeed &+ UInt64(index)
            let ir = try SPICEIO.lower(netlist, configuration: options.loweringConfiguration(randomSeed: seed))
            let plan = try StandardCompiler().compile(ir: ir)
            let devices = try bind(plan: plan)
            let waveform = try await runMonteCarloInnerAnalysis(
                spec.analysis,
                plan: plan,
                devices: devices,
                options: options,
                cancellation: cancellation
            )
            runs.append(ParametricWaveformData.Run(
                index: index,
                parameters: ["run": Double(index)],
                waveform: waveform
            ))
        }

        return ParametricWaveformData(
            runs: runs,
            analysisType: runs.first?.waveform.metadata.analysisType ?? .dc,
            title: "Monte Carlo",
            parameterNames: ["run"]
        )
    }

    private func runMonteCarloInnerAnalysis(
        _ analysis: ParsedAnalysisCommand,
        plan: ExecutionPlan,
        devices: [any BoundDevice],
        options: SPICEAnalysisOptions,
        cancellation: CancellationToken
    ) async throws -> WaveformData {
        let solver = SparseLUSolver()
        switch analysis {
        case .op:
            let result = try await DCAnalysis(config: options.convergence).run(
                plan: plan,
                devices: devices,
                solver: solver,
                observer: nil,
                cancellation: cancellation
            )
            return WaveformData.from(
                dcResult: result,
                topology: plan.topology.circuitTopology,
                title: "Operating Point"
            )
        case .transient(let spec):
            let result = try await TransientAnalysis(
                config: try transientConfig(from: spec, options: options),
                convergenceConfig: options.convergence
            ).run(
                plan: plan,
                devices: devices,
                solver: solver,
                observer: nil,
                cancellation: cancellation
            )
            return try WaveformData.from(
                transientResult: result,
                topology: plan.topology.circuitTopology,
                title: "Transient"
            )
        case .ac(let spec):
            let result = try await ACAnalysis(
                sweep: try frequencySweep(from: spec),
                dcConfig: options.convergence
            ).run(
                plan: plan,
                devices: devices,
                solver: solver,
                observer: nil,
                cancellation: cancellation
            )
            return WaveformData.from(
                acResult: result,
                topology: plan.topology.circuitTopology,
                title: "AC"
            )
        case .dc(let spec):
            guard spec.source2 == nil else {
                throw EngineError.unsupportedAnalysis(".mc nested .dc sweeps")
            }
            let start = try requiredNumeric(spec.startValue, label: ".mc .dc start value")
            let stop = try requiredNumeric(spec.stopValue, label: ".mc .dc stop value")
            let step = try requiredNumeric(spec.stepValue, label: ".mc .dc step value")
            guard step != 0, step.isFinite else {
                throw EngineError.unsupportedAnalysis(".mc .dc without a finite non-zero step value")
            }
            let values = strideInclusive(from: start, through: stop, by: step)
            guard !values.isEmpty else {
                throw EngineError.unsupportedAnalysis(".mc .dc sweep produced no points")
            }
            let sourceName = try validatedSweepSource(spec.source, in: plan, label: ".mc .dc")
            var results: [DCResult] = []
            results.reserveCapacity(values.count)
            for value in values {
                let devices = try bind(plan: plan, overrideSource: (sourceName, value))
                let result = try await DCAnalysis(config: options.convergence).run(
                    plan: plan,
                    devices: devices,
                    solver: solver,
                    observer: nil,
                    cancellation: cancellation
                )
                results.append(result)
            }
            let sweepResult = SweepResult(parameterName: spec.source, values: values, results: results)
            return WaveformData.from(
                sweepResult: sweepResult,
                topology: plan.topology.circuitTopology,
                title: "DC Sweep"
            )
        default:
            throw EngineError.unsupportedAnalysis(".mc inner \(analysis)")
        }
    }

    private func frequencySweep(from spec: NoiseAnalysisSpec) throws -> FrequencySweep {
        let start = try requiredNumeric(spec.startFrequency, label: ".noise start frequency")
        let stop = try requiredNumeric(spec.stopFrequency, label: ".noise stop frequency")
        guard start > 0, stop > 0, start.isFinite, stop.isFinite else {
            throw EngineError.unsupportedAnalysis(".noise requires positive finite start and stop frequencies")
        }
        guard spec.numberOfPoints > 0 else {
            throw EngineError.unsupportedAnalysis(".noise requires at least one point")
        }
        switch spec.scaleType {
        case .decade:
            return .decade(start: start, stop: stop, pointsPerDecade: spec.numberOfPoints)
        case .octave:
            return .octave(start: start, stop: stop, pointsPerOctave: spec.numberOfPoints)
        case .linear:
            return .linear(start: start, stop: stop, points: spec.numberOfPoints)
        }
    }

    private func frequencySweep(from spec: ACAnalysisSpec) throws -> FrequencySweep {
        let start = try requiredNumeric(spec.startFrequency, label: ".ac start frequency")
        let stop = try requiredNumeric(spec.stopFrequency, label: ".ac stop frequency")
        guard start > 0, stop > 0, start.isFinite, stop.isFinite else {
            throw EngineError.unsupportedAnalysis(".ac requires positive finite start and stop frequencies")
        }
        guard spec.numberOfPoints > 0 else {
            throw EngineError.unsupportedAnalysis(".ac requires at least one point")
        }
        switch spec.scaleType {
        case .decade:
            return .decade(start: start, stop: stop, pointsPerDecade: spec.numberOfPoints)
        case .octave:
            return .octave(start: start, stop: stop, pointsPerOctave: spec.numberOfPoints)
        case .linear:
            return .linear(start: start, stop: stop, points: spec.numberOfPoints)
        }
    }

    private func outputNode(from variable: String, in plan: ExecutionPlan, label: String) throws -> Node {
        let trimmed = variable.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("V("), trimmed.hasSuffix(")") else {
            throw EngineError.unsupportedAnalysis("\(label) must be a node voltage")
        }
        let inner = String(trimmed.dropFirst(2).dropLast())
        let parts = inner.split(separator: ",").map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let nodeName = parts.first, !nodeName.isEmpty else {
            throw EngineError.unsupportedAnalysis("\(label) is missing a node")
        }
        if parts.count > 1 {
            try requireGroundReference(parts[1], label: "\(label) reference node")
        }
        return try node(named: nodeName, in: plan)
    }

    private func node(named name: String, in plan: ExecutionPlan) throws -> Node {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if isGroundName(normalized) {
            return .ground
        }
        if let node = plan.ir.nodeNames.first(where: {
            $0.value.caseInsensitiveCompare(normalized) == .orderedSame
        })?.key {
            return node
        }
        if let id = Int(normalized) {
            let node = Node(id: id)
            if plan.ir.nodes.contains(node) {
                return node
            }
        }
        throw EngineError.unsupportedAnalysis("unknown node '\(name)'")
    }

    private func requireGroundReference(_ reference: String?, label: String) throws {
        guard let reference else {
            return
        }
        try requireGroundReference(reference, label: label)
    }

    private func requireGroundReference(_ reference: String, label: String) throws {
        guard isGroundName(reference) else {
            throw EngineError.unsupportedAnalysis("\(label) must be ground")
        }
    }

    private func isGroundName(_ name: String) -> Bool {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "0" || normalized == "gnd" || normalized == "ground"
    }

    private func inputVoltageSourceName(for spec: PoleZeroSpec, in plan: ExecutionPlan) throws -> String {
        let inputNode = try node(named: spec.inputNode, in: plan)
        let inputReference = try node(named: spec.inputReference, in: plan)
        for instance in plan.ir.instances where instance.typeName == "vsource" {
            guard instance.nodes.count >= 2 else {
                continue
            }
            if instance.nodes[0] == inputNode && instance.nodes[1] == inputReference {
                return instance.name
            }
        }
        throw EngineError.unsupportedAnalysis(".pz input node pair does not resolve to a voltage source")
    }

    private func bind(
        plan: ExecutionPlan,
        overrideSource: (String, Double)? = nil
    ) throws -> [any BoundDevice] {
        let registry = DeviceRegistry.standard()
        let structure = plan.matrixStructure
        var context = BindingContext(
            variableMap: plan.topology.variableMap,
            matrixDimension: plan.topology.dimension,
            branchNames: plan.ir.branchNames,
            stampIndexResolver: { row, col in structure.index(row: row, col: col) }
        )
        var devices: [any BoundDevice] = []
        devices.reserveCapacity(plan.ir.instances.count)
        for instance in plan.ir.instances {
            let resolvedInstance: Instance
            if let overrideSource,
               instance.name.caseInsensitiveCompare(overrideSource.0) == .orderedSame {
                var parameters = instance.parameters
                switch instance.typeName {
                case "isource":
                    parameters["i"] = .real(overrideSource.1)
                case "vsource":
                    parameters["v"] = .real(overrideSource.1)
                default:
                    throw EngineError.unsupportedAnalysis(
                        "source \(overrideSource.0) resolved to unsupported device type \(instance.typeName); sweep source must be an independent voltage or current source"
                    )
                }
                resolvedInstance = Instance(
                    name: instance.name,
                    typeName: instance.typeName,
                    nodes: instance.nodes,
                    parameters: parameters,
                    opticalNodes: instance.opticalNodes
                )
            } else {
                resolvedInstance = instance
            }
            guard let descriptor = registry.descriptor(for: resolvedInstance.typeName) else {
                throw EngineError.missingDeviceDescriptor(resolvedInstance.typeName)
            }
            devices.append(try descriptor.bind(instance: resolvedInstance, context: &context))
        }
        return devices
    }

    private func validatedSweepSource(
        _ source: String,
        in plan: ExecutionPlan,
        label: String
    ) throws -> String {
        let matches = plan.ir.instances.filter {
            $0.name.caseInsensitiveCompare(source) == .orderedSame
        }
        let availableSources = plan.ir.instances
            .filter { $0.typeName == "vsource" || $0.typeName == "isource" }
            .map(\.name)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        let availableSourceList = availableSources.isEmpty ? "none" : availableSources.joined(separator: ", ")
        guard let match = matches.first else {
            throw EngineError.unsupportedAnalysis(
                "\(label) source \(source) did not match any independent source; available sources: \(availableSourceList)"
            )
        }
        guard matches.count == 1 else {
            throw EngineError.unsupportedAnalysis(
                "\(label) source \(source) matched multiple devices; available sources: \(availableSourceList)"
            )
        }
        guard match.typeName == "vsource" || match.typeName == "isource" else {
            throw EngineError.unsupportedAnalysis(
                "\(label) source \(source) resolved to unsupported device type \(match.typeName); sweep source must be an independent voltage or current source"
            )
        }
        return match.name
    }

    private func strideInclusive(from start: Double, through stop: Double, by step: Double) -> [Double] {
        var values: [Double] = []
        var current = start
        if step > 0 {
            while current <= stop + step * 0.5 {
                values.append(current)
                current += step
            }
        } else {
            while current >= stop + step * 0.5 {
                values.append(current)
                current += step
            }
        }
        return values
    }

}
