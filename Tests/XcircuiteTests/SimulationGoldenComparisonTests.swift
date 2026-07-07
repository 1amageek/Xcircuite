import Foundation
import Testing
import Xcircuite
import XcircuiteFlowCLISupport

@Suite("Simulation golden comparison", .timeLimit(.minutes(1)))
struct SimulationGoldenComparisonTests {
    @Test func serviceComparesGoldenWaveformAndRecordsWorstPoint() throws {
        let golden = """
        time,V(out),I(vdd)
        0,0,0
        1e-9,1.0,-0.001
        2e-9,0.5,-0.0005
        """
        let candidate = """
        time,V(out),I(vdd),V(extra)
        0,0,0,1
        1e-9,0.97,-0.0011,1
        2e-9,0.52,-0.0005,1
        """

        let report = try SimulationGoldenComparisonService().compare(
            goldenCSV: golden,
            candidateCSV: candidate,
            options: SimulationGoldenComparisonOptions(
                maxAbsoluteDelta: 0.05,
                maxRelativeDelta: 0.2,
                requiredVariables: ["V(out)"],
                comparedVariables: ["V(out)"]
            )
        )

        #expect(report.status == "compared")
        #expect(report.gateStatus == "passed")
        #expect(report.comparedPointCount == 3)
        #expect(report.addedInCandidate == ["V(extra)"])
        #expect(report.requiredVariables == [
            SimulationGoldenRequiredVariableResult(variableName: "V(out)", present: true),
        ])
        let comparison = try #require(report.comparedVariables.first)
        #expect(comparison.variableName == "V(out)")
        #expect(abs(comparison.maxAbsoluteDelta - 0.03) < 1.0e-12)
        #expect(comparison.worstPoint?.sweepValue == 1.0e-9)
        #expect(comparison.worstPoint?.goldenValue == 1.0)
        #expect(comparison.worstPoint?.candidateValue == 0.97)
    }

    @Test func serviceFailsGateForMissingVariableAndToleranceViolation() throws {
        let golden = """
        time,V(out),I(vdd)
        0,0,0
        1e-9,1,0
        """
        let candidate = """
        time,V(out)
        0,0
        1e-9,0.8
        """

        let report = try SimulationGoldenComparisonService().compare(
            goldenCSV: golden,
            candidateCSV: candidate,
            options: SimulationGoldenComparisonOptions(
                maxAbsoluteDelta: 0.05,
                requiredVariables: ["I(vdd)"]
            )
        )

        #expect(report.status == "compared")
        #expect(report.gateStatus == "failed")
        #expect(report.missingInCandidate == ["I(vdd)"])
        #expect(report.gateViolations.contains {
            $0.contains("maximum absolute delta")
        })
        #expect(report.gateViolations.contains {
            $0.contains("missing required variable I(vdd)")
        })
    }

    @Test func serviceFailsGateForPartialCandidateSweepCoverageByDefault() throws {
        let golden = """
        time,V(out)
        0,0
        1e-9,1
        2e-9,0
        3e-9,1
        """
        let candidate = """
        time,V(out)
        0,0
        """

        let report = try SimulationGoldenComparisonService().compare(
            goldenCSV: golden,
            candidateCSV: candidate
        )

        #expect(report.gateStatus == "failed")
        #expect(report.comparedPointCount < report.goldenPointCount)
        #expect(report.gateViolations.contains { $0.contains("does not cover the full golden sweep") })
        #expect(report.diagnostics.contains { $0.contains("Candidate sweep has insufficient increasing points") })
    }

    @Test func serviceFailsGateForMissingGoldenVariableByDefault() throws {
        let golden = """
        time,V(out),I(vdd)
        0,0,0
        1e-9,1,-0.001
        """
        let candidate = """
        time,V(out)
        0,0
        1e-9,1
        """

        let report = try SimulationGoldenComparisonService().compare(
            goldenCSV: golden,
            candidateCSV: candidate
        )

        #expect(report.gateStatus == "failed")
        #expect(report.missingInCandidate == ["I(vdd)"])
        #expect(report.gateViolations.contains { $0.contains("missing golden variable I(vdd)") })
    }

    @Test func serviceMatchesWaveformVariablesCaseInsensitively() throws {
        let golden = """
        time,V(out)
        0,0
        1e-9,1
        """
        let candidate = """
        time,v(out)
        0,0
        1e-9,1
        """

        let report = try SimulationGoldenComparisonService().compare(
            goldenCSV: golden,
            candidateCSV: candidate,
            options: SimulationGoldenComparisonOptions(maxAbsoluteDelta: 0)
        )

        #expect(report.status == "compared")
        #expect(report.gateStatus == "passed")
        #expect(report.comparedVariables.map(\.variableName) == ["V(out)"])
    }

    @Test func serviceFailsGateWhenNoNumericToleranceIsConfigured() throws {
        let golden = """
        time,V(out)
        0,0
        1e-9,1
        """
        let candidate = """
        time,V(out)
        0,0
        1e-9,1
        """

        let report = try SimulationGoldenComparisonService().compare(
            goldenCSV: golden,
            candidateCSV: candidate
        )

        #expect(report.status == "compared")
        #expect(report.gateStatus == "failed")
        #expect(report.gateViolations.contains { $0.contains("requires maxAbsoluteDelta or maxRelativeDelta") })
    }

    @Test func cliEmitsAndWritesGoldenComparisonReport() async throws {
        let root = try makeTemporaryRoot("simulation-golden-cli")
        defer { removeTemporaryRoot(root) }
        let goldenURL = try writeText(
            """
            time,V(out)
            0,0
            1e-9,1
            """,
            name: "golden.csv",
            root: root
        )
        let candidateURL = try writeText(
            """
            time,V(out)
            0,0
            1e-9,0.99
            """,
            name: "candidate.csv",
            root: root
        )
        let outputURL = root.appending(path: "comparison.json")

        let output = try await XcircuiteFlowCLICommand.run(arguments: [
            "compare-simulation-golden",
            "--golden-csv", goldenURL.path(percentEncoded: false),
            "--candidate-csv", candidateURL.path(percentEncoded: false),
            "--max-absolute-delta", "0.02",
            "--required-variable", "V(out)",
            "--out", outputURL.path(percentEncoded: false),
            "--pretty",
        ])
        let stdoutReport = try JSONDecoder().decode(
            SimulationGoldenComparisonReport.self,
            from: Data(output.utf8)
        )
        let persistedReport = try JSONDecoder().decode(
            SimulationGoldenComparisonReport.self,
            from: Data(contentsOf: outputURL)
        )

        #expect(stdoutReport.gateStatus == "passed")
        #expect(stdoutReport == persistedReport)
        #expect(persistedReport.comparedVariables.first?.variableName == "V(out)")
    }

    @Test func actionDomainSnapshotIncludesGoldenComparisonOperation() throws {
        let snapshot = try XcircuiteActionDomainSnapshotBuilder().snapshot(
            runID: "simulation-golden-action-domain",
            generatedAt: "2026-06-29T00:00:00Z"
        )
        let simulation = try #require(snapshot.domains.first { $0.domainID == "simulation-analysis" })
        let operation = try #require(simulation.operations.first {
            $0.operationID == "simulation.compare-golden"
        })

        #expect(operation.maturity == "implemented")
        #expect(operation.producedArtifacts == ["simulation-golden-comparison"])
        #expect(operation.verificationGates.contains("simulation-metric-gate"))
    }

    private func writeText(_ text: String, name: String, root: URL) throws -> URL {
        let url = root.appending(path: name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func makeTemporaryRoot(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "xcircuite-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func removeTemporaryRoot(_ root: URL) {
        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            Issue.record("Failed to remove temporary root: \(error)")
        }
    }
}
