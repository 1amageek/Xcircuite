import CircuiteFoundation
import DesignFlowKernel
import Foundation
import ToolQualification
@testable import Xcircuite

enum QualifiedToolFixtures {
    private struct EvidenceFixture: Sendable {
        let evidence: ToolEvidence
        let data: Data
    }

    private static let checkedAt = Date(timeIntervalSince1970: 1_784_000_000)

    static func runtime(
        spec: XcircuiteFlowRuntimeSpec,
        projectRoot: URL
    ) throws -> XcircuiteFlowRuntime {
        try materializeEvidence(for: spec.makeToolBindings().descriptors, in: projectRoot)
        return try spec.makeRuntime(projectRoot: projectRoot)
    }

    static func runtime(
        executors: [any FlowStageExecutor],
        descriptors: [ToolDescriptor],
        projectRoot: URL,
        toolchainProfile: XcircuiteFlowToolchainProfile? = nil
    ) throws -> XcircuiteFlowRuntime {
        let qualifiedDescriptors = descriptors.map { descriptor in
            var qualifiedDescriptor = descriptor
            qualifiedDescriptor.trustProfile.evidence = evidenceSupporting(
                level: descriptor.trustProfile.level,
                toolID: descriptor.toolID
            )
            return qualifiedDescriptor
        }
        try materializeEvidence(for: qualifiedDescriptors, in: projectRoot)
        let healthResults = Dictionary(
            uniqueKeysWithValues: qualifiedDescriptors.map { descriptor in
                (
                    descriptor.toolID,
                    health(toolID: descriptor.toolID, level: descriptor.trustProfile.level)
                )
            }
        )
        return try XcircuiteFlowRuntimeFactory.make(
            descriptors: qualifiedDescriptors,
            healthResults: healthResults,
            executors: executors,
            projectRoot: projectRoot,
            toolchainProfile: toolchainProfile
        )
    }

    static func toolSpec(
        level: ToolQualificationLevel,
        toolID: String = "native-drc"
    ) -> XcircuiteFlowToolSpec {
        precondition(
            level != .productionEligible,
            "Production-eligible fixtures require retained process qualification evidence."
        )
        return XcircuiteFlowToolSpec(
            qualificationLevel: level,
            healthStatus: .passed,
            evidence: evidenceSupporting(level: level, toolID: toolID)
        )
    }

    static func health(
        toolID: String,
        level _: ToolQualificationLevel,
        status: ToolHealthStatus = .passed
    ) -> ToolHealthCheckResult {
        let evidence: [ToolEvidence]
        do {
            evidence = [try healthFixture(toolID: toolID).evidence]
        } catch {
            preconditionFailure("Invalid health qualification fixture: \(error)")
        }
        return ToolHealthCheckResult(
            toolID: toolID,
            status: status,
            evidence: evidence
        )
    }

    static func evidenceSupporting(
        level: ToolQualificationLevel,
        toolID: String
    ) -> [ToolEvidence] {
        fixtures(level: level, toolID: toolID).map(\.evidence)
    }

    static func materializeEvidence(
        for descriptors: [ToolDescriptor],
        in projectRoot: URL
    ) throws {
        for descriptor in descriptors {
            let fixtures = try makeFixtures(
                level: descriptor.trustProfile.level,
                toolID: descriptor.toolID
            ) + [try healthFixture(toolID: descriptor.toolID)]
            for fixture in fixtures {
                let url = try fixture.evidence.artifact?.locator.location.resolvedFileURL(
                    relativeTo: projectRoot
                )
                guard let url else {
                    preconditionFailure("Qualified evidence fixture must retain an artifact.")
                }
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try fixture.data.write(to: url, options: .atomic)
            }
        }
    }

    private static func fixtures(
        level: ToolQualificationLevel,
        toolID: String
    ) -> [EvidenceFixture] {
        do {
            return try makeFixtures(level: level, toolID: toolID)
        } catch {
            preconditionFailure("Invalid qualified tool fixture: \(error)")
        }
    }

    private static func makeFixtures(
        level: ToolQualificationLevel,
        toolID: String
    ) throws -> [EvidenceFixture] {
        switch level {
        case .unknown:
            return []
        case .smokeChecked:
            return [try smokeFixture(toolID: toolID)]
        case .corpusChecked:
            return [try corpusFixture(toolID: toolID)]
        case .oracleChecked:
            return [
                try corpusFixture(toolID: toolID),
                try oracleFixture(toolID: toolID),
            ]
        case .productionEligible:
            preconditionFailure(
                "Production-eligible fixtures require retained process qualification evidence."
            )
        }
    }

    private static func smokeFixture(toolID: String) throws -> EvidenceFixture {
        let data = Data("qualified-tool-smoke:\(toolID)".utf8)
        let issuer = try qualificationIssuer(toolID: toolID)
        let artifact = try qualificationArtifact(
            toolID: toolID,
            kind: .smoke,
            data: data,
            producer: issuer
        )
        return EvidenceFixture(
            evidence: ToolEvidence(
                evidenceID: "\(toolID)-smoke",
                kind: .smoke,
                artifact: artifact,
                checkedAt: checkedAt
            ),
            data: data
        )
    }

    private static func corpusFixture(toolID: String) throws -> EvidenceFixture {
        let issuer = try qualificationIssuer(toolID: toolID)
        let result = ToolCorpusQualificationResult(
            resultID: "\(toolID)-corpus",
            qualificationID: "\(toolID)-qualification",
            toolID: toolID,
            scope: qualificationScope(toolID: toolID),
            issuer: issuer,
            inputArtifacts: [try supportingArtifact(
                toolID: toolID,
                name: "input",
                producer: issuer
            )],
            outputArtifacts: [try supportingArtifact(toolID: toolID, name: "output", producer: issuer)],
            cases: [ToolQualificationCaseOutcome(
                caseID: "fixture-case",
                coverageTags: ["fixture"],
                comparisons: [ToolQualificationMetricComparison(
                    metricID: "pass",
                    observed: 1,
                    expected: 1
                )]
            )],
            checkedAt: checkedAt
        )
        return try evidenceFixture(
            evidenceID: result.resultID,
            toolID: toolID,
            kind: .corpus,
            data: result.canonicalData(),
            issuer: issuer
        )
    }

    private static func oracleFixture(toolID: String) throws -> EvidenceFixture {
        let issuer = try qualificationIssuer(toolID: toolID)
        let outcome = ToolQualificationCaseOutcome(
            caseID: "fixture-case",
            coverageTags: ["fixture"],
            comparisons: [ToolQualificationMetricComparison(
                metricID: "pass",
                observed: 1,
                expected: 1
            )]
        )
        let result = ToolOracleQualificationResult(
            resultID: "\(toolID)-oracle",
            qualificationID: "\(toolID)-qualification",
            primaryToolID: toolID,
            oracleToolID: "\(toolID)-oracle-tool",
            scope: qualificationScope(toolID: toolID),
            issuer: issuer,
            inputArtifacts: [try supportingArtifact(
                toolID: toolID,
                name: "input",
                producer: issuer
            )],
            primaryOutputArtifacts: [try supportingArtifact(
                toolID: toolID,
                name: "primary-output",
                producer: issuer
            )],
            oracleOutputArtifacts: [try supportingArtifact(
                toolID: toolID,
                name: "oracle-output",
                producer: issuer
            )],
            cases: [ToolOracleCaseComparison(
                caseID: "fixture-case",
                primary: outcome,
                oracle: outcome,
                agreementComparisons: [ToolQualificationMetricComparison(
                    metricID: "agreement",
                    observed: 1,
                    expected: 1
                )]
            )],
            checkedAt: checkedAt
        )
        return try evidenceFixture(
            evidenceID: result.resultID,
            toolID: toolID,
            kind: .oracle,
            data: result.canonicalData(),
            issuer: issuer
        )
    }

    private static func healthFixture(toolID: String) throws -> EvidenceFixture {
        let issuer = try qualificationIssuer(toolID: toolID)
        let result = ToolHealthQualificationResult(
            resultID: "\(toolID)-health-check",
            qualificationID: "\(toolID)-qualification",
            toolID: toolID,
            scope: qualificationScope(toolID: toolID),
            issuer: issuer,
            inputArtifacts: [try supportingArtifact(
                toolID: toolID,
                name: "input",
                producer: issuer
            )],
            outputArtifacts: [try supportingArtifact(
                toolID: toolID,
                name: "health-output",
                producer: issuer
            )],
            checkedAt: checkedAt
        )
        return try evidenceFixture(
            evidenceID: result.resultID,
            toolID: toolID,
            kind: .healthCheck,
            data: result.canonicalData(),
            issuer: issuer
        )
    }

    private static func evidenceFixture(
        evidenceID: String,
        toolID: String,
        kind: ToolEvidenceKind,
        data: Data,
        issuer: ProducerIdentity
    ) throws -> EvidenceFixture {
        let artifact = try qualificationArtifact(
            toolID: toolID,
            kind: kind,
            data: data,
            producer: issuer
        )
        return EvidenceFixture(
            evidence: ToolEvidence(
                evidenceID: evidenceID,
                kind: kind,
                artifact: artifact,
                checkedAt: checkedAt
            ),
            data: data
        )
    }

    private static func qualificationArtifact(
        toolID: String,
        kind: ToolEvidenceKind,
        data: Data,
        producer: ProducerIdentity
    ) throws -> ArtifactReference {
        ArtifactReference(
            id: try ArtifactID(rawValue: "\(toolID)-\(kind.rawValue)-evidence"),
            locator: ArtifactLocator(
                location: try ArtifactLocation(
                    workspaceRelativePath: "qualification/test-fixtures/\(toolID)-\(kind.rawValue).json"
                ),
                role: .output,
                kind: .evidence,
                format: .json
            ),
            digest: try SHA256ContentDigester().digest(data: data),
            byteCount: UInt64(data.count),
            producer: producer
        )
    }

    private static func supportingArtifact(
        toolID: String,
        name: String,
        producer: ProducerIdentity
    ) throws -> ArtifactReference {
        let data = Data("\(toolID):\(name)".utf8)
        return ArtifactReference(
            id: try ArtifactID(rawValue: "\(toolID)-\(name)"),
            locator: ArtifactLocator(
                location: try ArtifactLocation(
                    workspaceRelativePath: "qualification/test-fixtures/\(toolID)-\(name).json"
                ),
                role: .output,
                kind: .evidence,
                format: .json
            ),
            digest: try SHA256ContentDigester().digest(data: data),
            byteCount: UInt64(data.count),
            producer: producer
        )
    }

    private static func qualificationIssuer(toolID: String) throws -> ProducerIdentity {
        try ProducerIdentity(
            kind: .engine,
            identifier: "\(toolID)-qualification-fixture",
            version: "1"
        )
    }

    static func qualificationScope(toolID: String) -> ToolQualificationScope {
        ToolQualificationScope(
            implementationID: toolID,
            toolVersion: "1",
            binaryDigest: String(repeating: "1", count: 64),
            algorithmVersion: "fixture-v1",
            processProfileID: "fixture-process",
            processProfileDigest: String(repeating: "2", count: 64),
            deckDigest: String(repeating: "3", count: 64),
            pdkID: "fixture-pdk",
            pdkDigest: String(repeating: "4", count: 64),
            oracle: ToolOracleQualificationScope(
                implementationID: "\(toolID)-oracle-tool",
                version: "1",
                binaryDigest: String(repeating: "5", count: 64)
            )
        )
    }
}
