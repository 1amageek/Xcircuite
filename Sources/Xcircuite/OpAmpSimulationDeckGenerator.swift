import Foundation

public struct OpAmpSimulationDeckGenerator: Sendable {
    public init() {}

    public func makeDeckSet(
        spec: OpAmpSpec,
        sizingResult: OpAmpSizingResult
    ) -> OpAmpSimulationDeckSet {
        let fixture = topologyFixture(for: sizingResult.topology.kind)
        let decks = [
            operatingPointDeck(spec: spec, sizingResult: sizingResult, fixture: fixture),
            acOpenLoopDeck(spec: spec, sizingResult: sizingResult, fixture: fixture),
            transientPositiveDeck(spec: spec, sizingResult: sizingResult, fixture: fixture),
            transientNegativeDeck(spec: spec, sizingResult: sizingResult, fixture: fixture),
            noiseDeck(spec: spec, sizingResult: sizingResult, fixture: fixture),
        ]
        return OpAmpSimulationDeckSet(
            specID: spec.specID,
            topologyKind: sizingResult.topology.kind,
            decks: decks,
            diagnostics: diagnostics(for: decks)
        )
    }

    private func operatingPointDeck(
        spec: OpAmpSpec,
        sizingResult: OpAmpSizingResult,
        fixture: TopologyFixture
    ) -> OpAmpSimulationDeckSet.Deck {
        let measurements = ["inputCommonMode", "outputCommonMode"]
        return .init(
            deckID: "op-bias",
            analysisKind: "op",
            title: "Op-amp operating point bias deck",
            netlist: deckText(
                title: "Op-amp operating point bias deck",
                sizingResult: sizingResult,
                fixture: fixture,
                operatingPoint: spec.operatingPoint,
                input: .dc,
                analysisLines: [
                    ".op",
                    ".meas op inputCommonMode FIND V(vinp) AT=0",
                    ".meas op outputCommonMode FIND V(\(fixture.primaryOutputNode)) AT=0",
                ]
            ),
            measurementNames: measurements,
            notes: ["Bias deck measures operating voltages for human review and downstream offset post-processing."]
        )
    }

    private func acOpenLoopDeck(
        spec: OpAmpSpec,
        sizingResult: OpAmpSizingResult,
        fixture: TopologyFixture
    ) -> OpAmpSimulationDeckSet.Deck {
        let stop = max(requirementValue(spec, .unityGainFrequencyHz, defaultValue: 10.0e6) * 100.0, 1.0e9)
        let measurements = ["openLoopGainMagnitude", "unityGainCrossing"]
        return .init(
            deckID: "ac-open-loop",
            analysisKind: "ac",
            title: "Op-amp differential open-loop AC deck",
            netlist: deckText(
                title: "Op-amp differential open-loop AC deck",
                sizingResult: sizingResult,
                fixture: fixture,
                operatingPoint: spec.operatingPoint,
                input: .acDifferential,
                analysisLines: [
                    ".ac dec 40 1 \(format(stop))",
                    ".meas ac openLoopGainMagnitude FIND V(\(fixture.primaryOutputNode)) AT=1",
                    ".meas ac unityGainCrossing WHEN V(\(fixture.primaryOutputNode))=1",
                ]
            ),
            postProcessingMetricIDs: [.dcGainDB, .unityGainFrequencyHz, .phaseMarginDegrees],
            measurementNames: measurements,
            notes: [
                "CoreSpice direct .measure captures AC waveform evidence; dB gain and phase margin require waveform post-processing.",
            ]
        )
    }

    private func transientPositiveDeck(
        spec: OpAmpSpec,
        sizingResult: OpAmpSizingResult,
        fixture: TopologyFixture
    ) -> OpAmpSimulationDeckSet.Deck {
        let stop = transientStop(spec)
        let start = stop * 0.2
        let measurements = ["outputSwingHigh", "settlingTimePositive"]
        return .init(
            deckID: "tran-positive-step",
            analysisKind: "tran",
            title: "Op-amp positive-step transient deck",
            netlist: deckText(
                title: "Op-amp positive-step transient deck",
                sizingResult: sizingResult,
                fixture: fixture,
                operatingPoint: spec.operatingPoint,
                input: .positiveStep(stop: stop),
                analysisLines: [
                    ".tran \(format(stop / 500.0)) \(format(stop))",
                    ".meas tran outputSwingHigh MAX V(\(fixture.primaryOutputNode)) FROM=\(format(start)) TO=\(format(stop))",
                    ".meas tran settlingTimePositive WHEN V(\(fixture.primaryOutputNode))=\(format(spec.operatingPoint.outputCommonModeVoltage))",
                ]
            ),
            directMetricIDs: [.outputSwingHighV],
            postProcessingMetricIDs: [.positiveSlewRateVPerS, .settlingTimeSeconds],
            measurementNames: measurements,
            notes: ["Slew rate should be computed from the transient waveform slope, not from a scalar .measure alone."]
        )
    }

    private func transientNegativeDeck(
        spec: OpAmpSpec,
        sizingResult: OpAmpSizingResult,
        fixture: TopologyFixture
    ) -> OpAmpSimulationDeckSet.Deck {
        let stop = transientStop(spec)
        let start = stop * 0.2
        let measurements = ["outputSwingLow", "settlingTimeNegative"]
        return .init(
            deckID: "tran-negative-step",
            analysisKind: "tran",
            title: "Op-amp negative-step transient deck",
            netlist: deckText(
                title: "Op-amp negative-step transient deck",
                sizingResult: sizingResult,
                fixture: fixture,
                operatingPoint: spec.operatingPoint,
                input: .negativeStep(stop: stop),
                analysisLines: [
                    ".tran \(format(stop / 500.0)) \(format(stop))",
                    ".meas tran outputSwingLow MIN V(\(fixture.primaryOutputNode)) FROM=\(format(start)) TO=\(format(stop))",
                    ".meas tran settlingTimeNegative WHEN V(\(fixture.primaryOutputNode))=\(format(spec.operatingPoint.outputCommonModeVoltage))",
                ]
            ),
            directMetricIDs: [.outputSwingLowV],
            postProcessingMetricIDs: [.negativeSlewRateVPerS, .settlingTimeSeconds],
            measurementNames: measurements,
            notes: ["Negative slew rate should be computed from the transient waveform slope."]
        )
    }

    private func noiseDeck(
        spec: OpAmpSpec,
        sizingResult: OpAmpSizingResult,
        fixture: TopologyFixture
    ) -> OpAmpSimulationDeckSet.Deck {
        .init(
            deckID: "noise-input-referred",
            analysisKind: "noise",
            title: "Op-amp input-referred noise deck",
            netlist: deckText(
                title: "Op-amp input-referred noise deck",
                sizingResult: sizingResult,
                fixture: fixture,
                operatingPoint: spec.operatingPoint,
                input: .noise,
                analysisLines: [
                    ".noise V(\(fixture.primaryOutputNode)) VINP dec 20 1 1e6",
                ]
            ),
            postProcessingMetricIDs: [.inputReferredNoiseVPerRootHz],
            notes: ["Noise waveform output must be reduced to the requested input-referred-noise metric by the evaluation layer."]
        )
    }

    private func deckText(
        title: String,
        sizingResult: OpAmpSizingResult,
        fixture: TopologyFixture,
        operatingPoint: OpAmpSpec.OperatingPoint,
        input: InputStimulus,
        analysisLines: [String]
    ) -> String {
        let lines = [
            ["* \(title)"],
            [sizingResult.netlist.trimmingCharacters(in: .whitespacesAndNewlines)],
            fixture.instanceAndLoadLines(input: input, operatingPoint: operatingPoint),
            analysisLines,
            [".end"],
        ].flatMap { $0 }
        return lines.joined(separator: "\n") + "\n"
    }

    private func topologyFixture(for topology: OpAmpTopologyKind) -> TopologyFixture {
        switch topology {
        case .twoStageMiller:
            TopologyFixture(
                subcircuitName: "opamp_two_stage_miller",
                instancePins: ["vinp", "vinn", "vout", "vdd", "vss", "vbiasn", "vbiasp"],
                primaryOutputNode: "vout",
                secondaryOutputNode: nil,
                biasNodes: ["vbiasn", "vbiasp"]
            )
        case .foldedCascode:
            TopologyFixture(
                subcircuitName: "opamp_folded_cascode",
                instancePins: ["vinp", "vinn", "voutp", "voutn", "vdd", "vss", "vbiasn", "vbiasp", "vcasn"],
                primaryOutputNode: "voutp",
                secondaryOutputNode: "voutn",
                biasNodes: ["vbiasn", "vbiasp", "vcasn"]
            )
        case .telescopicCascode:
            TopologyFixture(
                subcircuitName: "opamp_telescopic_cascode",
                instancePins: ["vinp", "vinn", "voutp", "voutn", "vdd", "vss", "vbiasn", "vcasn", "vcasp"],
                primaryOutputNode: "voutp",
                secondaryOutputNode: "voutn",
                biasNodes: ["vbiasn", "vcasn", "vcasp"]
            )
        }
    }

    private func diagnostics(for decks: [OpAmpSimulationDeckSet.Deck]) -> [OpAmpDesignDiagnostic] {
        let postProcessing = Set(decks.flatMap(\.postProcessingMetricIDs))
        guard !postProcessing.isEmpty else {
            return []
        }
        return [
            .init(
                severity: .info,
                code: "opamp.simulation-decks.post-processing-required",
                message: "Some op-amp metrics require waveform post-processing after CoreSpice simulation.",
                relatedMetricIDs: Array(postProcessing).sorted { $0.rawValue < $1.rawValue },
                suggestedActions: ["run-analysis-decks", "extract-waveform-derived-opamp-metrics"]
            ),
        ]
    }

    private func transientStop(_ spec: OpAmpSpec) -> Double {
        let targetUGF = requirementValue(spec, .unityGainFrequencyHz, defaultValue: 10.0e6)
        return max(20.0 / targetUGF, 1.0e-6)
    }

    private func requirementValue(
        _ spec: OpAmpSpec,
        _ metricID: OpAmpMetricID,
        defaultValue: Double
    ) -> Double {
        spec.requirement(for: metricID)?.value ?? defaultValue
    }

    private func format(_ value: Double) -> String {
        String(format: "%.6e", value)
    }
}

private enum InputStimulus: Sendable, Hashable {
    case dc
    case acDifferential
    case positiveStep(stop: Double)
    case negativeStep(stop: Double)
    case noise
}

private struct TopologyFixture: Sendable, Hashable {
    var subcircuitName: String
    var instancePins: [String]
    var primaryOutputNode: String
    var secondaryOutputNode: String?
    var biasNodes: [String]

    func instanceAndLoadLines(input: InputStimulus, operatingPoint: OpAmpSpec.OperatingPoint) -> [String] {
        let supply = operatingPoint.supplyVoltage
        let commonMode = operatingPoint.inputCommonModeVoltage
        var lines = [
            "XUOP \(instancePins.joined(separator: " ")) \(subcircuitName)",
            "VDD vdd 0 DC \(format(supply))",
            "VSS vss 0 DC \(format(operatingPoint.groundVoltage))",
        ]
        lines.append(contentsOf: inputLines(input: input, commonMode: commonMode))
        lines.append(contentsOf: biasLines(supply: supply))
        lines.append("CLP \(primaryOutputNode) 0 \(format(operatingPoint.loadCapacitance))")
        if let secondaryOutputNode {
            lines.append("CLN \(secondaryOutputNode) 0 \(format(operatingPoint.loadCapacitance))")
        }
        return lines
    }

    private func inputLines(input: InputStimulus, commonMode: Double) -> [String] {
        switch input {
        case .dc:
            [
                "VINP vinp 0 DC \(format(commonMode))",
                "VINN vinn 0 DC \(format(commonMode))",
            ]
        case .acDifferential:
            [
                "VINP vinp 0 DC \(format(commonMode)) AC 0.5",
                "VINN vinn 0 DC \(format(commonMode)) AC -0.5",
            ]
        case .positiveStep(let stop):
            [
                "VINP vinp 0 PULSE(\(format(commonMode)) \(format(commonMode + 0.01)) 0 1e-9 1e-9 \(format(stop / 2.0)) \(format(stop)))",
                "VINN vinn 0 DC \(format(commonMode))",
            ]
        case .negativeStep(let stop):
            [
                "VINP vinp 0 PULSE(\(format(commonMode)) \(format(commonMode - 0.01)) 0 1e-9 1e-9 \(format(stop / 2.0)) \(format(stop)))",
                "VINN vinn 0 DC \(format(commonMode))",
            ]
        case .noise:
            [
                "VINP vinp 0 DC \(format(commonMode)) AC 1",
                "VINN vinn 0 DC \(format(commonMode))",
            ]
        }
    }

    private func biasLines(supply: Double) -> [String] {
        biasNodes.map { node in
            let voltage = node.contains("p") ? supply * 0.65 : supply * 0.35
            return "V\(node.uppercased()) \(node) 0 DC \(format(voltage))"
        }
    }

    private func format(_ value: Double) -> String {
        String(format: "%.6e", value)
    }
}
