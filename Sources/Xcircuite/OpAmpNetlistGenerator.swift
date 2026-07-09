import Foundation

public struct OpAmpNetlistGenerator: Sendable {
    public init() {}

    public func makeNetlist(
        spec: OpAmpSpec,
        sizing devices: [OpAmpSizedDevice],
        topology: OpAmpTopologyCandidate,
        technology: OpAmpSizingTechnologyModel
    ) -> String {
        let lines: [String]
        switch topology.kind {
        case .twoStageMiller:
            lines = twoStageMillerNetlist(spec: spec, devices: devices, technology: technology)
        case .foldedCascode:
            lines = foldedCascodeNetlist(spec: spec, devices: devices, technology: technology)
        case .telescopicCascode:
            lines = telescopicCascodeNetlist(spec: spec, devices: devices, technology: technology)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func twoStageMillerNetlist(
        spec: OpAmpSpec,
        devices: [OpAmpSizedDevice],
        technology: OpAmpSizingTechnologyModel
    ) -> [String] {
        [
            "* \(spec.title)",
            ".subckt opamp_two_stage_miller vinp vinn vout vdd vss vbiasn vbiasp",
            mosLine("M1", drain: "n1", gate: "vinn", source: "tail", bulk: "vss", devices: devices),
            mosLine("M2", drain: "n2", gate: "vinp", source: "tail", bulk: "vss", devices: devices),
            mosLine("M3", drain: "n1", gate: "n1", source: "vdd", bulk: "vdd", devices: devices),
            mosLine("M4", drain: "n2", gate: "n1", source: "vdd", bulk: "vdd", devices: devices),
            mosLine("M5", drain: "tail", gate: "vbiasn", source: "vss", bulk: "vss", devices: devices),
            mosLine("M6", drain: "vout", gate: "n2", source: "vss", bulk: "vss", devices: devices),
            mosLine("M7", drain: "vout", gate: "vbiasp", source: "vdd", bulk: "vdd", devices: devices),
            capacitorLine("Cc", positive: "n2", negative: "vout", devices: devices),
            ".ends opamp_two_stage_miller",
            "",
            modelLine(name: technology.nmosModelName, kind: "nmos", threshold: technology.nominalNmosThreshold),
            modelLine(name: technology.pmosModelName, kind: "pmos", threshold: technology.nominalPmosThreshold),
        ]
    }

    private func foldedCascodeNetlist(
        spec: OpAmpSpec,
        devices: [OpAmpSizedDevice],
        technology: OpAmpSizingTechnologyModel
    ) -> [String] {
        [
            "* \(spec.title)",
            ".subckt opamp_folded_cascode vinp vinn voutp voutn vdd vss vbiasn vbiasp vcasn",
            mosLine("M1", drain: "nf1", gate: "vinp", source: "tail", bulk: "vss", devices: devices),
            mosLine("M2", drain: "nf2", gate: "vinn", source: "tail", bulk: "vss", devices: devices),
            mosLine("M3", drain: "voutp", gate: "vbiasp", source: "vdd", bulk: "vdd", devices: devices),
            mosLine("M4", drain: "voutn", gate: "vbiasp", source: "vdd", bulk: "vdd", devices: devices),
            mosLine("Mcas1", drain: "voutp", gate: "vcasn", source: "nf1", bulk: "vss", devices: devices),
            mosLine("Mcas2", drain: "voutn", gate: "vcasn", source: "nf2", bulk: "vss", devices: devices),
            mosLine("Mcas3", drain: "nf1", gate: "vbiasn", source: "vss", bulk: "vss", devices: devices),
            mosLine("Mcas4", drain: "nf2", gate: "vbiasn", source: "vss", bulk: "vss", devices: devices),
            ".ends opamp_folded_cascode",
            "",
            modelLine(name: technology.nmosModelName, kind: "nmos", threshold: technology.nominalNmosThreshold),
            modelLine(name: technology.pmosModelName, kind: "pmos", threshold: technology.nominalPmosThreshold),
        ]
    }

    private func telescopicCascodeNetlist(
        spec: OpAmpSpec,
        devices: [OpAmpSizedDevice],
        technology: OpAmpSizingTechnologyModel
    ) -> [String] {
        [
            "* \(spec.title)",
            ".subckt opamp_telescopic_cascode vinp vinn voutp voutn vdd vss vbiasn vcasn vcasp",
            mosLine("M1", drain: "n1", gate: "vinp", source: "tail", bulk: "vss", devices: devices),
            mosLine("M2", drain: "n2", gate: "vinn", source: "tail", bulk: "vss", devices: devices),
            mosLine("MNcas1", drain: "voutp", gate: "vcasn", source: "n1", bulk: "vss", devices: devices),
            mosLine("MNcas2", drain: "voutn", gate: "vcasn", source: "n2", bulk: "vss", devices: devices),
            mosLine("MPcas1", drain: "voutp", gate: "vcasp", source: "vdd", bulk: "vdd", devices: devices),
            mosLine("MPcas2", drain: "voutn", gate: "vcasp", source: "vdd", bulk: "vdd", devices: devices),
            mosLine("Mtail", drain: "tail", gate: "vbiasn", source: "vss", bulk: "vss", devices: devices),
            ".ends opamp_telescopic_cascode",
            "",
            modelLine(name: technology.nmosModelName, kind: "nmos", threshold: technology.nominalNmosThreshold),
            modelLine(name: technology.pmosModelName, kind: "pmos", threshold: technology.nominalPmosThreshold),
        ]
    }

    private func mosLine(
        _ name: String,
        drain: String,
        gate: String,
        source: String,
        bulk: String,
        devices: [OpAmpSizedDevice]
    ) -> String {
        guard let device = devices.first(where: { $0.instanceName == name }),
              let model = device.modelName,
              let width = device.width,
              let length = device.length else {
            return "* \(name) missing sizing"
        }
        return "\(name) \(drain) \(gate) \(source) \(bulk) \(model) W=\(format(width)) L=\(format(length)) M=\(device.multiplier) NF=\(device.fingers)"
    }

    private func capacitorLine(
        _ name: String,
        positive: String,
        negative: String,
        devices: [OpAmpSizedDevice]
    ) -> String {
        guard let device = devices.first(where: { $0.instanceName == name }),
              let value = device.value else {
            return "* \(name) missing sizing"
        }
        return "\(name) \(positive) \(negative) \(format(value))"
    }

    private func modelLine(name: String, kind: String, threshold: Double) -> String {
        ".model \(name) \(kind) level=1 vto=\(format(threshold)) kp=100e-6 lambda=0.05"
    }

    private func format(_ value: Double) -> String {
        String(format: "%.6e", value)
    }
}
