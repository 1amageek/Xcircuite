import Foundation
import DesignFlowKernel
import PDKKit
import Testing
import ToolQualification
@testable import Xcircuite

@Suite("PDK external inspection process providers")
struct PDKExternalInspectionProcessProviderTests {
    @Test("standard-view process provider preserves result and execution artifacts", .timeLimit(.minutes(1)))
    func standardViewProcessProviderPreservesArtifacts() async throws {
        let root = try makeRoot(name: "pdk-external-standard-view")
        defer { removeRoot(root) }
        let fixtureRoot = try makeFixtureProject(root: root)
        let manifestURL = fixtureRoot.appending(path: "valid-pdk/pdk.json")
        let manifest = try PDKManifestCodec.decode(contentsOf: manifestURL).manifest
        let asset = try #require(manifest.assets.first { $0.assetID == "cells" })
        let resolved = try LocalPDKAssetResolver().resolve(asset, relativeTo: manifestURL)
        let request = PDKStandardViewInspectionRequest(
            runID: "pdk-external-standard-view",
            inputs: [resolved.reference.locator],
            format: .lef,
            assetID: "cells",
            projectRootPath: root.path
        )
        let localEnvelope = try await LocalPDKStandardViewInspector().execute(request)
        let sourceURL = root.appending(path: "external-standard-view-result.json")
        try JSONEncoder().encode(localEnvelope).write(to: sourceURL, options: [.atomic])

        let executableURL = try writeExecutable(
            at: root.appending(path: "external-standard-view-tool.sh"),
            text: """
            #!/bin/sh
            cp "$1" "$2"
            printf 'external standard-view stderr\\n' >&2
            """
        )
        let provider = ExternalPDKStandardViewProcessProvider(
            configuration: PDKExternalInspectionProcessConfiguration(
                executablePath: executableURL.path,
                arguments: [sourceURL.path, "{{resultPath}}"],
                timeoutSeconds: 10
            ),
            stageID: "pdk.external-standard-view"
        )
        let envelope = try await ExternalPDKStandardViewInspector(provider: provider).execute(request)

        #expect(envelope.status == .completed, "\(envelope.diagnostics)")
        #expect(envelope.payload.isValid)
        #expect(envelope.artifacts.count >= 5)
        #expect(envelope.artifacts.contains { $0.location.value.hasSuffix("/execution.json") })
        #expect(envelope.artifacts.contains { $0.location.value.hasSuffix("/stderr.txt") })

        let executionURL = root
            .appending(path: ".xcircuite/runs/pdk-external-standard-view/stages/pdk.external-standard-view/raw/external-pdk/execution.json")
        let execution = try JSONDecoder().decode(
            PDKExternalInspectionExecutionRecord.self,
            from: Data(contentsOf: executionURL)
        )
        #expect(execution.status == "completed")
        #expect(execution.exitCode == 0)
        #expect(execution.arguments.contains { $0 == sourceURL.path })
        #expect(execution.arguments.contains { $0.hasSuffix("/result.json") })
    }

    @Test("rule-deck process failure preserves structured diagnostics and logs", .timeLimit(.minutes(1)))
    func ruleDeckProcessFailurePreservesArtifacts() async throws {
        let root = try makeRoot(name: "pdk-external-rule-deck-failure")
        defer { removeRoot(root) }
        let fixtureRoot = try makeFixtureProject(root: root)
        let manifestURL = fixtureRoot.appending(path: "valid-pdk/pdk.json")
        let pdk = try PDKManifestReferenceBuilder().makeReference(for: manifestURL)
        let request = PDKRuleDeckInspectionRequest(
            runID: "pdk-external-rule-deck-failure",
            inputs: [pdk.manifest.locator],
            pdk: pdk,
            assetID: "rules",
            projectRootPath: root.path
        )
        let executableURL = try writeExecutable(
            at: root.appending(path: "external-rule-deck-failing-tool.sh"),
            text: """
            #!/bin/sh
            printf 'external rule-deck failure\\n' >&2
            exit 7
            """
        )
        let provider = ExternalPDKRuleDeckProcessProvider(
            configuration: PDKExternalInspectionProcessConfiguration(
                executablePath: executableURL.path,
                timeoutSeconds: 10
            ),
            stageID: "pdk.external-rule-deck"
        )

        let envelope = try await ExternalPDKRuleDeckInspector(provider: provider).execute(request)

        #expect(envelope.status == .failed)
        #expect(envelope.payload.isValid == false)
        #expect(envelope.payload.findings.contains {
            $0.code == "pdk.external.process-execution-failed"
        })
        #expect(envelope.artifacts.count == 5)

        let stderrURL = root
            .appending(path: ".xcircuite/runs/pdk-external-rule-deck-failure/stages/pdk.external-rule-deck/raw/external-pdk/stderr.txt")
        #expect(String(data: try Data(contentsOf: stderrURL), encoding: .utf8)?.contains("failure") == true)
        let executionURL = root
            .appending(path: ".xcircuite/runs/pdk-external-rule-deck-failure/stages/pdk.external-rule-deck/raw/external-pdk/execution.json")
        let execution = try JSONDecoder().decode(
            PDKExternalInspectionExecutionRecord.self,
            from: Data(contentsOf: executionURL)
        )
        #expect(execution.status == "failed")
        #expect(execution.exitCode == 7)
    }

    @Test("external standard-view provider is executable through the typed PDK stage", .timeLimit(.minutes(1)))
    func externalStandardViewStagePersistsProcessEvidence() async throws {
        let root = try makeRoot(name: "pdk-external-stage")
        defer { removeRoot(root) }
        let fixtureRoot = try makeFixtureProject(root: root)
        let manifestURL = fixtureRoot.appending(path: "valid-pdk/pdk.json")
        let manifest = try PDKManifestCodec.decode(contentsOf: manifestURL).manifest
        let asset = try #require(manifest.assets.first { $0.assetID == "cells" })
        let resolved = try LocalPDKAssetResolver().resolve(asset, relativeTo: manifestURL)
        let runID = "pdk-external-stage"
        let rawRequest = PDKStandardViewInspectionRequest(
            runID: runID,
            inputs: [resolved.reference.locator],
            format: .lef,
            assetID: "cells",
            projectRootPath: root.path
        )
        let localEnvelope = try await LocalPDKStandardViewInspector().execute(rawRequest)
        let sourceURL = root.appending(path: "external-stage-result.json")
        try JSONEncoder().encode(localEnvelope).write(to: sourceURL, options: [.atomic])
        let executableURL = try writeExecutable(
            at: root.appending(path: "external-stage-tool.sh"),
            text: """
            #!/bin/sh
            cp "$1" "$2"
            """
        )
        let stageID = "pdk.external-standard-view-stage"
        let executor = PDKStandardViewInspectionFlowStageExecutor.external(
            configuration: PDKExternalInspectionProcessConfiguration(
                executablePath: executableURL.path,
                arguments: [sourceURL.path, "{{resultPath}}"],
                timeoutSeconds: 10
            ),
            stageID: stageID,
            manifestInput: .path("fixtures/valid-pdk/pdk.json"),
            assetID: "cells",
            format: .lef
        )
        let context = makeContext(root: root, runID: runID)
        let result = try await executor.execute(
            stage: FlowStageDefinition(stageID: stageID, displayName: "External PDK standard view"),
            context: context
        )

        #expect(result.status == .succeeded, "\(result.diagnostics)")
        #expect(result.artifacts.count == 1)
        let rawURL = context.runDirectory
            .appending(path: "stages")
            .appending(path: stageID)
            .appending(path: "raw/pdk-result.json")
        let rawData = try Data(contentsOf: rawURL)
        let envelope = try JSONDecoder().decode(
            PDKManifestViewInspectionResult.self,
            from: rawData
        )
        #expect(envelope.status == .completed)
        #expect(envelope.artifacts.contains { $0.location.value.hasSuffix("/execution.json") })
        #expect(FileManager.default.fileExists(atPath: context.runDirectory
            .appending(path: "stages")
            .appending(path: stageID)
            .appending(path: "raw/external-pdk/stdout.txt")
            .path))
    }

    @Test("runtime specifications select the external PDK providers")
    func runtimeSpecificationSelectsExternalProviders() throws {
        let configuration = PDKExternalInspectionProcessConfiguration(
            executablePath: "/bin/sh",
            arguments: ["{{requestPath}}", "{{resultPath}}"],
            timeoutSeconds: 12
        )
        let standardView = XcircuiteFlowStageExecutorSpec.pdkStandardView(.init(
            manifestInput: .path("fixtures/valid-pdk/pdk.json"),
            assetID: "cells",
            format: .lef,
            externalProcess: configuration
        ))
        let ruleDeck = XcircuiteFlowStageExecutorSpec.pdkRuleDeck(.init(
            manifestInput: .path("fixtures/valid-pdk/pdk.json"),
            assetID: "rules",
            externalProcess: configuration
        ))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        for spec in [standardView, ruleDeck] {
            let decoded = try JSONDecoder().decode(
                XcircuiteFlowStageExecutorSpec.self,
                from: try encoder.encode(spec)
            )
            #expect(decoded == spec)
            try XcircuiteFlowRuntimeSpec(executors: [decoded]).validate(
                requireCompleteToolEvidence: false
            )
            let executor = try decoded.makeExecutor(projectRoot: URL(filePath: "/tmp/pdk-runtime-spec"))
            #expect(executor.toolID.hasPrefix("pdk-"))
            #expect(executor.toolID.contains("inspection"))
        }
    }

    private func makeRoot(name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeContext(root: URL, runID: String) -> FlowExecutionContext {
        let runDirectory = root
            .appending(path: ".xcircuite")
            .appending(path: "runs")
            .appending(path: runID)
        do {
            try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)
        } catch {
            Issue.record("Failed to create run directory: \(error)")
        }
        return FlowExecutionContext(
            projectRoot: root,
            runID: runID,
            runDirectory: runDirectory,
            workspaceStore: XcircuiteWorkspaceStore(),
            toolRegistry: ToolRegistry(),
            healthResults: [:]
        )
    }

    private func removeRoot(_ root: URL) {
        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            Issue.record("Failed to remove test root: \(error)")
        }
    }

    private func makeFixtureProject(root: URL) throws -> URL {
        let workspaceRoot = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = workspaceRoot
            .appending(path: "PDKKit")
            .appending(path: "Tests/PDKKitTests/Fixtures")
        let destination = root.appending(path: "fixtures")
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }

    private func writeExecutable(at url: URL, text: String) throws -> URL {
        try text.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path(percentEncoded: false)
        )
        return url
    }
}
