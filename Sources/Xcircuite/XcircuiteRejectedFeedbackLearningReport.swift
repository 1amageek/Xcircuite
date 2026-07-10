import Foundation
import XcircuitePackage

public struct XcircuiteRejectedFeedbackLearningReport: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var runID: String
    public var problemID: String?
    public var generatedAt: String
    public var numericRepairLoopPath: String
    public var rejectedPlansPath: String?
    public var rejectedRecordCount: Int
    public var selectionTraceArtifactIDs: [String]
    public var impactedCandidateCount: Int
    public var penalizedCandidateCount: Int
    public var rankChangedCandidateCount: Int
    public var scoreDeltaCandidateCount: Int
    public var retainedFailedGateIDs: [String]
    public var retainedDiagnosticCodes: [String]
    public var feedbackImpacts: [FeedbackImpact]
    public var diagnostics: [String]

    public init(
        schemaVersion: Int = 1,
        runID: String,
        problemID: String?,
        generatedAt: String,
        numericRepairLoopPath: String,
        rejectedPlansPath: String?,
        rejectedRecordCount: Int,
        selectionTraceArtifactIDs: [String],
        impactedCandidateCount: Int,
        penalizedCandidateCount: Int,
        rankChangedCandidateCount: Int,
        scoreDeltaCandidateCount: Int,
        retainedFailedGateIDs: [String],
        retainedDiagnosticCodes: [String],
        feedbackImpacts: [FeedbackImpact],
        diagnostics: [String] = []
    ) throws {
        try Self.validate(
            schemaVersion: schemaVersion,
            runID: runID,
            problemID: problemID,
            generatedAt: generatedAt,
            numericRepairLoopPath: numericRepairLoopPath,
            rejectedPlansPath: rejectedPlansPath,
            rejectedRecordCount: rejectedRecordCount,
            selectionTraceArtifactIDs: selectionTraceArtifactIDs,
            impactedCandidateCount: impactedCandidateCount,
            penalizedCandidateCount: penalizedCandidateCount,
            rankChangedCandidateCount: rankChangedCandidateCount,
            scoreDeltaCandidateCount: scoreDeltaCandidateCount,
            retainedFailedGateIDs: retainedFailedGateIDs,
            retainedDiagnosticCodes: retainedDiagnosticCodes,
            feedbackImpacts: feedbackImpacts,
            diagnostics: diagnostics
        )
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.problemID = problemID
        self.generatedAt = generatedAt
        self.numericRepairLoopPath = numericRepairLoopPath
        self.rejectedPlansPath = rejectedPlansPath
        self.rejectedRecordCount = rejectedRecordCount
        self.selectionTraceArtifactIDs = selectionTraceArtifactIDs
        self.impactedCandidateCount = impactedCandidateCount
        self.penalizedCandidateCount = penalizedCandidateCount
        self.rankChangedCandidateCount = rankChangedCandidateCount
        self.scoreDeltaCandidateCount = scoreDeltaCandidateCount
        self.retainedFailedGateIDs = retainedFailedGateIDs
        self.retainedDiagnosticCodes = retainedDiagnosticCodes
        self.feedbackImpacts = feedbackImpacts
        self.diagnostics = diagnostics
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        let runID = try container.decode(String.self, forKey: .runID)
        let problemID = try container.decodeIfPresent(String.self, forKey: .problemID)
        let generatedAt = try container.decode(String.self, forKey: .generatedAt)
        let numericRepairLoopPath = try container.decode(String.self, forKey: .numericRepairLoopPath)
        let rejectedPlansPath = try container.decodeIfPresent(String.self, forKey: .rejectedPlansPath)
        let rejectedRecordCount = try container.decode(Int.self, forKey: .rejectedRecordCount)
        let selectionTraceArtifactIDs = try container.decode([String].self, forKey: .selectionTraceArtifactIDs)
        let impactedCandidateCount = try container.decode(Int.self, forKey: .impactedCandidateCount)
        let penalizedCandidateCount = try container.decode(Int.self, forKey: .penalizedCandidateCount)
        let rankChangedCandidateCount = try container.decode(Int.self, forKey: .rankChangedCandidateCount)
        let scoreDeltaCandidateCount = try container.decode(Int.self, forKey: .scoreDeltaCandidateCount)
        let retainedFailedGateIDs = try container.decode([String].self, forKey: .retainedFailedGateIDs)
        let retainedDiagnosticCodes = try container.decode([String].self, forKey: .retainedDiagnosticCodes)
        let feedbackImpacts = try container.decode([FeedbackImpact].self, forKey: .feedbackImpacts)
        let diagnostics = try container.decode([String].self, forKey: .diagnostics)
        try self.init(
            schemaVersion: schemaVersion,
            runID: runID,
            problemID: problemID,
            generatedAt: generatedAt,
            numericRepairLoopPath: numericRepairLoopPath,
            rejectedPlansPath: rejectedPlansPath,
            rejectedRecordCount: rejectedRecordCount,
            selectionTraceArtifactIDs: selectionTraceArtifactIDs,
            impactedCandidateCount: impactedCandidateCount,
            penalizedCandidateCount: penalizedCandidateCount,
            rankChangedCandidateCount: rankChangedCandidateCount,
            scoreDeltaCandidateCount: scoreDeltaCandidateCount,
            retainedFailedGateIDs: retainedFailedGateIDs,
            retainedDiagnosticCodes: retainedDiagnosticCodes,
            feedbackImpacts: feedbackImpacts,
            diagnostics: diagnostics
        )
    }

    public func encode(to encoder: Encoder) throws {
        try Self.validate(
            schemaVersion: schemaVersion,
            runID: runID,
            problemID: problemID,
            generatedAt: generatedAt,
            numericRepairLoopPath: numericRepairLoopPath,
            rejectedPlansPath: rejectedPlansPath,
            rejectedRecordCount: rejectedRecordCount,
            selectionTraceArtifactIDs: selectionTraceArtifactIDs,
            impactedCandidateCount: impactedCandidateCount,
            penalizedCandidateCount: penalizedCandidateCount,
            rankChangedCandidateCount: rankChangedCandidateCount,
            scoreDeltaCandidateCount: scoreDeltaCandidateCount,
            retainedFailedGateIDs: retainedFailedGateIDs,
            retainedDiagnosticCodes: retainedDiagnosticCodes,
            feedbackImpacts: feedbackImpacts,
            diagnostics: diagnostics
        )
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(runID, forKey: .runID)
        try container.encodeIfPresent(problemID, forKey: .problemID)
        try container.encode(generatedAt, forKey: .generatedAt)
        try container.encode(numericRepairLoopPath, forKey: .numericRepairLoopPath)
        try container.encodeIfPresent(rejectedPlansPath, forKey: .rejectedPlansPath)
        try container.encode(rejectedRecordCount, forKey: .rejectedRecordCount)
        try container.encode(selectionTraceArtifactIDs, forKey: .selectionTraceArtifactIDs)
        try container.encode(impactedCandidateCount, forKey: .impactedCandidateCount)
        try container.encode(penalizedCandidateCount, forKey: .penalizedCandidateCount)
        try container.encode(rankChangedCandidateCount, forKey: .rankChangedCandidateCount)
        try container.encode(scoreDeltaCandidateCount, forKey: .scoreDeltaCandidateCount)
        try container.encode(retainedFailedGateIDs, forKey: .retainedFailedGateIDs)
        try container.encode(retainedDiagnosticCodes, forKey: .retainedDiagnosticCodes)
        try container.encode(feedbackImpacts, forKey: .feedbackImpacts)
        try container.encode(diagnostics, forKey: .diagnostics)
    }

    public struct FeedbackImpact: Codable, Sendable, Hashable {
        public var iterationIndex: Int
        public var candidateID: String
        public var feedbackFreeRank: Int
        public var feedbackAwareRank: Int
        public var rankDelta: Int
        public var baseCost: Double
        public var feedbackPenalty: Double
        public var totalScore: Double
        public var feedbackStatuses: [String]
        public var failedGateIDs: [String]
        public var diagnosticCodes: [String]
        public var penaltyComponents: [XcircuiteParameterCandidateFeedbackPenaltyComponent]
        public var sourceRejectionIDs: [String]
        public var sourcePlanIDs: [String]

        public init(
            iterationIndex: Int,
            candidateID: String,
            feedbackFreeRank: Int,
            feedbackAwareRank: Int,
            rankDelta: Int,
            baseCost: Double,
            feedbackPenalty: Double,
            totalScore: Double,
            feedbackStatuses: [String],
            failedGateIDs: [String],
            diagnosticCodes: [String],
            penaltyComponents: [XcircuiteParameterCandidateFeedbackPenaltyComponent],
            sourceRejectionIDs: [String],
            sourcePlanIDs: [String]
        ) throws {
            try Self.validate(
                iterationIndex: iterationIndex,
                candidateID: candidateID,
                feedbackFreeRank: feedbackFreeRank,
                feedbackAwareRank: feedbackAwareRank,
                rankDelta: rankDelta,
                baseCost: baseCost,
                feedbackPenalty: feedbackPenalty,
                totalScore: totalScore,
                feedbackStatuses: feedbackStatuses,
                failedGateIDs: failedGateIDs,
                diagnosticCodes: diagnosticCodes,
                penaltyComponents: penaltyComponents,
                sourceRejectionIDs: sourceRejectionIDs,
                sourcePlanIDs: sourcePlanIDs
            )
            self.iterationIndex = iterationIndex
            self.candidateID = candidateID
            self.feedbackFreeRank = feedbackFreeRank
            self.feedbackAwareRank = feedbackAwareRank
            self.rankDelta = rankDelta
            self.baseCost = baseCost
            self.feedbackPenalty = feedbackPenalty
            self.totalScore = totalScore
            self.feedbackStatuses = feedbackStatuses
            self.failedGateIDs = failedGateIDs
            self.diagnosticCodes = diagnosticCodes
            self.penaltyComponents = penaltyComponents
            self.sourceRejectionIDs = sourceRejectionIDs
            self.sourcePlanIDs = sourcePlanIDs
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let iterationIndex = try container.decode(Int.self, forKey: .iterationIndex)
            let candidateID = try container.decode(String.self, forKey: .candidateID)
            let feedbackFreeRank = try container.decode(Int.self, forKey: .feedbackFreeRank)
            let feedbackAwareRank = try container.decode(Int.self, forKey: .feedbackAwareRank)
            let rankDelta = try container.decode(Int.self, forKey: .rankDelta)
            let baseCost = try container.decode(Double.self, forKey: .baseCost)
            let feedbackPenalty = try container.decode(Double.self, forKey: .feedbackPenalty)
            let totalScore = try container.decode(Double.self, forKey: .totalScore)
            let feedbackStatuses = try container.decode([String].self, forKey: .feedbackStatuses)
            let failedGateIDs = try container.decode([String].self, forKey: .failedGateIDs)
            let diagnosticCodes = try container.decode([String].self, forKey: .diagnosticCodes)
            let penaltyComponents = try container.decode(
                [XcircuiteParameterCandidateFeedbackPenaltyComponent].self,
                forKey: .penaltyComponents
            )
            let sourceRejectionIDs = try container.decode([String].self, forKey: .sourceRejectionIDs)
            let sourcePlanIDs = try container.decode([String].self, forKey: .sourcePlanIDs)
            try self.init(
                iterationIndex: iterationIndex,
                candidateID: candidateID,
                feedbackFreeRank: feedbackFreeRank,
                feedbackAwareRank: feedbackAwareRank,
                rankDelta: rankDelta,
                baseCost: baseCost,
                feedbackPenalty: feedbackPenalty,
                totalScore: totalScore,
                feedbackStatuses: feedbackStatuses,
                failedGateIDs: failedGateIDs,
                diagnosticCodes: diagnosticCodes,
                penaltyComponents: penaltyComponents,
                sourceRejectionIDs: sourceRejectionIDs,
                sourcePlanIDs: sourcePlanIDs
            )
        }

        public func encode(to encoder: Encoder) throws {
            try Self.validate(
                iterationIndex: iterationIndex,
                candidateID: candidateID,
                feedbackFreeRank: feedbackFreeRank,
                feedbackAwareRank: feedbackAwareRank,
                rankDelta: rankDelta,
                baseCost: baseCost,
                feedbackPenalty: feedbackPenalty,
                totalScore: totalScore,
                feedbackStatuses: feedbackStatuses,
                failedGateIDs: failedGateIDs,
                diagnosticCodes: diagnosticCodes,
                penaltyComponents: penaltyComponents,
                sourceRejectionIDs: sourceRejectionIDs,
                sourcePlanIDs: sourcePlanIDs
            )
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(iterationIndex, forKey: .iterationIndex)
            try container.encode(candidateID, forKey: .candidateID)
            try container.encode(feedbackFreeRank, forKey: .feedbackFreeRank)
            try container.encode(feedbackAwareRank, forKey: .feedbackAwareRank)
            try container.encode(rankDelta, forKey: .rankDelta)
            try container.encode(baseCost, forKey: .baseCost)
            try container.encode(feedbackPenalty, forKey: .feedbackPenalty)
            try container.encode(totalScore, forKey: .totalScore)
            try container.encode(feedbackStatuses, forKey: .feedbackStatuses)
            try container.encode(failedGateIDs, forKey: .failedGateIDs)
            try container.encode(diagnosticCodes, forKey: .diagnosticCodes)
            try container.encode(penaltyComponents, forKey: .penaltyComponents)
            try container.encode(sourceRejectionIDs, forKey: .sourceRejectionIDs)
            try container.encode(sourcePlanIDs, forKey: .sourcePlanIDs)
        }

        private enum CodingKeys: String, CodingKey {
            case iterationIndex
            case candidateID
            case feedbackFreeRank
            case feedbackAwareRank
            case rankDelta
            case baseCost
            case feedbackPenalty
            case totalScore
            case feedbackStatuses
            case failedGateIDs
            case diagnosticCodes
            case penaltyComponents
            case sourceRejectionIDs
            case sourcePlanIDs
        }

        private static func validate(
            iterationIndex: Int,
            candidateID: String,
            feedbackFreeRank: Int,
            feedbackAwareRank: Int,
            rankDelta: Int,
            baseCost: Double,
            feedbackPenalty: Double,
            totalScore: Double,
            feedbackStatuses: [String],
            failedGateIDs: [String],
            diagnosticCodes: [String],
            penaltyComponents: [XcircuiteParameterCandidateFeedbackPenaltyComponent],
            sourceRejectionIDs: [String],
            sourcePlanIDs: [String]
        ) throws {
            try XcircuiteRejectedFeedbackLearningReport.validateNonNegativeCount(
                iterationIndex,
                field: "feedbackImpacts.iterationIndex"
            )
            try XcircuiteRejectedFeedbackLearningReport.validateIdentifier(
                candidateID,
                field: "feedbackImpacts.candidateID"
            )
            try validateRank(feedbackFreeRank, field: "feedbackFreeRank", candidateID: candidateID)
            try validateRank(feedbackAwareRank, field: "feedbackAwareRank", candidateID: candidateID)
            let expectedRankDelta = feedbackAwareRank - feedbackFreeRank
            guard rankDelta == expectedRankDelta else {
                throw XcircuiteRejectedFeedbackLearningReportValidationError.rankDeltaMismatch(
                    candidateID: candidateID,
                    expected: expectedRankDelta,
                    actual: rankDelta
                )
            }
            try validateFiniteNonNegative(baseCost, field: "baseCost", candidateID: candidateID)
            try validateFiniteNonNegative(feedbackPenalty, field: "feedbackPenalty", candidateID: candidateID)
            try validateFiniteNonNegative(totalScore, field: "totalScore", candidateID: candidateID)
            try XcircuiteRejectedFeedbackLearningReport.validateUniqueIdentifiers(
                failedGateIDs,
                field: "feedbackImpacts.failedGateIDs"
            )
            try XcircuiteRejectedFeedbackLearningReport.validateUniqueIdentifiers(
                diagnosticCodes,
                field: "feedbackImpacts.diagnosticCodes"
            )
            try XcircuiteRejectedFeedbackLearningReport.validateUniqueNonEmptyStrings(
                sourceRejectionIDs,
                field: "feedbackImpacts.sourceRejectionIDs"
            )
            try XcircuiteRejectedFeedbackLearningReport.validateUniqueNonEmptyStrings(
                sourcePlanIDs,
                field: "feedbackImpacts.sourcePlanIDs"
            )
            try XcircuiteRejectedFeedbackLearningReport.validateUniqueNonEmptyStrings(
                feedbackStatuses,
                field: "feedbackImpacts.feedbackStatuses"
            )
            try validatePenaltyComponents(penaltyComponents, candidateID: candidateID)
        }

        private static func validateRank(_ value: Int, field: String, candidateID: String) throws {
            guard value > 0 else {
                throw XcircuiteRejectedFeedbackLearningReportValidationError.invalidRank(
                    field: field,
                    candidateID: candidateID,
                    value: value
                )
            }
        }

        private static func validateFiniteNonNegative(_ value: Double, field: String, candidateID: String) throws {
            guard value.isFinite else {
                throw XcircuiteRejectedFeedbackLearningReportValidationError.nonFiniteValue(
                    field: field,
                    candidateID: candidateID,
                    value: value
                )
            }
            guard value >= 0 else {
                throw XcircuiteRejectedFeedbackLearningReportValidationError.negativeValue(
                    field: field,
                    candidateID: candidateID,
                    value: value
                )
            }
        }

        private static func validatePenaltyComponents(
            _ components: [XcircuiteParameterCandidateFeedbackPenaltyComponent],
            candidateID: String
        ) throws {
            var seen: Set<String> = []
            for component in components {
                try XcircuiteRejectedFeedbackLearningReport.validateNonEmpty(
                    component.componentID,
                    field: "penaltyComponents.componentID"
                )
                guard !seen.contains(component.componentID) else {
                    throw XcircuiteRejectedFeedbackLearningReportValidationError.duplicateIdentifier(
                        field: "penaltyComponents.componentID",
                        value: component.componentID
                    )
                }
                seen.insert(component.componentID)
                try XcircuiteRejectedFeedbackLearningReport.validateNonNegativeCount(
                    component.itemCount,
                    field: "penaltyComponents.itemCount"
                )
                try validateFiniteNonNegative(
                    component.unitPenalty,
                    field: "penaltyComponents.unitPenalty",
                    candidateID: candidateID
                )
                if let cap = component.cap {
                    try validateFiniteNonNegative(
                        cap,
                        field: "penaltyComponents.cap",
                        candidateID: candidateID
                    )
                }
                try validateFiniteNonNegative(
                    component.appliedPenalty,
                    field: "penaltyComponents.appliedPenalty",
                    candidateID: candidateID
                )
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case runID
        case problemID
        case generatedAt
        case numericRepairLoopPath
        case rejectedPlansPath
        case rejectedRecordCount
        case selectionTraceArtifactIDs
        case impactedCandidateCount
        case penalizedCandidateCount
        case rankChangedCandidateCount
        case scoreDeltaCandidateCount
        case retainedFailedGateIDs
        case retainedDiagnosticCodes
        case feedbackImpacts
        case diagnostics
    }

    private static func validate(
        schemaVersion: Int,
        runID: String,
        problemID: String?,
        generatedAt: String,
        numericRepairLoopPath: String,
        rejectedPlansPath: String?,
        rejectedRecordCount: Int,
        selectionTraceArtifactIDs: [String],
        impactedCandidateCount: Int,
        penalizedCandidateCount: Int,
        rankChangedCandidateCount: Int,
        scoreDeltaCandidateCount: Int,
        retainedFailedGateIDs: [String],
        retainedDiagnosticCodes: [String],
        feedbackImpacts: [FeedbackImpact],
        diagnostics: [String]
    ) throws {
        guard schemaVersion == 1 else {
            throw XcircuiteRejectedFeedbackLearningReportValidationError.unsupportedSchemaVersion(schemaVersion)
        }
        try validateRunID(runID)
        if let problemID {
            try validateIdentifier(problemID, field: "problemID")
        }
        try validateNonEmpty(generatedAt, field: "generatedAt")
        try validateProjectRelativePath(numericRepairLoopPath, field: "numericRepairLoopPath")
        if let rejectedPlansPath {
            try validateProjectRelativePath(rejectedPlansPath, field: "rejectedPlansPath")
        }
        try validateNonNegativeCount(rejectedRecordCount, field: "rejectedRecordCount")
        try validateUniqueIdentifiers(selectionTraceArtifactIDs, field: "selectionTraceArtifactIDs")
        try validateNonNegativeCount(impactedCandidateCount, field: "impactedCandidateCount")
        try validateNonNegativeCount(penalizedCandidateCount, field: "penalizedCandidateCount")
        try validateNonNegativeCount(rankChangedCandidateCount, field: "rankChangedCandidateCount")
        try validateNonNegativeCount(scoreDeltaCandidateCount, field: "scoreDeltaCandidateCount")
        try validateUniqueIdentifiers(retainedFailedGateIDs, field: "retainedFailedGateIDs")
        try validateUniqueIdentifiers(retainedDiagnosticCodes, field: "retainedDiagnosticCodes")
        try validateUniqueNonEmptyStrings(diagnostics, field: "diagnostics")
        try validateCounts(
            feedbackImpacts: feedbackImpacts,
            impactedCandidateCount: impactedCandidateCount,
            penalizedCandidateCount: penalizedCandidateCount,
            rankChangedCandidateCount: rankChangedCandidateCount,
            scoreDeltaCandidateCount: scoreDeltaCandidateCount
        )
    }

    private static func validateCounts(
        feedbackImpacts: [FeedbackImpact],
        impactedCandidateCount: Int,
        penalizedCandidateCount: Int,
        rankChangedCandidateCount: Int,
        scoreDeltaCandidateCount: Int
    ) throws {
        try validateCount("impactedCandidateCount", expected: feedbackImpacts.count, actual: impactedCandidateCount)
        try validateCount(
            "penalizedCandidateCount",
            expected: feedbackImpacts.filter { $0.feedbackPenalty > 0 }.count,
            actual: penalizedCandidateCount
        )
        try validateCount(
            "rankChangedCandidateCount",
            expected: feedbackImpacts.filter { $0.rankDelta != 0 }.count,
            actual: rankChangedCandidateCount
        )
        try validateCount(
            "scoreDeltaCandidateCount",
            expected: feedbackImpacts.filter { $0.feedbackPenalty > 0 || !$0.penaltyComponents.isEmpty }.count,
            actual: scoreDeltaCandidateCount
        )
    }

    private static func validateCount(_ field: String, expected: Int, actual: Int) throws {
        guard expected == actual else {
            throw XcircuiteRejectedFeedbackLearningReportValidationError.countMismatch(
                field: field,
                expected: expected,
                actual: actual
            )
        }
    }

    fileprivate static func validateRunID(_ value: String) throws {
        do {
            try XcircuiteIdentifierValidator().validate(value, kind: .runID)
        } catch {
            throw XcircuiteRejectedFeedbackLearningReportValidationError.invalidIdentifier(
                field: "runID",
                value: value
            )
        }
    }

    fileprivate static func validateIdentifier(_ value: String, field: String) throws {
        do {
            try XcircuiteIdentifierValidator().validate(value, kind: .artifactID)
        } catch {
            throw XcircuiteRejectedFeedbackLearningReportValidationError.invalidIdentifier(
                field: field,
                value: value
            )
        }
    }

    fileprivate static func validateUniqueIdentifiers(_ values: [String], field: String) throws {
        var seen: Set<String> = []
        for value in values {
            try validateIdentifier(value, field: field)
            guard !seen.contains(value) else {
                throw XcircuiteRejectedFeedbackLearningReportValidationError.duplicateIdentifier(
                    field: field,
                    value: value
                )
            }
            seen.insert(value)
        }
    }

    fileprivate static func validateUniqueNonEmptyStrings(_ values: [String], field: String) throws {
        var seen: Set<String> = []
        for value in values {
            try validateNonEmpty(value, field: field)
            guard !seen.contains(value) else {
                throw XcircuiteRejectedFeedbackLearningReportValidationError.duplicateIdentifier(
                    field: field,
                    value: value
                )
            }
            seen.insert(value)
        }
    }

    fileprivate static func validateNonEmpty(_ value: String, field: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw XcircuiteRejectedFeedbackLearningReportValidationError.emptyField(field)
        }
    }

    fileprivate static func validateNonNegativeCount(_ value: Int, field: String) throws {
        guard value >= 0 else {
            throw XcircuiteRejectedFeedbackLearningReportValidationError.negativeCount(field: field, value: value)
        }
    }

    private static func validateProjectRelativePath(_ path: String, field: String) throws {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        let isUnsafe = path.isEmpty
            || path == "."
            || path.hasPrefix("/")
            || path.hasPrefix("~")
            || components.contains("..")
        guard !isUnsafe else {
            throw XcircuiteRejectedFeedbackLearningReportValidationError.invalidProjectRelativePath(
                field: field,
                path: path
            )
        }
    }
}
