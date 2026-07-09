import Foundation

public struct OpAmpTopologyLibrary: Sendable {
    public init() {}

    public func candidates(for spec: OpAmpSpec) -> [OpAmpTopologyCandidate] {
        allCandidates()
            .filter { spec.allowedTopologies.contains($0.kind) }
            .map { annotate($0, for: spec) }
            .sorted { left, right in
                score(left, for: spec) > score(right, for: spec)
            }
    }

    public func candidate(kind: OpAmpTopologyKind, for spec: OpAmpSpec) -> OpAmpTopologyCandidate? {
        candidates(for: spec).first { $0.kind == kind }
    }

    private func allCandidates() -> [OpAmpTopologyCandidate] {
        [
            twoStageMiller(),
            foldedCascode(),
            telescopicCascode(),
        ]
    }

    private func twoStageMiller() -> OpAmpTopologyCandidate {
        OpAmpTopologyCandidate(
            topologyID: "opamp.topology.two-stage-miller",
            kind: .twoStageMiller,
            label: "Two-stage Miller compensated op-amp",
            stageCount: 2,
            deviceRoles: [
                .init(roleID: "inputPair", deviceKind: .nmos, count: 2, matchedGroupID: "input-pair", symmetryGroupID: "input-pair"),
                .init(roleID: "activeLoadMirror", deviceKind: .pmos, count: 2, matchedGroupID: "pmos-load", symmetryGroupID: "input-pair"),
                .init(roleID: "tailCurrent", deviceKind: .nmos, count: 1),
                .init(roleID: "secondStageDriver", deviceKind: .nmos, count: 1),
                .init(roleID: "secondStageLoad", deviceKind: .pmos, count: 1),
                .init(roleID: "compensation", deviceKind: .capacitor, count: 1),
            ],
            capabilities: [
                .init(metricID: .dcGainDB, rating: 0.75, rationale: "Two gain stages provide good moderate-gain coverage."),
                .init(metricID: .unityGainFrequencyHz, rating: 0.8, rationale: "Miller capacitor makes bandwidth controllable."),
                .init(metricID: .phaseMarginDegrees, rating: 0.8, rationale: "Dominant-pole compensation is explicit."),
                .init(metricID: .positiveSlewRateVPerS, rating: 0.65, rationale: "Slew rate is limited by compensation current."),
                .init(metricID: .outputSwingHighV, rating: 0.7, rationale: "Second stage gives broad output swing."),
            ],
            requiredBiases: ["tail-nmos", "second-stage-pmos"],
            layoutIntentIDs: ["input-pair-symmetry", "pmos-load-matching", "compensation-cap-near-second-stage"]
        )
    }

    private func foldedCascode() -> OpAmpTopologyCandidate {
        OpAmpTopologyCandidate(
            topologyID: "opamp.topology.folded-cascode",
            kind: .foldedCascode,
            label: "Folded cascode op-amp",
            stageCount: 1,
            deviceRoles: [
                .init(roleID: "inputPair", deviceKind: .nmos, count: 2, matchedGroupID: "input-pair", symmetryGroupID: "input-pair"),
                .init(roleID: "foldingDevices", deviceKind: .pmos, count: 2, matchedGroupID: "folding-pair", symmetryGroupID: "input-pair"),
                .init(roleID: "cascodeDevices", deviceKind: .nmos, count: 4, matchedGroupID: "cascode-array"),
                .init(roleID: "biasMirrors", deviceKind: .pmos, count: 2, matchedGroupID: "bias-mirror"),
            ],
            capabilities: [
                .init(metricID: .dcGainDB, rating: 0.85, rationale: "Cascode output resistance improves gain."),
                .init(metricID: .unityGainFrequencyHz, rating: 0.75, rationale: "Single-stage structure avoids Miller pole splitting."),
                .init(metricID: .phaseMarginDegrees, rating: 0.85, rationale: "Often stable as a single dominant output-pole amplifier."),
                .init(metricID: .outputSwingHighV, rating: 0.55, rationale: "Headroom is consumed by folded cascode stacks."),
                .init(metricID: .cmrrDB, rating: 0.8, rationale: "Symmetric input and cascode branches support rejection."),
            ],
            requiredBiases: ["tail-nmos", "fold-pmos", "cascode-nmos", "bias-mirror"],
            layoutIntentIDs: ["input-pair-common-centroid", "folding-device-symmetry", "cascode-array-matching"]
        )
    }

    private func telescopicCascode() -> OpAmpTopologyCandidate {
        OpAmpTopologyCandidate(
            topologyID: "opamp.topology.telescopic-cascode",
            kind: .telescopicCascode,
            label: "Telescopic cascode op-amp",
            stageCount: 1,
            deviceRoles: [
                .init(roleID: "inputPair", deviceKind: .nmos, count: 2, matchedGroupID: "input-pair", symmetryGroupID: "input-pair"),
                .init(roleID: "nmosCascodes", deviceKind: .nmos, count: 2, matchedGroupID: "nmos-cascode", symmetryGroupID: "input-pair"),
                .init(roleID: "pmosLoads", deviceKind: .pmos, count: 2, matchedGroupID: "pmos-load", symmetryGroupID: "input-pair"),
                .init(roleID: "pmosCascodes", deviceKind: .pmos, count: 2, matchedGroupID: "pmos-cascode", symmetryGroupID: "input-pair"),
                .init(roleID: "tailCurrent", deviceKind: .nmos, count: 1),
            ],
            capabilities: [
                .init(metricID: .dcGainDB, rating: 0.9, rationale: "Stacked cascodes maximize output resistance."),
                .init(metricID: .unityGainFrequencyHz, rating: 0.85, rationale: "Single-stage topology can be fast at modest load."),
                .init(metricID: .phaseMarginDegrees, rating: 0.8, rationale: "Single-stage topology has simpler stability behavior."),
                .init(metricID: .outputSwingHighV, rating: 0.35, rationale: "Stack headroom reduces swing."),
                .init(metricID: .inputCommonModeMinV, rating: 0.35, rationale: "Input common-mode range is narrow at low supply."),
            ],
            requiredBiases: ["tail-nmos", "nmos-cascode", "pmos-cascode"],
            layoutIntentIDs: ["input-pair-common-centroid", "cascode-stack-symmetry", "tail-current-on-axis"]
        )
    }

    private func annotate(
        _ candidate: OpAmpTopologyCandidate,
        for spec: OpAmpSpec
    ) -> OpAmpTopologyCandidate {
        var annotated = candidate
        let supply = spec.operatingPoint.supplyVoltage - spec.operatingPoint.groundVoltage
        if candidate.kind == .telescopicCascode && supply < 1.5 {
            annotated.diagnostics.append("Telescopic cascode headroom is risky below 1.5 V.")
        }
        if candidate.kind == .foldedCascode && supply < 1.2 {
            annotated.diagnostics.append("Folded cascode bias headroom is risky below 1.2 V.")
        }
        if let phaseMargin = spec.requirement(for: .phaseMarginDegrees), phaseMargin.value >= 70,
           candidate.kind == .twoStageMiller {
            annotated.diagnostics.append("High phase margin may require larger compensation and lower bandwidth.")
        }
        return annotated
    }

    private func score(
        _ candidate: OpAmpTopologyCandidate,
        for spec: OpAmpSpec
    ) -> Double {
        var score = candidate.capabilities.reduce(0.0) { partial, capability in
            let weight = spec.requirement(for: capability.metricID)?.weight ?? 0.25
            return partial + capability.rating * weight
        }
        score -= Double(candidate.diagnostics.count) * 0.2
        return score
    }
}
