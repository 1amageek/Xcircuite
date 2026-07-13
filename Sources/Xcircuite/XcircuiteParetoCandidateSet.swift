import Foundation
import DesignFlowKernel

public struct XcircuiteParetoCandidateSet: Codable, Sendable, Hashable {
    public struct Metric: Codable, Sendable, Hashable {
        public var metricID: String
        public var value: Double
        public var normalizedValue: Double
        public var direction: String
        public var unit: String?

        public init(
            metricID: String,
            value: Double,
            normalizedValue: Double,
            direction: String,
            unit: String? = nil
        ) throws {
            try Self.validate(
                metricID: metricID,
                value: value,
                normalizedValue: normalizedValue,
                direction: direction,
                unit: unit
            )
            self.metricID = metricID
            self.value = value
            self.normalizedValue = normalizedValue
            self.direction = direction
            self.unit = unit
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let metricID = try container.decode(String.self, forKey: .metricID)
            let value = try container.decode(Double.self, forKey: .value)
            let normalizedValue = try container.decode(Double.self, forKey: .normalizedValue)
            let direction = try container.decode(String.self, forKey: .direction)
            let unit = try container.decodeIfPresent(String.self, forKey: .unit)
            try self.init(
                metricID: metricID,
                value: value,
                normalizedValue: normalizedValue,
                direction: direction,
                unit: unit
            )
        }

        public func encode(to encoder: Encoder) throws {
            try Self.validate(
                metricID: metricID,
                value: value,
                normalizedValue: normalizedValue,
                direction: direction,
                unit: unit
            )
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(metricID, forKey: .metricID)
            try container.encode(value, forKey: .value)
            try container.encode(normalizedValue, forKey: .normalizedValue)
            try container.encode(direction, forKey: .direction)
            try container.encodeIfPresent(unit, forKey: .unit)
        }

        private enum CodingKeys: String, CodingKey {
            case metricID
            case value
            case normalizedValue
            case direction
            case unit
        }

        private static func validate(
            metricID: String,
            value: Double,
            normalizedValue: Double,
            direction: String,
            unit: String?
        ) throws {
            try XcircuiteParetoCandidateSet.validateIdentifier(metricID, field: "metricID")
            guard value.isFinite else {
                throw XcircuiteParetoCandidateSetValidationError.nonFiniteMetricValue(
                    metricID: metricID,
                    field: "value"
                )
            }
            guard normalizedValue.isFinite else {
                throw XcircuiteParetoCandidateSetValidationError.nonFiniteMetricValue(
                    metricID: metricID,
                    field: "normalizedValue"
                )
            }
            try XcircuiteParetoCandidateSet.validateNonEmpty(direction, field: "direction")
            if let unit {
                try XcircuiteParetoCandidateSet.validateNonEmpty(unit, field: "unit")
            }
        }
    }

    public struct Candidate: Codable, Sendable, Hashable {
        public var runID: String
        public var problemID: String?
        public var generatedAt: String
        public var candidateID: String
        public var sourceCandidateID: String?
        public var frontierRank: Int
        public var dominatedByCandidateIDs: [String]
        public var metrics: [Metric]
        public var gateStatuses: [String: String]
        public var rationale: String

        public init(
            runID: String,
            problemID: String? = nil,
            generatedAt: String,
            candidateID: String,
            sourceCandidateID: String? = nil,
            frontierRank: Int,
            dominatedByCandidateIDs: [String] = [],
            metrics: [Metric],
            gateStatuses: [String: String] = [:],
            rationale: String
        ) throws {
            try Self.validate(
                runID: runID,
                problemID: problemID,
                generatedAt: generatedAt,
                candidateID: candidateID,
                sourceCandidateID: sourceCandidateID,
                frontierRank: frontierRank,
                dominatedByCandidateIDs: dominatedByCandidateIDs,
                metrics: metrics,
                gateStatuses: gateStatuses,
                rationale: rationale
            )
            self.runID = runID
            self.problemID = problemID
            self.generatedAt = generatedAt
            self.candidateID = candidateID
            self.sourceCandidateID = sourceCandidateID
            self.frontierRank = frontierRank
            self.dominatedByCandidateIDs = dominatedByCandidateIDs
            self.metrics = metrics
            self.gateStatuses = gateStatuses
            self.rationale = rationale
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let runID = try container.decode(String.self, forKey: .runID)
            let problemID = try container.decodeIfPresent(String.self, forKey: .problemID)
            let generatedAt = try container.decode(String.self, forKey: .generatedAt)
            let candidateID = try container.decode(String.self, forKey: .candidateID)
            let sourceCandidateID = try container.decodeIfPresent(String.self, forKey: .sourceCandidateID)
            let frontierRank = try container.decode(Int.self, forKey: .frontierRank)
            let dominatedByCandidateIDs = try container.decode(
                [String].self,
                forKey: .dominatedByCandidateIDs
            )
            let metrics = try container.decode([Metric].self, forKey: .metrics)
            let gateStatuses = try container.decode([String: String].self, forKey: .gateStatuses)
            let rationale = try container.decode(String.self, forKey: .rationale)
            try self.init(
                runID: runID,
                problemID: problemID,
                generatedAt: generatedAt,
                candidateID: candidateID,
                sourceCandidateID: sourceCandidateID,
                frontierRank: frontierRank,
                dominatedByCandidateIDs: dominatedByCandidateIDs,
                metrics: metrics,
                gateStatuses: gateStatuses,
                rationale: rationale
            )
        }

        public func encode(to encoder: Encoder) throws {
            try Self.validate(
                runID: runID,
                problemID: problemID,
                generatedAt: generatedAt,
                candidateID: candidateID,
                sourceCandidateID: sourceCandidateID,
                frontierRank: frontierRank,
                dominatedByCandidateIDs: dominatedByCandidateIDs,
                metrics: metrics,
                gateStatuses: gateStatuses,
                rationale: rationale
            )
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(runID, forKey: .runID)
            try container.encodeIfPresent(problemID, forKey: .problemID)
            try container.encode(generatedAt, forKey: .generatedAt)
            try container.encode(candidateID, forKey: .candidateID)
            try container.encodeIfPresent(sourceCandidateID, forKey: .sourceCandidateID)
            try container.encode(frontierRank, forKey: .frontierRank)
            try container.encode(dominatedByCandidateIDs, forKey: .dominatedByCandidateIDs)
            try container.encode(metrics, forKey: .metrics)
            try container.encode(gateStatuses, forKey: .gateStatuses)
            try container.encode(rationale, forKey: .rationale)
        }

        private enum CodingKeys: String, CodingKey {
            case runID
            case problemID
            case generatedAt
            case candidateID
            case sourceCandidateID
            case frontierRank
            case dominatedByCandidateIDs
            case metrics
            case gateStatuses
            case rationale
        }

        private static func validate(
            runID: String,
            problemID: String?,
            generatedAt: String,
            candidateID: String,
            sourceCandidateID: String?,
            frontierRank: Int,
            dominatedByCandidateIDs: [String],
            metrics: [Metric],
            gateStatuses: [String: String],
            rationale: String
        ) throws {
            try XcircuiteParetoCandidateSet.validateIdentifier(runID, field: "candidate.runID")
            if let problemID {
                try XcircuiteParetoCandidateSet.validateIdentifier(problemID, field: "candidate.problemID")
            }
            try XcircuiteParetoCandidateSet.validateNonEmpty(generatedAt, field: "candidate.generatedAt")
            try XcircuiteParetoCandidateSet.validateIdentifier(candidateID, field: "candidateID")
            if let sourceCandidateID {
                try XcircuiteParetoCandidateSet.validateIdentifier(sourceCandidateID, field: "sourceCandidateID")
            }
            guard frontierRank > 0 else {
                throw XcircuiteParetoCandidateSetValidationError.invalidFrontierRank(
                    candidateID: candidateID,
                    rank: frontierRank
                )
            }
            try validateDominatedCandidateIDs(dominatedByCandidateIDs, candidateID: candidateID)
            try validateGateStatuses(gateStatuses, candidateID: candidateID)
            try XcircuiteParetoCandidateSet.validateNonEmpty(rationale, field: "candidate.rationale")
            _ = metrics
        }

        private static func validateDominatedCandidateIDs(
            _ dominatedByCandidateIDs: [String],
            candidateID: String
        ) throws {
            var seen: Set<String> = []
            for dominatedID in dominatedByCandidateIDs {
                try XcircuiteParetoCandidateSet.validateIdentifier(
                    dominatedID,
                    field: "dominatedByCandidateIDs"
                )
                guard dominatedID != candidateID else {
                    throw XcircuiteParetoCandidateSetValidationError.selfDominatedCandidateID(candidateID)
                }
                guard !seen.contains(dominatedID) else {
                    throw XcircuiteParetoCandidateSetValidationError.duplicateIdentifier(
                        field: "dominatedByCandidateIDs",
                        value: dominatedID
                    )
                }
                seen.insert(dominatedID)
            }
        }

        private static func validateGateStatuses(
            _ gateStatuses: [String: String],
            candidateID: String
        ) throws {
            for (gateID, status) in gateStatuses {
                do {
                    try XcircuiteParetoCandidateSet.validateIdentifier(gateID, field: "gateStatuses.gateID")
                    try XcircuiteParetoCandidateSet.validateNonEmpty(status, field: "gateStatuses.status")
                } catch {
                    throw XcircuiteParetoCandidateSetValidationError.invalidGateStatus(
                        candidateID: candidateID,
                        gateID: gateID,
                        status: status
                    )
                }
            }
        }
    }

    public var schemaVersion: Int
    public var runID: String
    public var problemID: String?
    public var generatedAt: String
    public var thresholdProfileArtifactID: String?
    public var costCalibrationArtifactID: String?
    public var sourceCandidateArtifactIDs: [String]
    public var candidates: [Candidate]
    public var selectedCandidateID: String?

    public init(
        schemaVersion: Int = 1,
        runID: String,
        problemID: String? = nil,
        generatedAt: String,
        thresholdProfileArtifactID: String? = nil,
        costCalibrationArtifactID: String? = nil,
        sourceCandidateArtifactIDs: [String] = [],
        candidates: [Candidate],
        selectedCandidateID: String? = nil
    ) throws {
        try Self.validate(
            schemaVersion: schemaVersion,
            runID: runID,
            problemID: problemID,
            generatedAt: generatedAt,
            thresholdProfileArtifactID: thresholdProfileArtifactID,
            costCalibrationArtifactID: costCalibrationArtifactID,
            sourceCandidateArtifactIDs: sourceCandidateArtifactIDs,
            candidates: candidates,
            selectedCandidateID: selectedCandidateID
        )
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.problemID = problemID
        self.generatedAt = generatedAt
        self.thresholdProfileArtifactID = thresholdProfileArtifactID
        self.costCalibrationArtifactID = costCalibrationArtifactID
        self.sourceCandidateArtifactIDs = sourceCandidateArtifactIDs
        self.candidates = candidates
        self.selectedCandidateID = selectedCandidateID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        let runID = try container.decode(String.self, forKey: .runID)
        let problemID = try container.decodeIfPresent(String.self, forKey: .problemID)
        let generatedAt = try container.decode(String.self, forKey: .generatedAt)
        let thresholdProfileArtifactID = try container.decodeIfPresent(
            String.self,
            forKey: .thresholdProfileArtifactID
        )
        let costCalibrationArtifactID = try container.decodeIfPresent(
            String.self,
            forKey: .costCalibrationArtifactID
        )
        let sourceCandidateArtifactIDs = try container.decode(
            [String].self,
            forKey: .sourceCandidateArtifactIDs
        )
        let candidates = try container.decode([Candidate].self, forKey: .candidates)
        let selectedCandidateID = try container.decodeIfPresent(String.self, forKey: .selectedCandidateID)
        try self.init(
            schemaVersion: schemaVersion,
            runID: runID,
            problemID: problemID,
            generatedAt: generatedAt,
            thresholdProfileArtifactID: thresholdProfileArtifactID,
            costCalibrationArtifactID: costCalibrationArtifactID,
            sourceCandidateArtifactIDs: sourceCandidateArtifactIDs,
            candidates: candidates,
            selectedCandidateID: selectedCandidateID
        )
    }

    public func encode(to encoder: Encoder) throws {
        try Self.validate(
            schemaVersion: schemaVersion,
            runID: runID,
            problemID: problemID,
            generatedAt: generatedAt,
            thresholdProfileArtifactID: thresholdProfileArtifactID,
            costCalibrationArtifactID: costCalibrationArtifactID,
            sourceCandidateArtifactIDs: sourceCandidateArtifactIDs,
            candidates: candidates,
            selectedCandidateID: selectedCandidateID
        )
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(runID, forKey: .runID)
        try container.encodeIfPresent(problemID, forKey: .problemID)
        try container.encode(generatedAt, forKey: .generatedAt)
        try container.encodeIfPresent(thresholdProfileArtifactID, forKey: .thresholdProfileArtifactID)
        try container.encodeIfPresent(costCalibrationArtifactID, forKey: .costCalibrationArtifactID)
        try container.encode(sourceCandidateArtifactIDs, forKey: .sourceCandidateArtifactIDs)
        try container.encode(candidates, forKey: .candidates)
        try container.encodeIfPresent(selectedCandidateID, forKey: .selectedCandidateID)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case runID
        case problemID
        case generatedAt
        case thresholdProfileArtifactID
        case costCalibrationArtifactID
        case sourceCandidateArtifactIDs
        case candidates
        case selectedCandidateID
    }

    private static func validate(
        schemaVersion: Int,
        runID: String,
        problemID: String?,
        generatedAt: String,
        thresholdProfileArtifactID: String?,
        costCalibrationArtifactID: String?,
        sourceCandidateArtifactIDs: [String],
        candidates: [Candidate],
        selectedCandidateID: String?
    ) throws {
        guard schemaVersion == 1 else {
            throw XcircuiteParetoCandidateSetValidationError.unsupportedSchemaVersion(schemaVersion)
        }
        try validateIdentifier(runID, field: "runID")
        if let problemID {
            try validateIdentifier(problemID, field: "problemID")
        }
        try validateNonEmpty(generatedAt, field: "generatedAt")
        try validateOptionalIdentifier(thresholdProfileArtifactID, field: "thresholdProfileArtifactID")
        try validateOptionalIdentifier(costCalibrationArtifactID, field: "costCalibrationArtifactID")
        try validateUniqueIdentifiers(sourceCandidateArtifactIDs, field: "sourceCandidateArtifactIDs")
        try validateCandidates(candidates, runID: runID, problemID: problemID)
        if let selectedCandidateID {
            try validateIdentifier(selectedCandidateID, field: "selectedCandidateID")
            let candidateIDs = Set(candidates.map(\.candidateID))
            guard candidateIDs.contains(selectedCandidateID) else {
                throw XcircuiteParetoCandidateSetValidationError.unknownSelectedCandidateID(selectedCandidateID)
            }
        }
    }

    private static func validateCandidates(
        _ candidates: [Candidate],
        runID: String,
        problemID: String?
    ) throws {
        var seen: Set<String> = []
        for candidate in candidates {
            guard candidate.runID == runID else {
                throw XcircuiteParetoCandidateSetValidationError.candidateRunMismatch(
                    candidateID: candidate.candidateID,
                    expected: runID,
                    actual: candidate.runID
                )
            }
            if let candidateProblemID = candidate.problemID {
                if let problemID {
                    guard candidateProblemID == problemID else {
                        throw XcircuiteParetoCandidateSetValidationError.candidateProblemMismatch(
                            candidateID: candidate.candidateID,
                            expected: problemID,
                            actual: candidateProblemID
                        )
                    }
                } else {
                    throw XcircuiteParetoCandidateSetValidationError.candidateProblemUnexpected(
                        candidateID: candidate.candidateID,
                        actual: candidateProblemID
                    )
                }
            }
            guard !seen.contains(candidate.candidateID) else {
                throw XcircuiteParetoCandidateSetValidationError.duplicateIdentifier(
                    field: "candidateID",
                    value: candidate.candidateID
                )
            }
            seen.insert(candidate.candidateID)
        }
    }

    private static func validateUniqueIdentifiers(
        _ values: [String],
        field: String
    ) throws {
        var seen: Set<String> = []
        for value in values {
            try validateIdentifier(value, field: field)
            guard !seen.contains(value) else {
                throw XcircuiteParetoCandidateSetValidationError.duplicateIdentifier(
                    field: field,
                    value: value
                )
            }
            seen.insert(value)
        }
    }

    private static func validateOptionalIdentifier(_ value: String?, field: String) throws {
        guard let value else {
            return
        }
        try validateIdentifier(value, field: field)
    }

    fileprivate static func validateIdentifier(_ value: String, field: String) throws {
        do {
            try XcircuiteIdentifierValidator().validate(value, kind: .artifactID)
        } catch {
            throw XcircuiteParetoCandidateSetValidationError.invalidIdentifier(field: field, value: value)
        }
    }

    fileprivate static func validateNonEmpty(_ value: String, field: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw XcircuiteParetoCandidateSetValidationError.emptyField(field)
        }
    }
}
