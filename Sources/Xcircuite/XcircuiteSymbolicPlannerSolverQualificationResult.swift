import ToolQualification
import XcircuitePackage

public struct XcircuiteSymbolicPlannerSolverQualificationResult: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var status: String
    public var runID: String
    public var toolID: String
    public var policyID: String
    public var expectedActionIDs: [String]
    public var observedActionIDs: [String]
    public var requireGoalCoverage: Bool
    public var requireOptimality: Bool
    public var maximumSolverCost: Double?
    public var requireNativeCertificate: Bool
    public var requireProofValidation: Bool
    public var goalCoverageStatus: String?
    public var missingGoalAtoms: [String]
    public var nativeCertificate: XcircuiteSymbolicPlannerSolverCertificateParseResult?
    public var solverMetadata: XcircuiteSymbolicPlannerSolverMetadata?
    public var planCostEvaluation: XcircuiteSymbolicPlannerPlanCostEvaluation?
    public var planReplayValidation: XcircuiteSymbolicPlannerPlanReplayValidation?
    public var proofValidation: XcircuiteSymbolicPlannerProofValidation?
    public var solverResult: XcircuiteSymbolicPlannerSolverResult
    public var planReplayValidationArtifact: XcircuiteFileReference?
    public var proofValidationArtifact: XcircuiteFileReference?
    public var nativeCertificateArtifact: XcircuiteFileReference?
    public var planVerificationArtifact: XcircuiteFileReference?
    public var qualificationArtifact: XcircuiteFileReference?
    public var toolHealth: ToolHealthCheckResult
    public var diagnostics: [XcircuiteSymbolicPlannerSolverDiagnostic]

    func attachingQualificationArtifact(
        _ artifact: XcircuiteFileReference
    ) -> XcircuiteSymbolicPlannerSolverQualificationResult {
        var result = self
        result.qualificationArtifact = artifact
        result.toolHealth.evidence = result.toolHealth.evidence.map { evidence in
            guard evidence.qualification != nil else {
                return evidence
            }
            var updated = evidence
            updated.artifact = artifact
            return updated
        }
        return result
    }

    func detachingQualificationArtifactReferencesForPersistence()
        -> XcircuiteSymbolicPlannerSolverQualificationResult
    {
        var result = self
        result.qualificationArtifact = nil
        result.toolHealth.evidence = result.toolHealth.evidence.map { evidence in
            guard evidence.qualification != nil else {
                return evidence
            }
            var updated = evidence
            updated.artifact = nil
            return updated
        }
        return result
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case status
        case runID
        case toolID
        case policyID
        case expectedActionIDs
        case observedActionIDs
        case requireGoalCoverage
        case requireOptimality
        case maximumSolverCost
        case requireNativeCertificate
        case requireProofValidation
        case goalCoverageStatus
        case missingGoalAtoms
        case nativeCertificate
        case solverMetadata
        case planCostEvaluation
        case planReplayValidation
        case proofValidation
        case solverResult
        case planReplayValidationArtifact
        case proofValidationArtifact
        case nativeCertificateArtifact
        case planVerificationArtifact
        case qualificationArtifact
        case toolHealth
        case diagnostics
    }

    public init(
        schemaVersion: Int = 1,
        status: String,
        runID: String,
        toolID: String,
        policyID: String,
        expectedActionIDs: [String],
        observedActionIDs: [String],
        requireGoalCoverage: Bool,
        requireOptimality: Bool = false,
        maximumSolverCost: Double? = nil,
        requireNativeCertificate: Bool = false,
        requireProofValidation: Bool = false,
        goalCoverageStatus: String?,
        missingGoalAtoms: [String],
        nativeCertificate: XcircuiteSymbolicPlannerSolverCertificateParseResult? = nil,
        solverMetadata: XcircuiteSymbolicPlannerSolverMetadata? = nil,
        planCostEvaluation: XcircuiteSymbolicPlannerPlanCostEvaluation? = nil,
        planReplayValidation: XcircuiteSymbolicPlannerPlanReplayValidation? = nil,
        proofValidation: XcircuiteSymbolicPlannerProofValidation? = nil,
        solverResult: XcircuiteSymbolicPlannerSolverResult,
        planReplayValidationArtifact: XcircuiteFileReference? = nil,
        proofValidationArtifact: XcircuiteFileReference? = nil,
        nativeCertificateArtifact: XcircuiteFileReference? = nil,
        planVerificationArtifact: XcircuiteFileReference?,
        qualificationArtifact: XcircuiteFileReference? = nil,
        toolHealth: ToolHealthCheckResult,
        diagnostics: [XcircuiteSymbolicPlannerSolverDiagnostic]
    ) {
        self.schemaVersion = schemaVersion
        self.status = status
        self.runID = runID
        self.toolID = toolID
        self.policyID = policyID
        self.expectedActionIDs = expectedActionIDs
        self.observedActionIDs = observedActionIDs
        self.requireGoalCoverage = requireGoalCoverage
        self.requireOptimality = requireOptimality
        self.maximumSolverCost = maximumSolverCost
        self.requireNativeCertificate = requireNativeCertificate
        self.requireProofValidation = requireProofValidation
        self.goalCoverageStatus = goalCoverageStatus
        self.missingGoalAtoms = missingGoalAtoms
        self.nativeCertificate = nativeCertificate
        self.solverMetadata = solverMetadata
        self.planCostEvaluation = planCostEvaluation
        self.planReplayValidation = planReplayValidation
        self.proofValidation = proofValidation
        self.solverResult = solverResult
        self.planReplayValidationArtifact = planReplayValidationArtifact
        self.proofValidationArtifact = proofValidationArtifact
        self.nativeCertificateArtifact = nativeCertificateArtifact
        self.planVerificationArtifact = planVerificationArtifact
        self.qualificationArtifact = qualificationArtifact
        self.toolHealth = toolHealth
        self.diagnostics = diagnostics
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            schemaVersion: try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1,
            status: try container.decode(String.self, forKey: .status),
            runID: try container.decode(String.self, forKey: .runID),
            toolID: try container.decode(String.self, forKey: .toolID),
            policyID: try container.decode(String.self, forKey: .policyID),
            expectedActionIDs: try container.decodeIfPresent([String].self, forKey: .expectedActionIDs) ?? [],
            observedActionIDs: try container.decodeIfPresent([String].self, forKey: .observedActionIDs) ?? [],
            requireGoalCoverage: try container.decodeIfPresent(Bool.self, forKey: .requireGoalCoverage) ?? true,
            requireOptimality: try container.decodeIfPresent(Bool.self, forKey: .requireOptimality) ?? false,
            maximumSolverCost: try container.decodeIfPresent(Double.self, forKey: .maximumSolverCost),
            requireNativeCertificate: try container.decodeIfPresent(Bool.self, forKey: .requireNativeCertificate) ?? false,
            requireProofValidation: try container.decodeIfPresent(Bool.self, forKey: .requireProofValidation) ?? false,
            goalCoverageStatus: try container.decodeIfPresent(String.self, forKey: .goalCoverageStatus),
            missingGoalAtoms: try container.decodeIfPresent([String].self, forKey: .missingGoalAtoms) ?? [],
            nativeCertificate: try container.decodeIfPresent(
                XcircuiteSymbolicPlannerSolverCertificateParseResult.self,
                forKey: .nativeCertificate
            ),
            solverMetadata: try container.decodeIfPresent(
                XcircuiteSymbolicPlannerSolverMetadata.self,
                forKey: .solverMetadata
            ),
            planCostEvaluation: try container.decodeIfPresent(
                XcircuiteSymbolicPlannerPlanCostEvaluation.self,
                forKey: .planCostEvaluation
            ),
            planReplayValidation: try container.decodeIfPresent(
                XcircuiteSymbolicPlannerPlanReplayValidation.self,
                forKey: .planReplayValidation
            ),
            proofValidation: try container.decodeIfPresent(
                XcircuiteSymbolicPlannerProofValidation.self,
                forKey: .proofValidation
            ),
            solverResult: try container.decode(XcircuiteSymbolicPlannerSolverResult.self, forKey: .solverResult),
            planReplayValidationArtifact: try container.decodeIfPresent(
                XcircuiteFileReference.self,
                forKey: .planReplayValidationArtifact
            ),
            proofValidationArtifact: try container.decodeIfPresent(
                XcircuiteFileReference.self,
                forKey: .proofValidationArtifact
            ),
            nativeCertificateArtifact: try container.decodeIfPresent(
                XcircuiteFileReference.self,
                forKey: .nativeCertificateArtifact
            ),
            planVerificationArtifact: try container.decodeIfPresent(
                XcircuiteFileReference.self,
                forKey: .planVerificationArtifact
            ),
            qualificationArtifact: try container.decodeIfPresent(
                XcircuiteFileReference.self,
                forKey: .qualificationArtifact
            ),
            toolHealth: try container.decode(ToolHealthCheckResult.self, forKey: .toolHealth),
            diagnostics: try container.decodeIfPresent(
                [XcircuiteSymbolicPlannerSolverDiagnostic].self,
                forKey: .diagnostics
            ) ?? []
        )
    }
}
