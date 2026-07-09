import Foundation

public struct OpAmpSpec: Sendable, Hashable, Codable {
    public struct Requirement: Sendable, Hashable, Codable {
        public enum Relation: String, Sendable, Hashable, Codable {
            case atLeast
            case atMost
            case between
            case equal
        }

        public enum Severity: String, Sendable, Hashable, Codable {
            case info
            case warning
            case error
            case blocker
        }

        public var metricID: OpAmpMetricID
        public var relation: Relation
        public var value: Double
        public var upperValue: Double?
        public var tolerance: Double?
        public var unit: String
        public var severity: Severity
        public var weight: Double

        public init(
            metricID: OpAmpMetricID,
            relation: Relation,
            value: Double,
            upperValue: Double? = nil,
            tolerance: Double? = nil,
            unit: String,
            severity: Severity = .error,
            weight: Double = 1
        ) {
            self.metricID = metricID
            self.relation = relation
            self.value = value
            self.upperValue = upperValue
            self.tolerance = tolerance
            self.unit = unit
            self.severity = severity
            self.weight = weight
        }
    }

    public struct OperatingPoint: Sendable, Hashable, Codable {
        public var supplyVoltage: Double
        public var groundVoltage: Double
        public var inputCommonModeVoltage: Double
        public var outputCommonModeVoltage: Double
        public var loadCapacitance: Double
        public var loadResistance: Double?
        public var temperatureCelsius: Double

        public init(
            supplyVoltage: Double,
            groundVoltage: Double = 0,
            inputCommonModeVoltage: Double,
            outputCommonModeVoltage: Double,
            loadCapacitance: Double,
            loadResistance: Double? = nil,
            temperatureCelsius: Double = 27
        ) {
            self.supplyVoltage = supplyVoltage
            self.groundVoltage = groundVoltage
            self.inputCommonModeVoltage = inputCommonModeVoltage
            self.outputCommonModeVoltage = outputCommonModeVoltage
            self.loadCapacitance = loadCapacitance
            self.loadResistance = loadResistance
            self.temperatureCelsius = temperatureCelsius
        }
    }

    public struct DesignLimits: Sendable, Hashable, Codable {
        public var maximumStaticPower: Double?
        public var maximumInputOffsetVoltage: Double?
        public var maximumInputReferredNoise: Double?
        public var minimumOutputSwingHigh: Double?
        public var maximumOutputSwingLow: Double?
        public var minimumInputCommonMode: Double?
        public var maximumInputCommonMode: Double?

        public init(
            maximumStaticPower: Double? = nil,
            maximumInputOffsetVoltage: Double? = nil,
            maximumInputReferredNoise: Double? = nil,
            minimumOutputSwingHigh: Double? = nil,
            maximumOutputSwingLow: Double? = nil,
            minimumInputCommonMode: Double? = nil,
            maximumInputCommonMode: Double? = nil
        ) {
            self.maximumStaticPower = maximumStaticPower
            self.maximumInputOffsetVoltage = maximumInputOffsetVoltage
            self.maximumInputReferredNoise = maximumInputReferredNoise
            self.minimumOutputSwingHigh = minimumOutputSwingHigh
            self.maximumOutputSwingLow = maximumOutputSwingLow
            self.minimumInputCommonMode = minimumInputCommonMode
            self.maximumInputCommonMode = maximumInputCommonMode
        }
    }

    public var schemaVersion: Int
    public var specID: String
    public var title: String
    public var operatingPoint: OperatingPoint
    public var requirements: [Requirement]
    public var limits: DesignLimits
    public var allowedTopologies: [OpAmpTopologyKind]
    public var metadata: [String: String]

    public init(
        schemaVersion: Int = 1,
        specID: String,
        title: String,
        operatingPoint: OperatingPoint,
        requirements: [Requirement],
        limits: DesignLimits = DesignLimits(),
        allowedTopologies: [OpAmpTopologyKind] = OpAmpTopologyKind.allCases,
        metadata: [String: String] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.specID = specID
        self.title = title
        self.operatingPoint = operatingPoint
        self.requirements = requirements
        self.limits = limits
        self.allowedTopologies = allowedTopologies
        self.metadata = metadata
    }

    public func requirement(for metricID: OpAmpMetricID) -> Requirement? {
        requirements.first { $0.metricID == metricID }
    }

    public static func makeDefault(
        specID: String = "opamp-spec",
        supplyVoltage: Double = 1.8,
        loadCapacitance: Double = 1.0e-12,
        dcGainDB: Double = 60,
        unityGainFrequencyHz: Double = 10.0e6,
        phaseMarginDegrees: Double = 60,
        slewRateVPerS: Double = 5.0e6
    ) -> OpAmpSpec {
        OpAmpSpec(
            specID: specID,
            title: "Operational amplifier specification",
            operatingPoint: OperatingPoint(
                supplyVoltage: supplyVoltage,
                inputCommonModeVoltage: supplyVoltage / 2,
                outputCommonModeVoltage: supplyVoltage / 2,
                loadCapacitance: loadCapacitance
            ),
            requirements: [
                Requirement(metricID: .dcGainDB, relation: .atLeast, value: dcGainDB, unit: "dB"),
                Requirement(metricID: .unityGainFrequencyHz, relation: .atLeast, value: unityGainFrequencyHz, unit: "Hz"),
                Requirement(metricID: .phaseMarginDegrees, relation: .atLeast, value: phaseMarginDegrees, unit: "deg"),
                Requirement(metricID: .positiveSlewRateVPerS, relation: .atLeast, value: slewRateVPerS, unit: "V/s"),
                Requirement(metricID: .negativeSlewRateVPerS, relation: .atLeast, value: slewRateVPerS, unit: "V/s"),
                Requirement(metricID: .cmrrDB, relation: .atLeast, value: 70, unit: "dB", severity: .warning),
                Requirement(metricID: .psrrPositiveDB, relation: .atLeast, value: 60, unit: "dB", severity: .warning),
                Requirement(metricID: .psrrNegativeDB, relation: .atLeast, value: 60, unit: "dB", severity: .warning),
                Requirement(metricID: .inputReferredNoiseVPerRootHz, relation: .atMost, value: 50.0e-9, unit: "V/sqrt(Hz)", severity: .warning),
                Requirement(metricID: .inputOffsetVoltage, relation: .atMost, value: 2.0e-3, unit: "V", severity: .warning),
            ],
            limits: DesignLimits(
                maximumStaticPower: 1.0e-3,
                maximumInputOffsetVoltage: 2.0e-3,
                maximumInputReferredNoise: 50.0e-9,
                minimumOutputSwingHigh: supplyVoltage * 0.85,
                maximumOutputSwingLow: supplyVoltage * 0.15,
                minimumInputCommonMode: supplyVoltage * 0.25,
                maximumInputCommonMode: supplyVoltage * 0.75
            )
        )
    }
}
