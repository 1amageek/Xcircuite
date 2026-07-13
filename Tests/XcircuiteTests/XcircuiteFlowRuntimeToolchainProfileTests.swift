import DesignFlowKernel
import DRCEngine
import Foundation
import LayoutIO
import LayoutTech
import LVSEngine
import PEXEngine
import Testing
import ToolQualification
import Xcircuite
import XcircuiteFlowCLISupport
import DesignFlowKernel

extension XcircuiteFlowRuntimeTests {
    @Test func runtimeToolchainProfileFeedsDefaultSignoffTechnologyInputs() async throws {
        let root = try makeTemporaryRoot("runtime-toolchain-profile-signoff")
        defer { removeTemporaryRoot(root) }
        try writeLayoutCommandRequest(root: root)
        try writeStandardLayoutTechnology(root: root)
        try writePEXTechnology(root: root)
        try writeTechnologyCatalog(
            root: root,
            requiredFiles: [
                XcircuiteFlowTechnologyCatalogRequiredFile(
                    purpose: "layout-technology",
                    path: "process.json"
                ),
                XcircuiteFlowTechnologyCatalogRequiredFile(
                    purpose: "pex-technology",
                    path: "pex.json"
                ),
            ]
        )
        _ = try writeNetlist(
            """
            .subckt top
            .ends top
            """,
            name: "circuits/top.spice",
            root: root
        )
        let spec = XcircuiteFlowRuntimeSpec(
            toolchainProfile: XcircuiteFlowToolchainProfile(
                profileID: "local-signoff",
                pdkID: "test-pdk",
                technologyCatalogID: "test-catalog",
                technologyCatalogPath: "tech/catalog.json",
                drcTechnologyInput: .path("tech/process.json"),
                lvsTechnologyInput: .path("tech/process.json"),
                pexTechnology: .jsonFile(path: "tech/pex.json"),
                metadata: [
                    "source": "runtime-test",
                ]
            ),
            executors: [
                .layoutCommand(
                    XcircuiteFlowStageExecutorSpec.LayoutCommand(
                        stageID: "006-layout",
                        requestPath: "layout-command-request.json",
                        standardLayoutExports: [
                            LayoutCommandStandardLayoutExportSpec(
                                artifactID: "layout-gds",
                                format: .gds,
                                technologyInput: .path("tech/process.json")
                            ),
                        ],
                        tool: QualifiedToolFixtures.toolSpec(level: .smokeChecked)
                    )
                ),
                .nativeDRC(
                    XcircuiteFlowStageExecutorSpec.NativeDRC(
                        stageID: "007-drc",
                        layoutInput: .stageArtifact(
                            XcircuiteFlowInputReference.StageArtifact(
                                stageID: "006-layout",
                                artifactID: "layout-gds",
                                kind: .layout,
                                format: .gdsii
                            )
                        ),
                        layoutFormat: .gds,
                        topCell: "top",
                        tool: QualifiedToolFixtures.toolSpec(level: .productionEligible)
                    )
                ),
                .nativeLVS(
                    XcircuiteFlowStageExecutorSpec.NativeLVS(
                        stageID: "008-lvs",
                        layoutGDSInput: .stageArtifact(
                            XcircuiteFlowInputReference.StageArtifact(
                                stageID: "006-layout",
                                artifactID: "layout-gds",
                                kind: .layout,
                                format: .gdsii
                            )
                        ),
                        layoutFormat: .gds,
                        schematicNetlistPath: "circuits/top.spice",
                        topCell: "top",
                        tool: QualifiedToolFixtures.toolSpec(level: .productionEligible)
                    )
                ),
                .mockPEX(
                    XcircuiteFlowStageExecutorSpec.MockPEX(
                        stageID: "009-pex",
                        layoutInput: .stageArtifact(
                            XcircuiteFlowInputReference.StageArtifact(
                                stageID: "006-layout",
                                artifactID: "layout-gds",
                                kind: .layout,
                                format: .gdsii
                            )
                        ),
                        layoutFormat: .gds,
                        sourceNetlistPath: "circuits/top.spice",
                        topCell: "top",
                        corners: [PEXCorner(id: "tt")],
                        tool: mockPEXContractToolSpec()
                    )
                ),
            ]
        )
        let runtime = try spec.makeRuntime(projectRoot: root)

        let result = try await runtime.run(
            request: FlowOperationRequest(
                projectRoot: root,
                runID: "run-1",
                intent: "Apply a shared signoff toolchain profile",
                stages: [
                    FlowStageDefinition(
                        stageID: "006-layout",
                        displayName: "Layout command",
                        requiredTool: layoutCommandRequirement(requiredStandardOutputFormat: .gdsii)
                    ),
                    FlowStageDefinition(
                        stageID: "007-drc",
                        displayName: "DRC",
                        requiredTool: drcRequirement(requiredLayoutFormat: .gdsii)
                    ),
                    FlowStageDefinition(
                        stageID: "008-lvs",
                        displayName: "LVS",
                        requiredTool: lvsRequirement()
                    ),
                    FlowStageDefinition(
                        stageID: "009-pex",
                        displayName: "PEX",
                        requiredTool: mockPEXContractRequirement()
                    ),
                ]
            )
        )

        #expect(result.status == .succeeded)
        let drcStage = try #require(result.stages.first { $0.stageID == "007-drc" })
        let lvsStage = try #require(result.stages.first { $0.stageID == "008-lvs" })
        let pexStage = try #require(result.stages.first { $0.stageID == "009-pex" })
        #expect(drcStage.gates.contains { $0.gateID == "drc" && $0.status == .passed })
        #expect(lvsStage.gates.contains { $0.gateID == "lvs" && $0.status == .passed })
        #expect(pexStage.gates.contains { $0.gateID == "pex" && $0.status == .passed })
        #expect(drcStage.gates.contains { $0.gateID == "artifact-integrity" && $0.status == .passed })
        #expect(lvsStage.gates.contains { $0.gateID == "artifact-integrity" && $0.status == .passed })
        #expect(pexStage.gates.contains { $0.gateID == "artifact-integrity" && $0.status == .passed })
        #expect(drcStage.artifacts.contains { $0.artifactID == "drc-summary" })
        #expect(lvsStage.artifacts.contains { $0.artifactID == "lvs-summary" })
        #expect(pexStage.artifacts.contains { $0.artifactID == "pex-summary" })

        let toolchain = try readToolchainManifest(in: root, runID: "run-1")
        #expect(toolchain.profile?.profileID == "local-signoff")
        #expect(toolchain.profile?.pdkID == "test-pdk")
        #expect(toolchain.profile?.technologyCatalogID == "test-catalog")
        #expect(toolchain.profile?.technologyCatalogPath == "tech/catalog.json")
        #expect(toolchain.profile?.profileArtifactPath == ".xcircuite/runs/run-1/toolchain-profile.json")
        #expect(toolchain.profile?.drcTechnologyInput == .path("tech/process.json"))
        #expect(toolchain.profile?.lvsTechnologyInput == .path("tech/process.json"))
        #expect(toolchain.profile?.pexTechnology == .jsonFile(path: "tech/pex.json"))

        let persistedProfile = try XcircuitePackageStore().readJSON(
            XcircuiteFlowToolchainProfile.self,
            from: root.appending(path: ".xcircuite/runs/run-1/toolchain-profile.json")
        )
        #expect(persistedProfile.profileID == "local-signoff")
        #expect(persistedProfile.pdkID == "test-pdk")
        #expect(persistedProfile.technologyCatalogID == "test-catalog")
        #expect(persistedProfile.technologyCatalogPath == "tech/catalog.json")
        #expect(persistedProfile.metadata?["source"] == "runtime-test")

        let summary = try DefaultFlowRunLedgerInspector().inspectRun(
            runID: "run-1",
            projectRoot: root
        )
        #expect(summary.toolchain?.profileID == "local-signoff")
        #expect(summary.toolchain?.technologyCatalogPath == "tech/catalog.json")
        #expect(summary.toolchain?.profileArtifactPath == ".xcircuite/runs/run-1/toolchain-profile.json")

        let bundle = try DefaultFlowRunReviewBundler().makeReviewBundle(
            runID: "run-1",
            projectRoot: root
        )
        #expect(bundle.artifacts.contains {
            $0.role == "toolchain-profile"
                && $0.artifactID == "flow-toolchain-profile"
                && $0.path == ".xcircuite/runs/run-1/toolchain-profile.json"
        })
    }

    @Test func runtimeSpecRoundTripsToolchainProfile() throws {
        let spec = XcircuiteFlowRuntimeSpec(
            toolchainProfile: XcircuiteFlowToolchainProfile(
                profileID: "local-signoff",
                pdkID: "test-pdk",
                technologyCatalogID: "test-catalog",
                technologyCatalogPath: "tech/catalog.json",
                drcTechnologyInput: .path("tech/drc.json"),
                lvsTechnologyInput: .path("tech/lvs.json"),
                pexTechnology: .input(.path("tech/pex.json")),
                metadata: [
                    "owner": "signoff",
                ]
            ),
            executors: [
                .mockPEX(
                    XcircuiteFlowStageExecutorSpec.MockPEX(
                        stageID: "009-pex",
                        layoutPath: "layout/top.gds",
                        layoutFormat: .gds,
                        sourceNetlistPath: "circuits/top.spice",
                        topCell: "top",
                        corners: [PEXCorner(id: "tt")]
                    )
                ),
            ]
        )

        let data = try JSONEncoder().encode(spec)
        let decoded = try JSONDecoder().decode(XcircuiteFlowRuntimeSpec.self, from: data)
        let profile = try #require(decoded.toolchainProfile)

        #expect(profile.profileID == "local-signoff")
        #expect(profile.pdkID == "test-pdk")
        #expect(profile.technologyCatalogID == "test-catalog")
        #expect(profile.technologyCatalogPath == "tech/catalog.json")
        #expect(profile.metadata?["owner"] == "signoff")
        guard case .path(let drcPath) = try #require(profile.drcTechnologyInput) else {
            Issue.record("Expected DRC technology path")
            return
        }
        guard case .path(let lvsPath) = try #require(profile.lvsTechnologyInput) else {
            Issue.record("Expected LVS technology path")
            return
        }
        guard case .input(let pexTechnologyInput) = try #require(profile.pexTechnology) else {
            Issue.record("Expected PEX technology input")
            return
        }
        guard case .path(let pexPath) = pexTechnologyInput else {
            Issue.record("Expected PEX technology path")
            return
        }
        #expect(drcPath == "tech/drc.json")
        #expect(lvsPath == "tech/lvs.json")
        #expect(pexPath == "tech/pex.json")
    }

    @Test func runtimeSpecRejectsToolchainProfileMissingPDKID() throws {
        let spec = runtimeSpecWithProfile(
            XcircuiteFlowToolchainProfile(
                profileID: "local-signoff",
                technologyCatalogID: "test-catalog"
            )
        )

        do {
            try spec.validate()
            Issue.record("Expected missing toolchain profile field")
        } catch let error as XcircuiteFlowRuntimeSpecError {
            #expect(error == .missingToolchainProfileField("pdkID"))
        }
    }

    @Test func runtimeSpecRejectsToolchainProfileUnsafeTechnologyPath() throws {
        let spec = runtimeSpecWithProfile(
            XcircuiteFlowToolchainProfile(
                profileID: "local-signoff",
                pdkID: "test-pdk",
                technologyCatalogID: "test-catalog",
                drcTechnologyInput: .path("../tech/drc.json")
            )
        )

        do {
            try spec.validate()
            Issue.record("Expected invalid toolchain profile field")
        } catch let error as XcircuiteFlowRuntimeSpecError {
            #expect(error == .invalidToolchainProfileField("drcTechnologyInput"))
        }
    }

    @Test func runtimeSpecRejectsToolchainProfileInvalidStageArtifactSelector() throws {
        let spec = runtimeSpecWithProfile(
            XcircuiteFlowToolchainProfile(
                profileID: "local-signoff",
                pdkID: "test-pdk",
                technologyCatalogID: "test-catalog",
                lvsTechnologyInput: .stageArtifact(
                    XcircuiteFlowInputReference.StageArtifact(
                        stageID: "bad/stage",
                        artifactID: "layout-gds"
                    )
                )
            )
        )

        do {
            try spec.validate()
            Issue.record("Expected invalid toolchain profile field")
        } catch let error as XcircuiteFlowRuntimeSpecError {
            #expect(error == .invalidToolchainProfileField("lvsTechnologyInput.stageID"))
        }
    }

    @Test func toolchainProfileReadinessReportCapturesBlockingIssues() throws {
        let report = XcircuiteFlowToolchainProfileReadinessValidator().report(
            for: XcircuiteFlowToolchainProfile(
                profileID: "local-signoff",
                technologyCatalogID: "test-catalog",
                pexTechnology: .jsonFile(path: "../tech/pex.json")
            )
        )

        #expect(report.status == .failed)
        #expect(report.profileID == "local-signoff")
        #expect(report.technologyCatalogID == "test-catalog")
        #expect(report.issues.map(\.field) == ["pdkID", "pexTechnology.path"])
    }

    @Test func toolchainProfileReadinessReportValidatesTechnologyCatalogFiles() throws {
        let root = try makeTemporaryRoot("runtime-toolchain-profile-catalog")
        defer { removeTemporaryRoot(root) }
        let drcURL = root.appending(path: "tech/drc.json")
        let pexURL = root.appending(path: "tech/pex.json")
        try FileManager.default.createDirectory(
            at: drcURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("{}".utf8).write(to: drcURL)
        try Data("{}".utf8).write(to: pexURL)
        try writeTechnologyCatalog(
            root: root,
            requiredFiles: [
                XcircuiteFlowTechnologyCatalogRequiredFile(
                    purpose: "drc-rules",
                    path: "drc.json"
                ),
                XcircuiteFlowTechnologyCatalogRequiredFile(
                    purpose: "pex-rules",
                    path: "pex.json"
                ),
            ]
        )

        let report = XcircuiteFlowToolchainProfileReadinessValidator().report(
            for: XcircuiteFlowToolchainProfile(
                profileID: "local-signoff",
                pdkID: "test-pdk",
                technologyCatalogID: "test-catalog",
                technologyCatalogPath: "tech/catalog.json"
            ),
            projectRoot: root
        )

        #expect(report.status == .passed)
        #expect(report.technologyCatalogPath == "tech/catalog.json")
        #expect(report.issues.isEmpty)
    }

    @Test func runtimeSpecRejectsToolchainProfileCatalogPDKMismatch() throws {
        let root = try makeTemporaryRoot("runtime-toolchain-profile-catalog-pdk")
        defer { removeTemporaryRoot(root) }
        try writeTechnologyCatalog(
            root: root,
            pdkID: "other-pdk",
            requiredFiles: []
        )
        let spec = runtimeSpecWithProfile(
            XcircuiteFlowToolchainProfile(
                profileID: "local-signoff",
                pdkID: "test-pdk",
                technologyCatalogID: "test-catalog",
                technologyCatalogPath: "tech/catalog.json"
            )
        )

        do {
            try spec.validate(projectRoot: root)
            Issue.record("Expected catalog pdk mismatch")
        } catch let error as XcircuiteFlowRuntimeSpecError {
            #expect(error == .invalidToolchainProfileField("pdkID"))
        } catch {
            throw error
        }
    }

    @Test func runtimeSpecRejectsToolchainProfileMissingCatalogRequiredFile() throws {
        let root = try makeTemporaryRoot("runtime-toolchain-profile-catalog-required")
        defer { removeTemporaryRoot(root) }
        try writeTechnologyCatalog(
            root: root,
            requiredFiles: [
                XcircuiteFlowTechnologyCatalogRequiredFile(
                    purpose: "drc-rules",
                    path: "missing-drc.json"
                ),
            ]
        )
        let spec = runtimeSpecWithProfile(
            XcircuiteFlowToolchainProfile(
                profileID: "local-signoff",
                pdkID: "test-pdk",
                technologyCatalogID: "test-catalog",
                technologyCatalogPath: "tech/catalog.json"
            )
        )

        do {
            try spec.validate(projectRoot: root)
            Issue.record("Expected missing catalog required file")
        } catch let error as XcircuiteFlowRuntimeSpecError {
            #expect(error == .invalidToolchainProfileField("technologyCatalog.requiredFiles.drc-rules"))
        } catch {
            throw error
        }
    }

    @Test func validateCLIRejectsMissingCatalogRequiredFileWithProjectRoot() async throws {
        let root = try makeTemporaryRoot("runtime-cli-validate-catalog-required")
        defer { removeTemporaryRoot(root) }
        try writeTechnologyCatalog(
            root: root,
            requiredFiles: [
                XcircuiteFlowTechnologyCatalogRequiredFile(
                    purpose: "drc-rules",
                    path: "missing-drc.json"
                ),
            ]
        )
        let runtimeURL = try writeRuntimeSpec(
            runtimeSpecWithProfile(
                XcircuiteFlowToolchainProfile(
                    profileID: "local-signoff",
                    pdkID: "test-pdk",
                    technologyCatalogID: "test-catalog",
                    technologyCatalogPath: "tech/catalog.json"
                )
            ),
            root: root
        )

        do {
            _ = try await XcircuiteFlowCLICommand.run(
                arguments: [
                    "validate",
                    "--project-root",
                    root.path(percentEncoded: false),
                    "--runtime-config",
                    runtimeURL.path(percentEncoded: false),
                ]
            )
            Issue.record("Expected CLI catalog required file validation error")
        } catch let error as XcircuiteFlowRuntimeSpecError {
            #expect(error == .invalidToolchainProfileField("technologyCatalog.requiredFiles.drc-rules"))
        } catch {
            throw error
        }
    }

    @Test func inspectToolchainProfileCLIReportsCatalogReadiness() async throws {
        let root = try makeTemporaryRoot("runtime-cli-inspect-profile-catalog")
        defer { removeTemporaryRoot(root) }
        let drcURL = root.appending(path: "tech/drc.json")
        try FileManager.default.createDirectory(
            at: drcURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("{}".utf8).write(to: drcURL)
        try writeTechnologyCatalog(
            root: root,
            requiredFiles: [
                XcircuiteFlowTechnologyCatalogRequiredFile(
                    purpose: "drc-rules",
                    path: "drc.json"
                ),
            ]
        )
        let runtimeURL = try writeRuntimeSpec(
            runtimeSpecWithProfile(
                XcircuiteFlowToolchainProfile(
                    profileID: "local-signoff",
                    pdkID: "test-pdk",
                    technologyCatalogID: "test-catalog",
                    technologyCatalogPath: "tech/catalog.json"
                )
            ),
            root: root
        )

        let json = try await XcircuiteFlowCLICommand.run(
            arguments: [
                "inspect-toolchain-profile",
                "--project-root",
                root.path(percentEncoded: false),
                "--runtime-config",
                runtimeURL.path(percentEncoded: false),
                "--pretty",
            ]
        )
        let data = try #require(json.data(using: .utf8))
        let inspection = try JSONDecoder().decode(
            XcircuiteFlowToolchainProfileInspection.self,
            from: data
        )

        #expect(inspection.status == .passed)
        #expect(inspection.profilePresent)
        #expect(inspection.runtimeConfigPath == runtimeURL.path(percentEncoded: false))
        #expect(inspection.projectRootPath == root.path(percentEncoded: false))
        #expect(inspection.readinessReport?.status == .passed)
        #expect(inspection.readinessReport?.issues.isEmpty == true)
    }

    @Test func inspectToolchainProfileCLIReportsFailedCatalogReadinessWithoutThrowing() async throws {
        let root = try makeTemporaryRoot("runtime-cli-inspect-profile-failed-catalog")
        defer { removeTemporaryRoot(root) }
        try writeTechnologyCatalog(
            root: root,
            requiredFiles: [
                XcircuiteFlowTechnologyCatalogRequiredFile(
                    purpose: "drc-rules",
                    path: "missing-drc.json"
                ),
            ]
        )
        let runtimeURL = try writeRuntimeSpec(
            runtimeSpecWithProfile(
                XcircuiteFlowToolchainProfile(
                    profileID: "local-signoff",
                    pdkID: "test-pdk",
                    technologyCatalogID: "test-catalog",
                    technologyCatalogPath: "tech/catalog.json"
                )
            ),
            root: root
        )

        let json = try await XcircuiteFlowCLICommand.run(
            arguments: [
                "inspect-toolchain-profile",
                "--project-root",
                root.path(percentEncoded: false),
                "--runtime-config",
                runtimeURL.path(percentEncoded: false),
            ]
        )
        let data = try #require(json.data(using: .utf8))
        let inspection = try JSONDecoder().decode(
            XcircuiteFlowToolchainProfileInspection.self,
            from: data
        )

        #expect(inspection.status == .failed)
        #expect(inspection.profilePresent)
        #expect(inspection.readinessReport?.status == .failed)
        #expect(inspection.readinessReport?.issues.map(\.field) == [
            "technologyCatalog.requiredFiles.drc-rules",
        ])
    }

    @Test func inspectToolchainProfileCLIReportsMissingOptionalProfile() async throws {
        let root = try makeTemporaryRoot("runtime-cli-inspect-profile-not-present")
        defer { removeTemporaryRoot(root) }
        let runtimeURL = try writeRuntimeSpec(
            XcircuiteFlowRuntimeSpec(
                executors: [
                    .coreSpiceSimulation(
                        XcircuiteFlowStageExecutorSpec.CoreSpiceSimulation(
                            stageID: "010-sim",
                            netlistPath: "circuits/top.spice"
                        )
                    ),
                ]
            ),
            root: root
        )

        let json = try await XcircuiteFlowCLICommand.run(
            arguments: [
                "inspect-toolchain-profile",
                "--runtime-config",
                runtimeURL.path(percentEncoded: false),
            ]
        )
        let data = try #require(json.data(using: .utf8))
        let inspection = try JSONDecoder().decode(
            XcircuiteFlowToolchainProfileInspection.self,
            from: data
        )

        #expect(inspection.status == .notPresent)
        #expect(!inspection.profilePresent)
        #expect(inspection.runtimeConfigPath == runtimeURL.path(percentEncoded: false))
        #expect(inspection.projectRootPath == nil)
        #expect(inspection.readinessReport == nil)
    }

    @Test func inspectTechnologyCatalogCLIReportsEntriesAndRequiredFiles() async throws {
        let root = try makeTemporaryRoot("runtime-cli-inspect-catalog")
        defer { removeTemporaryRoot(root) }
        let drcURL = root.appending(path: "tech/drc.json")
        try FileManager.default.createDirectory(
            at: drcURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("{}".utf8).write(to: drcURL)
        try writeTechnologyCatalog(
            root: root,
            requiredFiles: [
                XcircuiteFlowTechnologyCatalogRequiredFile(
                    purpose: "drc-rules",
                    path: "drc.json"
                ),
            ]
        )

        let json = try await XcircuiteFlowCLICommand.run(
            arguments: [
                "inspect-technology-catalog",
                "--project-root",
                root.path(percentEncoded: false),
                "--catalog-path",
                "tech/catalog.json",
                "--pretty",
            ]
        )
        let data = try #require(json.data(using: .utf8))
        let inventory = try JSONDecoder().decode(
            XcircuiteFlowTechnologyCatalogInventory.self,
            from: data
        )
        let catalog = try #require(inventory.catalogs.first)
        let entry = try #require(catalog.entries.first)
        let requiredFile = try #require(entry.requiredFiles.first)

        #expect(inventory.status == .passed)
        #expect(inventory.catalogCount == 1)
        #expect(inventory.entryCount == 1)
        #expect(inventory.missingRequiredFileCount == 0)
        #expect(catalog.status == .passed)
        #expect(entry.technologyCatalogID == "test-catalog")
        #expect(entry.pdkID == "test-pdk")
        #expect(requiredFile.status == .passed)
        #expect(requiredFile.exists)
        #expect(requiredFile.resolvedPath == drcURL.path(percentEncoded: false))
    }

    @Test func inspectTechnologyCatalogCLIReportsMissingRequiredFileWithoutThrowing() async throws {
        let root = try makeTemporaryRoot("runtime-cli-inspect-catalog-missing-file")
        defer { removeTemporaryRoot(root) }
        try writeTechnologyCatalog(
            root: root,
            requiredFiles: [
                XcircuiteFlowTechnologyCatalogRequiredFile(
                    purpose: "drc-rules",
                    path: "missing-drc.json"
                ),
            ]
        )

        let json = try await XcircuiteFlowCLICommand.run(
            arguments: [
                "inspect-technology-catalog",
                "--project-root",
                root.path(percentEncoded: false),
                "--catalog-path",
                "tech/catalog.json",
            ]
        )
        let data = try #require(json.data(using: .utf8))
        let inventory = try JSONDecoder().decode(
            XcircuiteFlowTechnologyCatalogInventory.self,
            from: data
        )
        let requiredFile = try #require(inventory.catalogs.first?.entries.first?.requiredFiles.first)

        #expect(inventory.status == .failed)
        #expect(inventory.failedCatalogCount == 1)
        #expect(inventory.failedEntryCount == 1)
        #expect(inventory.missingRequiredFileCount == 1)
        #expect(requiredFile.status == .failed)
        #expect(requiredFile.issues.map(\.code) == ["missing-required-file"])
    }

    @Test func inspectTechnologyCatalogCLIDiscoversRuntimeProfileCatalogAndDeduplicates() async throws {
        let root = try makeTemporaryRoot("runtime-cli-inspect-catalog-runtime")
        defer { removeTemporaryRoot(root) }
        let drcURL = root.appending(path: "tech/drc.json")
        try FileManager.default.createDirectory(
            at: drcURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("{}".utf8).write(to: drcURL)
        try writeTechnologyCatalog(
            root: root,
            requiredFiles: [
                XcircuiteFlowTechnologyCatalogRequiredFile(
                    purpose: "drc-rules",
                    path: "drc.json"
                ),
            ]
        )
        let runtimeURL = try writeRuntimeSpec(
            runtimeSpecWithProfile(
                XcircuiteFlowToolchainProfile(
                    profileID: "local-signoff",
                    pdkID: "test-pdk",
                    technologyCatalogID: "test-catalog",
                    technologyCatalogPath: "tech/catalog.json"
                )
            ),
            root: root
        )

        let json = try await XcircuiteFlowCLICommand.run(
            arguments: [
                "inspect-technology-catalog",
                "--project-root",
                root.path(percentEncoded: false),
                "--runtime-config",
                runtimeURL.path(percentEncoded: false),
                "--catalog-path",
                "tech/catalog.json",
            ]
        )
        let data = try #require(json.data(using: .utf8))
        let inventory = try JSONDecoder().decode(
            XcircuiteFlowTechnologyCatalogInventory.self,
            from: data
        )

        #expect(inventory.status == .passed)
        #expect(inventory.catalogCount == 1)
        #expect(inventory.catalogs.first?.catalogPath == "tech/catalog.json")
    }

    @Test func inspectTechnologyCatalogCLIDiscoversCatalogsFromPDKRootAndResolvesRequiredFiles() async throws {
        let root = try makeTemporaryRoot("runtime-cli-inspect-catalog-pdk-root")
        defer { removeTemporaryRoot(root) }
        let pdkRoot = root.appending(path: "pdks/test-pdk")
        let drcURL = pdkRoot.appending(path: "rules/drc.json")
        try FileManager.default.createDirectory(
            at: drcURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("{}".utf8).write(to: drcURL)
        try writeTechnologyCatalog(
            root: root,
            catalogPath: "pdks/test-pdk/tech/catalog.json",
            requiredFiles: [
                XcircuiteFlowTechnologyCatalogRequiredFile(
                    purpose: "drc-rules",
                    path: "rules/drc.json"
                ),
            ]
        )

        let json = try await XcircuiteFlowCLICommand.run(
            arguments: [
                "inspect-technology-catalog",
                "--project-root",
                root.path(percentEncoded: false),
                "--pdk-root",
                "pdks/test-pdk",
                "--pretty",
            ]
        )
        let data = try #require(json.data(using: .utf8))
        let inventory = try JSONDecoder().decode(
            XcircuiteFlowTechnologyCatalogInventory.self,
            from: data
        )
        let pdkRootInventory = try #require(inventory.pdkRoots.first)
        let requiredFile = try #require(inventory.catalogs.first?.entries.first?.requiredFiles.first)

        #expect(inventory.status == .passed)
        #expect(inventory.discoveredCatalogCount == 1)
        #expect(inventory.catalogCount == 1)
        #expect(inventory.missingRequiredFileCount == 0)
        #expect(pdkRootInventory.status == .passed)
        #expect(pdkRootInventory.discoveredCatalogPaths.first?.hasSuffix(
            "/pdks/test-pdk/tech/catalog.json"
        ) == true)
        #expect(requiredFile.status == .passed)
        #expect(requiredFile.exists)
        #expect(requiredFile.resolutionSource == "pdk-root")
        #expect(requiredFile.resolvedPath == drcURL.path(percentEncoded: false))
    }

    @Test func inspectTechnologyCatalogCLIReportsPDKRootWithoutCatalogAsStructuredFailure() async throws {
        let root = try makeTemporaryRoot("runtime-cli-inspect-catalog-empty-pdk-root")
        defer { removeTemporaryRoot(root) }
        try FileManager.default.createDirectory(
            at: root.appending(path: "pdks/empty-pdk"),
            withIntermediateDirectories: true
        )

        let json = try await XcircuiteFlowCLICommand.run(
            arguments: [
                "inspect-technology-catalog",
                "--project-root",
                root.path(percentEncoded: false),
                "--pdk-root",
                "pdks/empty-pdk",
            ]
        )
        let data = try #require(json.data(using: .utf8))
        let inventory = try JSONDecoder().decode(
            XcircuiteFlowTechnologyCatalogInventory.self,
            from: data
        )

        #expect(inventory.status == .failed)
        #expect(inventory.catalogCount == 0)
        #expect(inventory.pdkRoots.first?.status == .passed)
        #expect(inventory.issues.map(\.code) == ["no-technology-catalogs-found"])
    }

    @Test func inspectTechnologyCatalogCLIReportsRelativePathWithoutProjectRoot() async throws {
        let json = try await XcircuiteFlowCLICommand.run(
            arguments: [
                "inspect-technology-catalog",
                "--catalog-path",
                "tech/catalog.json",
            ]
        )
        let data = try #require(json.data(using: .utf8))
        let inventory = try JSONDecoder().decode(
            XcircuiteFlowTechnologyCatalogInventory.self,
            from: data
        )

        #expect(inventory.status == .failed)
        #expect(inventory.catalogCount == 1)
        #expect(inventory.failedCatalogCount == 1)
        #expect(inventory.catalogs.first?.issues.map(\.code) == ["missing-project-root"])
    }

}
