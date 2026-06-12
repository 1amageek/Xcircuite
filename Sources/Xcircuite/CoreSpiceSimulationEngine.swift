import Foundation
import CoreSpice
import CoreSpiceIO
import CoreSpiceWaveform

/// In-process CoreSpice driver for the simulation flow stage: parse →
/// lower → compile → bind → run the netlist's own first analysis
/// directive (`.op` or `.tran`; nothing when absent defaults to `.op`)
/// → evaluate the netlist's `.measure` statements.
///
/// AC and DC-sweep directives are not supported by the stage yet and
/// FAIL with a typed error — a stage that silently ran a different
/// analysis than the netlist asked for would be lying about its gate.
public struct CoreSpiceSimulationEngine: SimulationExecuting {

    public enum EngineError: Error, LocalizedError, Equatable {
        case unsupportedAnalysis(String)
        case missingDeviceDescriptor(String)

        public var errorDescription: String? {
            switch self {
            case .unsupportedAnalysis(let kind):
                return "The simulation stage supports .op and .tran; the netlist asks for \(kind)."
            case .missingDeviceDescriptor(let type):
                return "No device descriptor is registered for '\(type)'."
            }
        }
    }

    public init() {}

    public func run(netlistSource: String, fileName: String?) async throws -> SimulationStageOutcome {
        let netlist = try await SPICEIO.parse(netlistSource, fileName: fileName).get()
        let options = try SPICEAnalysisOptions.resolve(from: netlist)
        let ir = try SPICEIO.lower(netlist, configuration: options.loweringConfiguration())
        let plan = try StandardCompiler().compile(ir: ir)
        let devices = try bind(plan: plan)

        let solver = SparseLUSolver()
        let cancellation = CancellationToken()
        let waveform: WaveformData
        let label: String

        switch try firstAnalysis(of: netlist) {
        case .none, .op:
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
            guard let stop = numeric(spec.stopTime), stop > 0, stop.isFinite else {
                throw EngineError.unsupportedAnalysis(".tran without a positive stop time")
            }
            let step = numeric(spec.stepTime) ?? (stop / 50.0)
            guard step > 0, step.isFinite else {
                throw EngineError.unsupportedAnalysis(".tran without a positive time step")
            }
            let config = try options.transientConfig(
                stopTime: stop,
                stepTime: step,
                startTime: numeric(spec.startTime),
                maxStep: numeric(spec.maxStep),
                useInitialConditions: spec.useInitialConditions
            )
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
            waveform = WaveformData.from(
                transientResult: result,
                topology: plan.topology.circuitTopology,
                title: "Transient"
            )
            label = "tran"
        case .some(let other):
            throw EngineError.unsupportedAnalysis(String(describing: other))
        }

        let measures = netlist.controls.compactMap { control -> MeasureSpec? in
            if case .measure(let measure) = control { return measure }
            return nil
        }
        let measurements = try SPICEMeasureEvaluator()
            .evaluate(measures: measures, waveform: waveform)
            .map { SimulationMeasurementValue(name: $0.name, value: $0.value, unit: $0.unit) }

        return SimulationStageOutcome(
            analysisLabel: label,
            measurements: measurements,
            waveformCSV: csv(from: waveform)
        )
    }

    // MARK: - Internals

    private enum StageAnalysis {
        case op
        case transient(TransientAnalysisSpec)
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

    private func firstAnalysis(of netlist: ParsedNetlist) throws -> StageAnalysis? {
        for analysis in netlist.analyses {
            switch analysis {
            case .op:
                return .op
            case .transient(let spec):
                return .transient(spec)
            case .ac:
                throw EngineError.unsupportedAnalysis(".ac")
            case .dc:
                throw EngineError.unsupportedAnalysis(".dc")
            default:
                continue
            }
        }
        return nil
    }

    private func bind(plan: ExecutionPlan) throws -> [any BoundDevice] {
        let registry = DeviceRegistry.standard()
        let structure = plan.matrixStructure
        var context = BindingContext(
            variableMap: plan.topology.variableMap,
            matrixDimension: plan.topology.dimension,
            stampIndexResolver: { row, col in structure.index(row: row, col: col) }
        )
        var devices: [any BoundDevice] = []
        devices.reserveCapacity(plan.ir.instances.count)
        for instance in plan.ir.instances {
            guard let descriptor = registry.descriptor(for: instance.typeName) else {
                throw EngineError.missingDeviceDescriptor(instance.typeName)
            }
            devices.append(try descriptor.bind(instance: instance, context: &context))
        }
        return devices
    }

    private func csv(from waveform: WaveformData) -> String {
        var lines: [String] = []
        let header = ([waveform.sweepVariable.name] + waveform.variables.map(\.name))
            .joined(separator: ",")
        lines.append(header)
        let columns = waveform.allRealData ?? []
        for index in waveform.sweepValues.indices {
            var row = [String(waveform.sweepValues[index])]
            for column in columns where column.indices.contains(index) {
                row.append(String(column[index]))
            }
            lines.append(row.joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
