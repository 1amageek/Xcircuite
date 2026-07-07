import Foundation
import DesignFlowKernel
import ToolQualification
import Xcircuite

enum QualifiedToolFixtures {
    static func runtime(
        executors: [any FlowStageExecutor],
        descriptors: [ToolDescriptor],
        toolchainProfile: XcircuiteFlowToolchainProfile? = nil
    ) -> XcircuiteFlowRuntime {
        let healthResults = Dictionary(
            uniqueKeysWithValues: descriptors.map { descriptor in
                (
                    descriptor.toolID,
                    health(toolID: descriptor.toolID, level: descriptor.trustProfile.level)
                )
            }
        )
        return XcircuiteFlowRuntimeFactory.make(
            descriptors: descriptors,
            healthResults: healthResults,
            executors: executors,
            toolchainProfile: toolchainProfile
        )
    }

    static func toolSpec(level: ToolQualificationLevel) -> XcircuiteFlowToolSpec {
        XcircuiteFlowToolSpec(
            qualificationLevel: level,
            healthStatus: .passed,
            evidence: evidenceSupporting(level: level)
        )
    }

    static func health(
        toolID: String,
        level: ToolQualificationLevel,
        status: ToolHealthStatus = .passed
    ) -> ToolHealthCheckResult {
        ToolHealthCheckResult(
            toolID: toolID,
            status: status,
            evidence: evidenceSupporting(level: level)
        )
    }

    static func evidenceSupporting(level: ToolQualificationLevel) -> [ToolEvidence] {
        switch level {
        case .unknown:
            []
        case .smokeChecked:
            [qualifiedEvidence("smoke-1", kind: .smoke)]
        case .corpusChecked:
            [qualifiedEvidence("corpus-1", kind: .corpus)]
        case .oracleChecked:
            [
                qualifiedEvidence("corpus-1", kind: .corpus),
                qualifiedEvidence("oracle-1", kind: .oracle),
            ]
        case .productionEligible:
            [
                qualifiedEvidence("corpus-1", kind: .corpus),
                qualifiedEvidence("oracle-1", kind: .oracle),
                qualifiedEvidence("production-approval-1", kind: .productionApproval),
            ]
        }
    }

    static func qualifiedEvidence(_ evidenceID: String, kind: ToolEvidenceKind) -> ToolEvidence {
        ToolEvidence(
            evidenceID: evidenceID,
            kind: kind,
            qualification: ToolEvidenceQualificationSummary(
                qualified: true,
                policyID: "unit-test-policy",
                observedMetrics: ["passRate": 1],
                observedCounts: ["caseCount": 1]
            )
        )
    }
}
