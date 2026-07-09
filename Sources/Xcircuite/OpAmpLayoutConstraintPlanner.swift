import Foundation

public struct OpAmpLayoutConstraintPlanner: Sendable {
    public init() {}

    public func makePlan(
        topology: OpAmpTopologyCandidate,
        devices: [OpAmpSizedDevice]
    ) -> OpAmpLayoutConstraintPlan {
        let namesByRole = Dictionary(grouping: devices, by: \.role)
            .mapValues { $0.map(\.instanceName).sorted() }
        var constraints: [OpAmpLayoutConstraintPlan.Constraint] = []

        if let inputPair = pair(namesByRole["inputPair"]) {
            constraints.append(.init(
                constraintID: "input-pair-symmetry",
                kind: .symmetry,
                members: inputPair,
                rationale: "Differential input devices require mirrored placement to reduce input offset and CMRR loss."
            ))
            constraints.append(.init(
                constraintID: "input-pair-common-centroid",
                kind: .commonCentroid,
                members: inputPair,
                pattern: ["A", "B", "B", "A"],
                rationale: "Input pair common-centroid placement reduces gradient-driven offset."
            ))
            constraints.append(.init(
                constraintID: "input-pair-guard-ring",
                kind: .guardRing,
                members: inputPair,
                rationale: "Input pair guard ring reduces substrate and well noise coupling."
            ))
        }

        for role in ["activeLoadMirror", "pmosLoads", "biasMirrors", "foldingDevices"] {
            guard let members = namesByRole[role], members.count >= 2 else {
                continue
            }
            constraints.append(.init(
                constraintID: "\(role)-matching",
                kind: .matching,
                members: members,
                rationale: "\(role) devices should share dimensions and local environment for mirror accuracy."
            ))
            constraints.append(.init(
                constraintID: "\(role)-interdigitated",
                kind: .interdigitated,
                members: members,
                pattern: interdigitationPattern(members),
                isHard: false,
                rationale: "Interdigitation reduces systematic mismatch across mirror devices."
            ))
        }

        let cascodes = (namesByRole["cascodeDevices"] ?? [])
            + (namesByRole["nmosCascodes"] ?? [])
            + (namesByRole["pmosCascodes"] ?? [])
        if cascodes.count >= 2 {
            constraints.append(.init(
                constraintID: "cascode-array-matching",
                kind: .matching,
                members: cascodes.sorted(),
                rationale: "Cascode arrays require matched orientation and nearby placement for gain and swing predictability."
            ))
        }

        if let tail = namesByRole["tailCurrent"]?.first {
            constraints.append(.init(
                constraintID: "tail-current-on-symmetry-axis",
                kind: .symmetry,
                members: [tail],
                rationale: "Tail current source should be centered on the input symmetry axis."
            ))
        }

        let highImpedanceMembers = ["M2", "M4", "M6", "M7", "Cc"].filter { name in
            devices.contains { $0.instanceName == name }
        }
        if !highImpedanceMembers.isEmpty {
            constraints.append(.init(
                constraintID: "high-impedance-node-shielding",
                kind: .shielding,
                members: highImpedanceMembers,
                isHard: false,
                rationale: "High-impedance gain and compensation nodes should be shielded from switching and supply routing."
            ))
        }

        if devices.contains(where: { $0.instanceName == "Cc" }) {
            constraints.append(.init(
                constraintID: "compensation-cap-proximity",
                kind: .proximity,
                members: ["Cc", "M6", "M7"].filter { name in
                    devices.contains { $0.instanceName == name }
                },
                isHard: false,
                rationale: "Compensation capacitor should stay close to second-stage devices to reduce parasitic uncertainty."
            ))
        }

        return OpAmpLayoutConstraintPlan(
            planID: "\(topology.topologyID).layout-constraints",
            topologyID: topology.topologyID,
            constraints: constraints,
            notes: [
                "Constraints use logical instance names and can be resolved to concrete layout instance IDs after placement.",
            ]
        )
    }

    private func pair(_ values: [String]?) -> [String]? {
        guard let values, values.count >= 2 else {
            return nil
        }
        return Array(values.prefix(2))
    }

    private func interdigitationPattern(_ members: [String]) -> [String] {
        guard members.count == 2 else {
            return members
        }
        return [members[0], members[1], members[1], members[0]]
    }
}
