import Foundation
import Testing
import Xcircuite
import XcircuiteFlowCLISupport

@Suite("Xcircuite symbolic planner feature matrix")
struct XcircuiteSymbolicPlannerFeatureMatrixTests {
    @Test func providerExposesRequiredTrustCoverageTags() {
        let matrix = XcircuiteSymbolicPlannerFeatureMatrixProvider().currentMatrix()

        #expect(matrix.matrixID == "symbolic-planner-feature-matrix-v1")
        #expect(matrix.requiredForCorpusTrustTags.contains("symbolic.external-solver-invocation"))
        #expect(matrix.requiredForCorpusTrustTags.contains("symbolic.expected-action-coverage"))
        #expect(matrix.requiredForCorpusTrustTags.contains("symbolic.plan-replay-validation"))
        #expect(matrix.requiredForCorpusTrustTags.contains("symbolic.goal-coverage"))
        #expect(matrix.requiredForCorpusTrustTags.contains("symbolic.multi-case"))
        #expect(matrix.requiredForCorpusTrustTags.contains("symbolic.suite-spec-provenance"))
        #expect(matrix.requiredForCorpusTrustTags.contains("symbolic.required-coverage-gate"))

        let requiredTags = Set(matrix.requiredForCorpusTrustTags)
        let implementedTags = Set(matrix.implementedCoverageTags)
        #expect(requiredTags.isSubset(of: implementedTags))
        #expect(matrix.implementedCoverageTags.contains("symbolic.drc-repair-domain"))
        #expect(matrix.implementedCoverageTags.contains("symbolic.drc-overlap-repair-domain"))
        #expect(matrix.implementedCoverageTags.contains("symbolic.drc-density-repair-domain"))
        #expect(matrix.implementedCoverageTags.contains("symbolic.drc-antenna-repair-domain"))
        #expect(matrix.implementedCoverageTags.contains("symbolic.drc-routing-repair-domain"))
        #expect(matrix.implementedCoverageTags.contains("symbolic.drc-notch-repair-domain"))
        #expect(matrix.implementedCoverageTags.contains("symbolic.drc-grid-repair-domain"))
        #expect(matrix.implementedCoverageTags.contains("symbolic.drc-cut-repair-domain"))
        #expect(matrix.implementedCoverageTags.contains("symbolic.lvs-repair-domain"))
        #expect(matrix.implementedCoverageTags.contains("symbolic.lvs-device-repair-domain"))
        #expect(matrix.implementedCoverageTags.contains("symbolic.lvs-terminal-equivalence-repair-domain"))
        #expect(matrix.implementedCoverageTags.contains("symbolic.lvs-hierarchy-repair-domain"))
        #expect(matrix.implementedCoverageTags.contains("symbolic.lvs-global-net-repair-domain"))
        #expect(matrix.implementedCoverageTags.contains("symbolic.lvs-policy-mutation-repair-domain"))
        #expect(matrix.implementedCoverageTags.contains("symbolic.lvs-black-box-hierarchy-repair-domain"))
        #expect(matrix.implementedCoverageTags.contains("symbolic.lvs-arrayed-device-repair-domain"))
        #expect(matrix.implementedCoverageTags.contains("symbolic.lvs-parasitic-device-repair-domain"))
        #expect(matrix.implementedCoverageTags.contains("symbolic.pex-repair-domain"))
        #expect(matrix.implementedCoverageTags.contains("symbolic.pex-multi-corner-repair-domain"))
        #expect(matrix.implementedCoverageTags.contains("symbolic.pex-rc-network-repair-domain"))
        #expect(matrix.implementedCoverageTags.contains("symbolic.pex-post-layout-simulation-repair-domain"))
        #expect(matrix.implementedCoverageTags.contains("symbolic.optimality-check"))
        #expect(matrix.implementedCoverageTags.contains("symbolic.weighted-action-cost"))
        #expect(matrix.implementedCoverageTags.contains("symbolic.plan-replay-validation"))
        #expect(matrix.implementedCoverageTags.contains("symbolic.independent-plan-cost"))
        #expect(matrix.implementedCoverageTags.contains("symbolic.solver-proof-validation"))
        #expect(matrix.implementedCoverageTags.contains("symbolic.solver-native-certificate-parsing"))
        #expect(matrix.implementedCoverageTags.contains("symbolic.installed-solver-lane"))
        #expect(matrix.implementedCoverageTags.contains("symbolic.repair-formulation-compiler"))
        #expect(matrix.implementedCoverageTags.contains("symbolic.signoff-repair-formulation-bridge"))
        #expect(!matrix.plannedCoverageTags.contains("symbolic.solver-native-certificate-parsing"))
        #expect(!matrix.plannedCoverageTags.contains("symbolic.installed-solver-lane"))
        #expect(!matrix.plannedCoverageTags.contains("symbolic.repair-formulation-compiler"))
        #expect(!matrix.plannedCoverageTags.contains("symbolic.signoff-repair-formulation-bridge"))
    }

    @Test func featureTagsAreUnique() {
        let matrix = XcircuiteSymbolicPlannerFeatureMatrixProvider().currentMatrix()
        let tags = matrix.features.map(\.coverageTag)

        #expect(Set(tags).count == tags.count)
    }

    @Test func coverageTagValidatorRejectsUnknownTags() async throws {
        let validator = XcircuiteSymbolicPlannerCoverageTagValidator()

        do {
            try validator.validateCoverageTags([
                "symbolic.required-coverage-gate",
                "symbolic.not-in-matrix",
            ])
            Issue.record("Expected unknown coverage tag validation to fail.")
        } catch let error as XcircuiteSymbolicPlannerSolverError {
            #expect(error == .unknownCoverageTags(
                tags: ["symbolic.not-in-matrix"],
                knownTags: XcircuiteSymbolicPlannerFeatureMatrixProvider()
                    .currentMatrix()
                    .features
                    .map(\.coverageTag)
                    .sorted()
            ))
        }
    }

    @Test func coverageTagValidatorAcceptsNativeCertificateCoverageAsImplemented() async throws {
        let validator = XcircuiteSymbolicPlannerCoverageTagValidator()

        try validator.validateImplementedCoverageTags([
            "symbolic.external-solver-invocation",
            "symbolic.solver-native-certificate-parsing",
        ])
    }

    @Test func featureMatrixCLIEmitsJSON() async throws {
        let json = try await XcircuiteFlowCLICommand.run(
            arguments: [
                "symbolic-planner-feature-matrix",
                "--pretty",
            ]
        )
        let data = try #require(json.data(using: .utf8))
        let matrix = try JSONDecoder().decode(XcircuiteSymbolicPlannerFeatureMatrix.self, from: data)

        #expect(matrix.requiredForCorpusTrustTags.contains("symbolic.required-coverage-gate"))
        #expect(matrix.features.contains {
            $0.coverageTag == "symbolic.optimality-check"
                && $0.maturity == "implemented"
        })
        #expect(matrix.features.contains {
            $0.coverageTag == "symbolic.weighted-action-cost"
                && $0.maturity == "implemented"
        })
        #expect(matrix.features.contains {
            $0.coverageTag == "symbolic.plan-replay-validation"
                && $0.maturity == "implemented"
        })
        #expect(matrix.features.contains {
            $0.coverageTag == "symbolic.independent-plan-cost"
                && $0.maturity == "implemented"
        })
        #expect(matrix.features.contains {
            $0.coverageTag == "symbolic.solver-proof-validation"
                && $0.maturity == "implemented"
        })
        #expect(matrix.features.contains {
            $0.coverageTag == "symbolic.solver-native-certificate-parsing"
                && $0.maturity == "implemented"
        })
        #expect(matrix.features.contains {
            $0.coverageTag == "symbolic.installed-solver-lane"
                && $0.maturity == "implemented"
        })
        #expect(matrix.features.contains {
            $0.coverageTag == "symbolic.repair-formulation-compiler"
                && $0.maturity == "implemented"
        })
        #expect(matrix.features.contains {
            $0.coverageTag == "symbolic.signoff-repair-formulation-bridge"
                && $0.maturity == "implemented"
        })
    }
}
