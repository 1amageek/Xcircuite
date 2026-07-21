import Foundation
import DesignFlowKernel
import PDKKit
import PDKCore
import PDKDiscovery
import PDKStandardViews
import PDKValidation
import Testing
import ToolQualification
@testable import Xcircuite

@Suite("PDK external inspection process providers")
struct PDKExternalInspectionProcessProviderTests {
    @Test("standard-view process provider preserves result and execution artifacts", .timeLimit(.minutes(1)))
    func standardViewProcessProviderPreservesArtifacts() async throws {
        let root = try makeRoot(name: "pdk-external-standard-view")
        defer { removeRoot(root) }
        _ = try await makeContext(root: root, runID: "pdk-external-standard-view")
        let fixtureRoot = try makeFixtureProject(root: root)
        let manifestURL = fixtureRoot.appending(path: "valid-pdk/pdk.json")
        let manifest = try PDKManifestCodec.decode(contentsOf: manifestURL)
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
            test "$1" = "fixture-secret-token" || exit 9
            cp "$2" "$3"
            printf 'external standard-view stderr\\n' >&2
            """
        )
        let executableAliasURL = root.appending(path: "external-standard-view-tool-link.sh")
        try FileManager.default.createSymbolicLink(
            at: executableAliasURL,
            withDestinationURL: executableURL
        )
        let provider = ExternalPDKStandardViewProcessProvider(
            configuration: PDKExternalInspectionProcessConfiguration(
                executablePath: executableAliasURL.path,
                arguments: ["fixture-secret-token", sourceURL.path, "{{resultPath}}"],
                redactedArgumentIndexes: [0],
                timeoutSeconds: 10
            ),
            stageID: "pdk.external-standard-view"
        )
        let envelope = try await ExternalPDKStandardViewInspector(provider: provider).execute(request)

        #expect(envelope.status == .completed, "\(envelope.diagnostics)")
        #expect(envelope.payload.isValid)
        #expect(envelope.artifacts.count >= 5)
        #expect(envelope.artifacts.contains { $0.locator.location.value.hasSuffix("/execution.json") })
        #expect(envelope.artifacts.contains { $0.locator.location.value.hasSuffix("/stderr.txt") })
        #expect(envelope.provenance.producer.identifier == executableURL.lastPathComponent)
        #expect(envelope.provenance.producer.version.hasPrefix("sha256-"))
        #expect(envelope.provenance.invocation?.executable == executableURL.path)
        #expect(envelope.provenance.environment?.environmentDigest != nil)

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
        #expect(execution.arguments.first == "<redacted>")
        #expect(execution.executablePath == executableURL.path)
        #expect(execution.provenance.invocation?.arguments.first == "<redacted>")
        let encodedExecution = try JSONEncoder().encode(execution)
        #expect(!encodedExecution.contains(Data("fixture-secret-token".utf8)))
        #expect(execution.schemaVersion == PDKExternalInspectionExecutionRecord.currentSchemaVersion)
        #expect(execution.provenance == envelope.provenance)
    }

    @Test("rule-deck process failure preserves structured diagnostics and logs", .timeLimit(.minutes(1)))
    func ruleDeckProcessFailurePreservesArtifacts() async throws {
        let root = try makeRoot(name: "pdk-external-rule-deck-failure")
        defer { removeRoot(root) }
        _ = try await makeContext(root: root, runID: "pdk-external-rule-deck-failure")
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
        #expect(envelope.provenance.producer.identifier == executableURL.lastPathComponent)
        #expect(envelope.provenance.producer.version.hasPrefix("sha256-"))
        #expect(envelope.provenance.invocation?.executable == executableURL.path)

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
        #expect(execution.provenance == envelope.provenance)
    }

    @Test("external standard-view provider is executable through the typed PDK stage", .timeLimit(.minutes(1)))
    func externalStandardViewStagePersistsProcessEvidence() async throws {
        let root = try makeRoot(name: "pdk-external-stage")
        defer { removeRoot(root) }
        let fixtureRoot = try makeFixtureProject(root: root)
        let manifestURL = fixtureRoot.appending(path: "valid-pdk/pdk.json")
        let manifest = try PDKManifestCodec.decode(contentsOf: manifestURL)
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
        let context = try await makeContext(root: root, runID: runID)
        let result = try await executor.execute(
            stage: FlowStageDefinition(stageID: stageID, displayName: "External PDK standard view"),
            context: context
        )

        #expect(result.status == .succeeded, "\(result.diagnostics)")
        #expect(result.artifacts.count == 1)
        let runDirectory = try context.xcircuiteRunDirectory()
        let rawURL = runDirectory
            .appending(path: "stages")
            .appending(path: stageID)
            .appending(path: "raw/pdk-result.json")
        let rawData = try Data(contentsOf: rawURL)
        let envelope = try JSONDecoder().decode(
            PDKManifestViewInspectionResult.self,
            from: rawData
        )
        #expect(envelope.status == .completed)
        #expect(envelope.artifacts.contains { $0.locator.location.value.hasSuffix("/execution.json") })
        let resultArtifact = try #require(result.artifacts.first {
            $0.locator.location.value.hasSuffix("/pdk-result.json")
        })
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let ledger = try await store.loadRunLedger(runID: runID)
        #expect(resultArtifact.producer == envelope.provenance.producer)
        #expect(ledger.runManifest.artifacts.first {
            $0.locator == resultArtifact.locator
        } == resultArtifact)
        #expect(FileManager.default.fileExists(atPath: runDirectory
            .appending(path: "stages")
            .appending(path: stageID)
            .appending(path: "raw/external-pdk/stdout.txt")
            .path))
    }

    @Test("runtime specifications select the external PDK providers")
    func runtimeSpecificationSelectsExternalProviders() async throws {
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
            try XcircuiteFlowRuntimeSpec(executors: [decoded]).validate()
            let executor = try decoded.makeExecutor(projectRoot: URL(filePath: "/tmp/pdk-runtime-spec"))
            #expect(executor.toolID.hasPrefix("pdk-"))
            #expect(executor.toolID.contains("inspection"))
        }
    }

    @Test("redacted argument indexes must reference configured arguments")
    func redactedArgumentIndexesMustBeValid() {
        let outOfRange = PDKExternalInspectionProcessConfiguration(
            executablePath: "/bin/sh",
            arguments: ["secret"],
            redactedArgumentIndexes: [1]
        )
        let duplicated = PDKExternalInspectionProcessConfiguration(
            executablePath: "/bin/sh",
            arguments: ["first", "second"],
            redactedArgumentIndexes: [1, 1]
        )

        #expect(throws: PDKExternalInspectionProcessConfigurationError
            .invalidRedactedArgumentIndexes([1])) {
            try outOfRange.validate()
        }
        #expect(throws: PDKExternalInspectionProcessConfigurationError
            .invalidRedactedArgumentIndexes([1, 1])) {
            try duplicated.validate()
        }
    }

    private func makeRoot(name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeContext(root: URL, runID: String) async throws -> FlowExecutionContext {
        let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: root)
        try await workspaceStore.createWorkspace()
        _ = try await prepareTestRun(runID: runID, store: workspaceStore)
        let manifest = try await workspaceStore.loadManifest()
        return FlowExecutionContext(
            workspaceID: try FlowWorkspaceID(rawValue: manifest.identity.projectID),
            runID: runID,
            infrastructure: workspaceStore,
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
        let destination = root.appending(path: "fixtures")
        try PDKFixtureMaterializer.materialize(in: destination)
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
