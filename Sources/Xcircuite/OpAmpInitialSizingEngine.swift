import Foundation

public struct OpAmpInitialSizingEngine: Sendable {
    public init() {}

    public func size(
        spec: OpAmpSpec,
        topologyKind: OpAmpTopologyKind? = nil,
        technology: OpAmpSizingTechnologyModel = .genericCMOS180()
    ) throws -> OpAmpSizingResult {
        try validate(spec: spec, technology: technology)
        let topology = try selectedTopology(spec: spec, topologyKind: topologyKind)
        switch topology.kind {
        case .twoStageMiller:
            return try sizeTwoStageMiller(spec: spec, topology: topology, technology: technology)
        case .foldedCascode:
            return try sizeFoldedCascode(spec: spec, topology: topology, technology: technology)
        case .telescopicCascode:
            return try sizeTelescopicCascode(spec: spec, topology: topology, technology: technology)
        }
    }

    private func selectedTopology(
        spec: OpAmpSpec,
        topologyKind: OpAmpTopologyKind?
    ) throws -> OpAmpTopologyCandidate {
        let library = OpAmpTopologyLibrary()
        if let topologyKind {
            guard let candidate = library.candidate(kind: topologyKind, for: spec) else {
                throw OpAmpSizingError.unsupportedTopology(topologyKind.rawValue)
            }
            return candidate
        }
        guard let candidate = library.candidates(for: spec).first else {
            throw OpAmpSizingError.invalidSpecification("No allowed topology is available.")
        }
        return candidate
    }

    private func sizeTwoStageMiller(
        spec: OpAmpSpec,
        topology: OpAmpTopologyCandidate,
        technology: OpAmpSizingTechnologyModel
    ) throws -> OpAmpSizingResult {
        let loadCap = spec.operatingPoint.loadCapacitance
        let targetUGF = requirementValue(spec, .unityGainFrequencyHz, defaultValue: 10.0e6)
        let targetSR = requirementValue(spec, .positiveSlewRateVPerS, defaultValue: 5.0e6)
        let targetGainDB = requirementValue(spec, .dcGainDB, defaultValue: 60)
        let compensationCap = max(loadCap * 0.25, 200e-15)
        let inputGM = max(2.0 * .pi * targetUGF * compensationCap, 1.0e-6)
        let inputBranchCurrent = inputGM / technology.defaultInputGMOverID
        let slewCurrent = targetSR * compensationCap
        let tailCurrent = max(2.0 * inputBranchCurrent, slewCurrent)
        let outputGM = max(2.2 * 2.0 * .pi * targetUGF * loadCap, inputGM * 2.0)
        let outputCurrent = max(outputGM / technology.defaultOutputGMOverID, targetSR * loadCap)
        let inputLength = gainLength(
            targetGainDB: targetGainDB,
            baseLength: technology.minimumLength * 2.0,
            current: inputBranchCurrent,
            lambda: technology.nmosLambda,
            technology: technology
        )
        let outputLength = gainLength(
            targetGainDB: targetGainDB,
            baseLength: technology.minimumLength * 2.5,
            current: outputCurrent,
            lambda: technology.pmosLambda,
            technology: technology
        )

        let inputPair = mosPair(
            names: ("M1", "M2"),
            role: "inputPair",
            kind: .nmos,
            modelName: technology.nmosModelName,
            current: inputBranchCurrent,
            gmOverID: technology.defaultInputGMOverID,
            length: inputLength,
            technology: technology
        )
        let pmosLoad = mosPair(
            names: ("M3", "M4"),
            role: "activeLoadMirror",
            kind: .pmos,
            modelName: technology.pmosModelName,
            current: inputBranchCurrent,
            gmOverID: technology.defaultBiasGMOverID,
            length: inputLength,
            technology: technology
        )
        let tail = mos(
            name: "M5",
            role: "tailCurrent",
            kind: .nmos,
            modelName: technology.nmosModelName,
            current: tailCurrent,
            gmOverID: technology.defaultBiasGMOverID,
            length: inputLength,
            technology: technology
        )
        let secondDriver = mos(
            name: "M6",
            role: "secondStageDriver",
            kind: .nmos,
            modelName: technology.nmosModelName,
            current: outputCurrent,
            gmOverID: technology.defaultOutputGMOverID,
            length: outputLength,
            technology: technology
        )
        let secondLoad = mos(
            name: "M7",
            role: "secondStageLoad",
            kind: .pmos,
            modelName: technology.pmosModelName,
            current: outputCurrent,
            gmOverID: technology.defaultBiasGMOverID,
            length: outputLength,
            technology: technology
        )
        let compensation = OpAmpSizedDevice(
            instanceName: "Cc",
            role: "compensation",
            deviceKind: .capacitor,
            value: compensationCap,
            unit: "F"
        )
        let devices = inputPair + pmosLoad + [tail, secondDriver, secondLoad, compensation]
        let metrics = estimatedTwoStageMetrics(
            spec: spec,
            technology: technology,
            inputGM: inputGM,
            inputCurrent: inputBranchCurrent,
            outputGM: outputGM,
            outputCurrent: outputCurrent,
            compensationCap: compensationCap,
            inputLength: inputLength,
            outputLength: outputLength
        )
        let diagnostics = diagnosticsFor(spec: spec, metrics: metrics, technology: technology, totalCurrent: tailCurrent + outputCurrent)
        let layout = OpAmpLayoutConstraintPlanner().makePlan(topology: topology, devices: devices)
        var result = OpAmpSizingResult(
            resultID: "\(spec.specID)-two-stage-miller-sizing",
            specID: spec.specID,
            topology: topology,
            technology: technology,
            status: diagnostics.contains { $0.severity == .error } ? .needsReview : .sized,
            devices: devices,
            estimatedMetrics: metrics,
            layoutConstraintPlan: layout,
            netlist: OpAmpNetlistGenerator().makeNetlist(spec: spec, sizing: devices, topology: topology, technology: technology),
            diagnostics: diagnostics,
            metadata: [
                "compensationCapacitanceF": "\(compensationCap)",
                "tailCurrentA": "\(tailCurrent)",
                "outputStageCurrentA": "\(outputCurrent)",
            ]
        )
        result.simulationDeckSet = OpAmpSimulationDeckGenerator().makeDeckSet(spec: spec, sizingResult: result)
        return result
    }

    private func sizeFoldedCascode(
        spec: OpAmpSpec,
        topology: OpAmpTopologyCandidate,
        technology: OpAmpSizingTechnologyModel
    ) throws -> OpAmpSizingResult {
        let loadCap = spec.operatingPoint.loadCapacitance
        let targetUGF = requirementValue(spec, .unityGainFrequencyHz, defaultValue: 10.0e6)
        let targetSR = requirementValue(spec, .positiveSlewRateVPerS, defaultValue: 5.0e6)
        let targetGainDB = requirementValue(spec, .dcGainDB, defaultValue: 65)
        let inputGM = max(2.0 * .pi * targetUGF * loadCap, 1.0e-6)
        let branchCurrent = max(inputGM / technology.defaultInputGMOverID, targetSR * loadCap)
        let length = gainLength(
            targetGainDB: targetGainDB + 6,
            baseLength: technology.minimumLength * 3.0,
            current: branchCurrent,
            lambda: technology.nmosLambda,
            technology: technology
        )
        let devices = mosPair(
            names: ("M1", "M2"),
            role: "inputPair",
            kind: .nmos,
            modelName: technology.nmosModelName,
            current: branchCurrent,
            gmOverID: technology.defaultInputGMOverID,
            length: length,
            technology: technology
        ) + mosPair(
            names: ("M3", "M4"),
            role: "foldingDevices",
            kind: .pmos,
            modelName: technology.pmosModelName,
            current: branchCurrent,
            gmOverID: technology.defaultBiasGMOverID,
            length: length,
            technology: technology
        ) + mosArray(
            prefix: "Mcas",
            role: "cascodeDevices",
            kind: .nmos,
            modelName: technology.nmosModelName,
            count: 4,
            current: branchCurrent,
            gmOverID: technology.defaultBiasGMOverID,
            length: length,
            technology: technology
        )
        let metrics = singleStageCascodeMetrics(
            spec: spec,
            topology: .foldedCascode,
            branchCurrent: branchCurrent,
            gm: inputGM,
            loadCap: loadCap,
            length: length,
            technology: technology
        )
        let diagnostics = diagnosticsFor(spec: spec, metrics: metrics, technology: technology, totalCurrent: branchCurrent * 4)
        let layout = OpAmpLayoutConstraintPlanner().makePlan(topology: topology, devices: devices)
        var result = OpAmpSizingResult(
            resultID: "\(spec.specID)-folded-cascode-sizing",
            specID: spec.specID,
            topology: topology,
            technology: technology,
            status: diagnostics.contains { $0.severity == .error } ? .needsReview : .sized,
            devices: devices,
            estimatedMetrics: metrics,
            layoutConstraintPlan: layout,
            netlist: OpAmpNetlistGenerator().makeNetlist(spec: spec, sizing: devices, topology: topology, technology: technology),
            diagnostics: diagnostics
        )
        result.simulationDeckSet = OpAmpSimulationDeckGenerator().makeDeckSet(spec: spec, sizingResult: result)
        return result
    }

    private func sizeTelescopicCascode(
        spec: OpAmpSpec,
        topology: OpAmpTopologyCandidate,
        technology: OpAmpSizingTechnologyModel
    ) throws -> OpAmpSizingResult {
        let loadCap = spec.operatingPoint.loadCapacitance
        let targetUGF = requirementValue(spec, .unityGainFrequencyHz, defaultValue: 10.0e6)
        let targetSR = requirementValue(spec, .positiveSlewRateVPerS, defaultValue: 5.0e6)
        let targetGainDB = requirementValue(spec, .dcGainDB, defaultValue: 70)
        let inputGM = max(2.0 * .pi * targetUGF * loadCap, 1.0e-6)
        let branchCurrent = max(inputGM / technology.defaultInputGMOverID, targetSR * loadCap)
        let length = gainLength(
            targetGainDB: targetGainDB + 10,
            baseLength: technology.minimumLength * 4.0,
            current: branchCurrent,
            lambda: technology.nmosLambda,
            technology: technology
        )
        let devices = mosPair(
            names: ("M1", "M2"),
            role: "inputPair",
            kind: .nmos,
            modelName: technology.nmosModelName,
            current: branchCurrent,
            gmOverID: technology.defaultInputGMOverID,
            length: length,
            technology: technology
        ) + mosArray(
            prefix: "MNcas",
            role: "nmosCascodes",
            kind: .nmos,
            modelName: technology.nmosModelName,
            count: 2,
            current: branchCurrent,
            gmOverID: technology.defaultBiasGMOverID,
            length: length,
            technology: technology
        ) + mosArray(
            prefix: "MPcas",
            role: "pmosCascodes",
            kind: .pmos,
            modelName: technology.pmosModelName,
            count: 2,
            current: branchCurrent,
            gmOverID: technology.defaultBiasGMOverID,
            length: length,
            technology: technology
        ) + [
            mos(
                name: "Mtail",
                role: "tailCurrent",
                kind: .nmos,
                modelName: technology.nmosModelName,
                current: branchCurrent * 2,
                gmOverID: technology.defaultBiasGMOverID,
                length: length,
                technology: technology
            ),
        ]
        let metrics = singleStageCascodeMetrics(
            spec: spec,
            topology: .telescopicCascode,
            branchCurrent: branchCurrent,
            gm: inputGM,
            loadCap: loadCap,
            length: length,
            technology: technology
        )
        let diagnostics = diagnosticsFor(spec: spec, metrics: metrics, technology: technology, totalCurrent: branchCurrent * 2)
        let layout = OpAmpLayoutConstraintPlanner().makePlan(topology: topology, devices: devices)
        var result = OpAmpSizingResult(
            resultID: "\(spec.specID)-telescopic-cascode-sizing",
            specID: spec.specID,
            topology: topology,
            technology: technology,
            status: diagnostics.contains { $0.severity == .error } ? .needsReview : .sized,
            devices: devices,
            estimatedMetrics: metrics,
            layoutConstraintPlan: layout,
            netlist: OpAmpNetlistGenerator().makeNetlist(spec: spec, sizing: devices, topology: topology, technology: technology),
            diagnostics: diagnostics
        )
        result.simulationDeckSet = OpAmpSimulationDeckGenerator().makeDeckSet(spec: spec, sizingResult: result)
        return result
    }

    private func estimatedTwoStageMetrics(
        spec: OpAmpSpec,
        technology: OpAmpSizingTechnologyModel,
        inputGM: Double,
        inputCurrent: Double,
        outputGM: Double,
        outputCurrent: Double,
        compensationCap: Double,
        inputLength: Double,
        outputLength: Double
    ) -> [OpAmpEstimatedMetric] {
        let inputRO = outputResistance(current: inputCurrent, lambda: technology.nmosLambda, length: inputLength, technology: technology)
        let loadRO = outputResistance(current: inputCurrent, lambda: technology.pmosLambda, length: inputLength, technology: technology)
        let outputRO = outputResistance(current: outputCurrent, lambda: technology.pmosLambda, length: outputLength, technology: technology)
        let driverRO = outputResistance(current: outputCurrent, lambda: technology.nmosLambda, length: outputLength, technology: technology)
        let firstGain = inputGM * parallel(inputRO, loadRO)
        let secondGain = outputGM * parallel(outputRO, driverRO)
        let gainDB = 20.0 * log10(max(firstGain * secondGain, 1.0))
        let ugf = inputGM / (2.0 * .pi * compensationCap)
        let nonDominantPole = outputGM / (2.0 * .pi * max(spec.operatingPoint.loadCapacitance, 1.0e-15))
        let phaseMargin = min(85.0, max(35.0, 90.0 - atan(ugf / max(nonDominantPole, 1.0)) * 180.0 / .pi))
        let srPositive = outputCurrent / max(spec.operatingPoint.loadCapacitance, 1.0e-15)
        let srNegative = (2.0 * inputCurrent) / max(compensationCap, 1.0e-15)
        let totalCurrent = outputCurrent + 2.0 * inputCurrent
        return [
            .init(metricID: .dcGainDB, value: gainDB, unit: "dB", method: "gmro product estimate"),
            .init(metricID: .unityGainFrequencyHz, value: ugf, unit: "Hz", method: "gm1 / Cc"),
            .init(metricID: .phaseMarginDegrees, value: phaseMargin, unit: "deg", method: "two-pole separation estimate"),
            .init(metricID: .positiveSlewRateVPerS, value: srPositive, unit: "V/s", method: "output current / load capacitance"),
            .init(metricID: .negativeSlewRateVPerS, value: srNegative, unit: "V/s", method: "tail current / compensation capacitance"),
            .init(metricID: .staticPowerW, value: totalCurrent * supply(spec), unit: "W", method: "VDD times estimated bias current"),
            .init(metricID: .quiescentCurrentA, value: totalCurrent, unit: "A", method: "estimated bias current sum"),
            .init(metricID: .cmrrDB, value: gainDB + 10, unit: "dB", method: "symmetry-limited proxy"),
            .init(metricID: .psrrPositiveDB, value: max(gainDB - 6, 0), unit: "dB", method: "active-load proxy"),
            .init(metricID: .psrrNegativeDB, value: max(gainDB - 10, 0), unit: "dB", method: "tail-source proxy"),
            .init(metricID: .inputReferredNoiseVPerRootHz, value: sqrt(8.0e-21 / max(inputGM, 1.0e-12)), unit: "V/sqrt(Hz)", method: "thermal-noise gm proxy"),
            .init(metricID: .inputOffsetVoltage, value: 1.0e-3 * sqrt(technology.minimumLength / max(inputLength, technology.minimumLength)), unit: "V", method: "area proxy"),
        ]
    }

    private func singleStageCascodeMetrics(
        spec: OpAmpSpec,
        topology: OpAmpTopologyKind,
        branchCurrent: Double,
        gm: Double,
        loadCap: Double,
        length: Double,
        technology: OpAmpSizingTechnologyModel
    ) -> [OpAmpEstimatedMetric] {
        let roN = outputResistance(current: branchCurrent, lambda: technology.nmosLambda, length: length, technology: technology)
        let roP = outputResistance(current: branchCurrent, lambda: technology.pmosLambda, length: length, technology: technology)
        let cascodeBoost = topology == .telescopicCascode ? 12.0 : 8.0
        let gainDB = 20.0 * log10(max(gm * parallel(roN, roP), 1.0)) + cascodeBoost
        let ugf = gm / (2.0 * .pi * max(loadCap, 1.0e-15))
        let totalCurrent = branchCurrent * (topology == .telescopicCascode ? 2.0 : 4.0)
        let swingFactor = topology == .telescopicCascode ? 0.55 : 0.65
        return [
            .init(metricID: .dcGainDB, value: gainDB, unit: "dB", method: "cascode gmro estimate"),
            .init(metricID: .unityGainFrequencyHz, value: ugf, unit: "Hz", method: "gm / load capacitance"),
            .init(metricID: .phaseMarginDegrees, value: topology == .telescopicCascode ? 72 : 68, unit: "deg", method: "single-stage proxy"),
            .init(metricID: .positiveSlewRateVPerS, value: branchCurrent / max(loadCap, 1.0e-15), unit: "V/s", method: "branch current / load capacitance"),
            .init(metricID: .negativeSlewRateVPerS, value: branchCurrent / max(loadCap, 1.0e-15), unit: "V/s", method: "branch current / load capacitance"),
            .init(metricID: .staticPowerW, value: totalCurrent * supply(spec), unit: "W", method: "VDD times estimated bias current"),
            .init(metricID: .quiescentCurrentA, value: totalCurrent, unit: "A", method: "estimated branch current sum"),
            .init(metricID: .outputSwingHighV, value: supply(spec) * swingFactor, unit: "V", method: "stack headroom proxy"),
            .init(metricID: .outputSwingLowV, value: supply(spec) * (1.0 - swingFactor), unit: "V", method: "stack headroom proxy"),
            .init(metricID: .cmrrDB, value: gainDB + 12, unit: "dB", method: "differential symmetry proxy"),
            .init(metricID: .psrrPositiveDB, value: gainDB - 4, unit: "dB", method: "cascode supply rejection proxy"),
            .init(metricID: .psrrNegativeDB, value: gainDB - 4, unit: "dB", method: "cascode supply rejection proxy"),
        ]
    }

    private func diagnosticsFor(
        spec: OpAmpSpec,
        metrics: [OpAmpEstimatedMetric],
        technology: OpAmpSizingTechnologyModel,
        totalCurrent: Double
    ) -> [OpAmpDesignDiagnostic] {
        var diagnostics: [OpAmpDesignDiagnostic] = []
        for requirement in spec.requirements {
            guard let metric = metrics.first(where: { $0.metricID == requirement.metricID }) else {
                diagnostics.append(.init(
                    severity: .warning,
                    code: "opamp.metric.unestimated",
                    message: "Metric \(requirement.metricID.rawValue) is not estimated by the initial sizing engine.",
                    relatedMetricIDs: [requirement.metricID],
                    suggestedActions: ["run-simulation", "attach-measured-artifact"]
                ))
                continue
            }
            if !passes(metric.value, requirement: requirement) {
                diagnostics.append(.init(
                    severity: diagnosticSeverity(requirement.severity),
                    code: "opamp.metric.estimate-misses-target",
                    message: "Estimated \(requirement.metricID.rawValue) \(metric.value) \(metric.unit) does not satisfy \(requirement.relation.rawValue) \(requirement.value) \(requirement.unit).",
                    relatedMetricIDs: [requirement.metricID],
                    suggestedActions: suggestedActions(for: requirement.metricID)
                ))
            }
        }
        if totalCurrent > technology.maximumDeviceCurrent {
            diagnostics.append(.init(
                severity: .warning,
                code: "opamp.current.exceeds-technology-guidance",
                message: "Estimated current \(totalCurrent) A exceeds technology guidance \(technology.maximumDeviceCurrent) A.",
                relatedMetricIDs: [.quiescentCurrentA, .staticPowerW],
                suggestedActions: ["relax-bandwidth-or-slew-rate", "choose-higher-current-technology-profile"]
            ))
        }
        return diagnostics
    }

    private func passes(_ value: Double, requirement: OpAmpSpec.Requirement) -> Bool {
        let tolerance = requirement.tolerance ?? 0
        switch requirement.relation {
        case .atLeast:
            return value + tolerance >= requirement.value
        case .atMost:
            return value - tolerance <= requirement.value
        case .between:
            guard let upper = requirement.upperValue else {
                return false
            }
            return value + tolerance >= requirement.value && value - tolerance <= upper
        case .equal:
            return abs(value - requirement.value) <= tolerance
        }
    }

    private func diagnosticSeverity(_ severity: OpAmpSpec.Requirement.Severity) -> OpAmpDesignDiagnostic.Severity {
        switch severity {
        case .info:
            .info
        case .warning:
            .warning
        case .error, .blocker:
            .error
        }
    }

    private func suggestedActions(for metricID: OpAmpMetricID) -> [String] {
        switch metricID {
        case .dcGainDB:
            ["increase-channel-length", "choose-cascode-topology", "increase-output-resistance"]
        case .unityGainFrequencyHz:
            ["increase-input-gm", "reduce-compensation-capacitance", "reduce-load-capacitance"]
        case .phaseMarginDegrees:
            ["increase-compensation-capacitance", "increase-second-stage-gm", "reduce-nondominant-pole-loading"]
        case .positiveSlewRateVPerS, .negativeSlewRateVPerS:
            ["increase-bias-current", "reduce-compensation-capacitance", "reduce-load-capacitance"]
        case .staticPowerW, .quiescentCurrentA:
            ["reduce-bias-current", "relax-bandwidth-or-slew-rate", "choose-lower-power-topology"]
        default:
            ["run-simulation", "inspect-topology-and-sizing"]
        }
    }

    private func mosPair(
        names: (String, String),
        role: String,
        kind: OpAmpSizedDevice.DeviceKind,
        modelName: String,
        current: Double,
        gmOverID: Double,
        length: Double,
        technology: OpAmpSizingTechnologyModel
    ) -> [OpAmpSizedDevice] {
        [
            mos(name: names.0, role: role, kind: kind, modelName: modelName, current: current, gmOverID: gmOverID, length: length, technology: technology),
            mos(name: names.1, role: role, kind: kind, modelName: modelName, current: current, gmOverID: gmOverID, length: length, technology: technology),
        ]
    }

    private func mosArray(
        prefix: String,
        role: String,
        kind: OpAmpSizedDevice.DeviceKind,
        modelName: String,
        count: Int,
        current: Double,
        gmOverID: Double,
        length: Double,
        technology: OpAmpSizingTechnologyModel
    ) -> [OpAmpSizedDevice] {
        (1...count).map { index in
            mos(
                name: "\(prefix)\(index)",
                role: role,
                kind: kind,
                modelName: modelName,
                current: current,
                gmOverID: gmOverID,
                length: length,
                technology: technology
            )
        }
    }

    private func mos(
        name: String,
        role: String,
        kind: OpAmpSizedDevice.DeviceKind,
        modelName: String,
        current: Double,
        gmOverID: Double,
        length: Double,
        technology: OpAmpSizingTechnologyModel
    ) -> OpAmpSizedDevice {
        let vov = max(2.0 / gmOverID, 0.04)
        let muCox = kind == .pmos ? technology.pmosMobilityCox : technology.nmosMobilityCox
        let rawWidth = 2.0 * current * length / max(muCox * vov * vov, 1.0e-30)
        let width = min(max(rawWidth, technology.minimumWidth), technology.maximumWidth)
        let fingers = max(1, Int(ceil(width / max(20.0e-6, technology.minimumWidth))))
        let lambda = kind == .pmos ? technology.pmosLambda : technology.nmosLambda
        return OpAmpSizedDevice(
            instanceName: name,
            role: role,
            deviceKind: kind,
            modelName: modelName,
            width: width,
            length: length,
            fingers: fingers,
            drainCurrent: current,
            transconductance: gmOverID * current,
            outputResistance: outputResistance(current: current, lambda: lambda, length: length, technology: technology),
            overdriveVoltage: vov
        )
    }

    private func gainLength(
        targetGainDB: Double,
        baseLength: Double,
        current: Double,
        lambda: Double,
        technology: OpAmpSizingTechnologyModel
    ) -> Double {
        let targetLinear = pow(10.0, max(targetGainDB, 1.0) / 20.0)
        let baseRO = outputResistance(current: max(current, 1.0e-12), lambda: lambda, length: baseLength, technology: technology)
        let neededScale = sqrt(max(targetLinear / max(baseRO * 1.0e-4, 1.0), 1.0))
        return min(max(baseLength * min(neededScale, 8.0), technology.minimumLength), technology.minimumLength * 12.0)
    }

    private func outputResistance(
        current: Double,
        lambda: Double,
        length: Double,
        technology: OpAmpSizingTechnologyModel
    ) -> Double {
        let lengthScale = max(length / technology.minimumLength, 1.0)
        return lengthScale / max(lambda * max(current, 1.0e-12), 1.0e-12)
    }

    private func parallel(_ left: Double, _ right: Double) -> Double {
        let denominator = left + right
        guard denominator > 0 else {
            return 0
        }
        return left * right / denominator
    }

    private func requirementValue(
        _ spec: OpAmpSpec,
        _ metricID: OpAmpMetricID,
        defaultValue: Double
    ) -> Double {
        guard let value = spec.requirement(for: metricID)?.value, value.isFinite, value > 0 else {
            return defaultValue
        }
        return value
    }

    private func supply(_ spec: OpAmpSpec) -> Double {
        spec.operatingPoint.supplyVoltage - spec.operatingPoint.groundVoltage
    }

    private func validate(spec: OpAmpSpec, technology: OpAmpSizingTechnologyModel) throws {
        guard spec.operatingPoint.supplyVoltage > spec.operatingPoint.groundVoltage else {
            throw OpAmpSizingError.invalidSpecification("Supply voltage must be above ground voltage.")
        }
        guard spec.operatingPoint.loadCapacitance > 0 else {
            throw OpAmpSizingError.invalidSpecification("Load capacitance must be positive.")
        }
        guard technology.minimumLength > 0, technology.minimumWidth > 0 else {
            throw OpAmpSizingError.invalidTechnology("Minimum geometry must be positive.")
        }
        guard technology.maximumWidth >= technology.minimumWidth else {
            throw OpAmpSizingError.invalidTechnology("Maximum width must not be smaller than minimum width.")
        }
    }
}
