import Foundation
import XcircuitePackage

public struct OpAmpEvaluationProfileFactory: Sendable {
    public init() {}

    public func makeProfile(
        profileID: String = "opamp-evaluation-profile"
    ) -> XcircuiteEvaluationProfile {
        XcircuiteEvaluationProfile(
            profileID: profileID,
            domain: "analog-opamp",
            metricChannels: metricChannels(),
            requiredAnalyses: requiredAnalyses(),
            artifactRoles: artifactRoles(),
            comparisonPolicy: .previousIteration,
            metadata: [
                "intent": .string("Provide evaluation material for external Agent-driven op-amp design iterations."),
                "loopOwner": .string("external-agent"),
            ]
        )
    }

    private func metricChannels() -> [XcircuiteEvaluationProfile.MetricChannel] {
        [
            metric("dc.operatingPoint", label: "DC operating point", direction: .categorical),
            metric("dc.biasRegion", label: "Device operating regions", direction: .categorical),
            metric("ac.dcGain", label: "DC gain", unit: "dB", direction: .maximize),
            metric("ac.unityGainFrequency", label: "Unity gain frequency", unit: "Hz", direction: .maximize),
            metric("ac.phaseMargin", label: "Phase margin", unit: "deg", direction: .bounded),
            metric("tran.slewRatePositive", label: "Positive slew rate", unit: "V/s", direction: .maximize),
            metric("tran.slewRateNegative", label: "Negative slew rate", unit: "V/s", direction: .maximize),
            metric("tran.settlingTime", label: "Settling time", unit: "s", direction: .minimize),
            metric("tran.outputSwingHigh", label: "Output swing high", unit: "V", direction: .maximize),
            metric("tran.outputSwingLow", label: "Output swing low", unit: "V", direction: .minimize),
            metric("input.commonModeRange", label: "Input common-mode range", unit: "V", direction: .bounded),
            metric("input.offsetVoltage", label: "Input offset voltage", unit: "V", direction: .minimize),
            metric("noise.inputReferredNoise", label: "Input-referred noise", unit: "V/sqrt(Hz)", direction: .minimize),
            metric("ac.cmrr", label: "CMRR", unit: "dB", direction: .maximize),
            metric("ac.psrrPositive", label: "Positive PSRR", unit: "dB", direction: .maximize),
            metric("ac.psrrNegative", label: "Negative PSRR", unit: "dB", direction: .maximize),
            metric("power.quiescentCurrent", label: "Quiescent current", unit: "A", direction: .minimize),
            metric("power.staticPower", label: "Static power", unit: "W", direction: .minimize),
            metric("layout.area", label: "Layout area", unit: "um^2", direction: .minimize, required: false),
            metric("drc.violationCount", label: "DRC violation count", direction: .minimize, required: false),
            metric("lvs.status", label: "LVS status", direction: .categorical, required: false),
            metric("pex.deltaGain", label: "Post-layout gain delta", unit: "dB", direction: .bounded, required: false),
            metric("pex.deltaPhaseMargin", label: "Post-layout phase-margin delta", unit: "deg", direction: .bounded, required: false),
            metric("pex.totalCapacitance", label: "Extracted total capacitance", unit: "F", direction: .minimize, required: false),
        ]
    }

    private func requiredAnalyses() -> [XcircuiteEvaluationProfile.RequiredAnalysis] {
        [
            analysis("dc-operating-point", domain: "simulation", artifactRole: "simulation-summary"),
            analysis("ac-small-signal", domain: "simulation", artifactRole: "simulation-summary"),
            analysis("transient-large-signal", domain: "simulation", artifactRole: "waveform-summary"),
            analysis("noise", domain: "simulation", artifactRole: "noise-summary"),
            analysis("layout-drc", domain: "layout", artifactRole: "drc-summary", required: false),
            analysis("layout-lvs", domain: "layout", artifactRole: "lvs-summary", required: false),
            analysis("layout-pex", domain: "layout", artifactRole: "pex-summary", required: false),
            analysis("post-layout-comparison", domain: "evaluation", artifactRole: "post-layout-comparison", required: false),
        ]
    }

    private func artifactRoles() -> [XcircuiteEvaluationProfile.ArtifactRole] {
        [
            role("netlist", description: "Canonical SPICE netlist used by the run."),
            role("simulation-summary", description: "Structured simulation result with evaluated metric channels."),
            role("waveform-summary", description: "Transient waveform metrics and source waveform references."),
            role("noise-summary", description: "Noise analysis metrics and source references."),
            role("design-diff", description: "Proposed or applied design changes for the iteration.", required: false),
            role("layout", description: "Generated or edited physical layout.", required: false),
            role("drc-summary", description: "DRC outcome and violation metrics.", required: false),
            role("lvs-summary", description: "LVS outcome and mismatch metrics.", required: false),
            role("pex-summary", description: "Parasitic extraction summary and SPEF references.", required: false),
            role("post-layout-comparison", description: "Comparison between schematic and post-layout simulation.", required: false),
        ]
    }

    private func metric(
        _ channelID: String,
        label: String,
        unit: String? = nil,
        direction: XcircuiteEvaluationProfile.MetricChannel.Direction,
        required: Bool = true
    ) -> XcircuiteEvaluationProfile.MetricChannel {
        XcircuiteEvaluationProfile.MetricChannel(
            channelID: channelID,
            label: label,
            unit: unit,
            direction: direction,
            required: required
        )
    }

    private func analysis(
        _ analysisID: String,
        domain: String,
        artifactRole: String,
        required: Bool = true
    ) -> XcircuiteEvaluationProfile.RequiredAnalysis {
        XcircuiteEvaluationProfile.RequiredAnalysis(
            analysisID: analysisID,
            domain: domain,
            artifactRole: artifactRole,
            required: required
        )
    }

    private func role(
        _ role: String,
        description: String,
        required: Bool = true
    ) -> XcircuiteEvaluationProfile.ArtifactRole {
        XcircuiteEvaluationProfile.ArtifactRole(
            role: role,
            required: required,
            description: description
        )
    }
}
