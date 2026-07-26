// swift-tools-version: 6.3
import PackageDescription
import Foundation

let workspaceRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let isLSIWorkspace = FileManager.default.fileExists(
    atPath: workspaceRoot
        .appendingPathComponent("docs")
        .appendingPathComponent("workspace-packages.json")
        .path
)

func workspaceDependency(named name: String, revision: String) -> Package.Dependency {
    let siblingManifest = workspaceRoot
        .appendingPathComponent(name)
        .appendingPathComponent("Package.swift")

    if isLSIWorkspace,
       FileManager.default.fileExists(atPath: siblingManifest.path) {
        return .package(path: "../\(name)")
    }

    return .package(
        url: "https://github.com/1amageek/\(name).git",
        revision: revision
    )
}

let package = Package(
    name: "Xcircuite",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "Xcircuite", targets: ["Xcircuite"]),
        .library(name: "XcircuiteFlowCLISupport", targets: ["XcircuiteFlowCLISupport"]),
        .executable(name: "xcircuite-flow", targets: ["XcircuiteFlowCLI"]),
    ],
    dependencies: [
        workspaceDependency(
            named: "CircuiteFoundation",
            revision: "dc792c88e189c822c9f83ea86cf139ee68560dca"
        ),
        workspaceDependency(
            named: "ToolQualification",
            revision: "c489783a5673bc2dd0b94c438c2f53a65d9a2d8b"
        ),
        workspaceDependency(
            named: "DesignFlowKernel",
            revision: "5d60047c1c322ed3f8fc741ebee1f35ce7a99533"
        ),
        workspaceDependency(
            named: "DRCEngine",
            revision: "aefe34029acc01c3dc600f6f826125479bfc3153"
        ),
        workspaceDependency(
            named: "LVSEngine",
            revision: "97d308443b131dc00611622da42a48e12e5eb398"
        ),
        workspaceDependency(
            named: "PEXEngine",
            revision: "c2dc912203790d862a2055bd6abd9a0a1dc86b6b"
        ),
        workspaceDependency(
            named: "CoreSpice",
            revision: "d8161966cc53bf1f4deec81f4250ae08bb03fe0c"
        ),
        workspaceDependency(
            named: "semiconductor-layout",
            revision: "d4dda0ce9dd60e5f5aeaf171c2e563bf0685ceb9"
        ),
        workspaceDependency(
            named: "SignoffToolSupport",
            revision: "2c36104106bdfc8c279629c162c3ced9d7401328"
        ),
        workspaceDependency(
            named: "PDKKit",
            revision: "3ab7e3b6094d2de672b582d90076cf58b6527766"
        ),
        workspaceDependency(
            named: "LogicDesign",
            revision: "e8f8e1dace0445ddd816929c4ca0fe17cca12a7b"
        ),
        workspaceDependency(
            named: "TimingEngine",
            revision: "7809651994017a932314b747b948ac14e32e779b"
        ),
        workspaceDependency(
            named: "LogicEngine",
            revision: "f162f844b9e5f29da2307f3620a069cc37255fb6"
        ),
        workspaceDependency(
            named: "RTLVerificationEngine",
            revision: "b03ccaa2b7c88e167c089ee5a28a67bd082108dc"
        ),
        workspaceDependency(
            named: "DFTEngine",
            revision: "5acd86d91b0827fceb02cab0931bcad546202dae"
        ),
        workspaceDependency(
            named: "PhysicalDesignEngine",
            revision: "a7bf05dc88da9daea37e256c32d73418484d2a28"
        ),
        workspaceDependency(
            named: "ElectricalSignoffEngine",
            revision: "219fc4b853b0a1deca43e18c6e4acab01e7262b1"
        ),
        workspaceDependency(
            named: "ReleaseEngine",
            revision: "6048a43350f589eb2505cc989029bf29024c3245"
        ),
    ],
    targets: [
        .target(
            name: "Xcircuite",
            dependencies: [
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
                .product(name: "ToolQualification", package: "ToolQualification"),
                .product(name: "DesignFlowKernel", package: "DesignFlowKernel"),
                .product(name: "DRCEngine", package: "DRCEngine"),
                .product(name: "LVSEngine", package: "LVSEngine"),
                .product(name: "PEXEngine", package: "PEXEngine"),
                .product(name: "CoreSpice", package: "CoreSpice"),
                .product(name: "CoreSpiceIO", package: "CoreSpice"),
                .product(name: "LayoutCore", package: "semiconductor-layout"),
                .product(name: "LayoutTech", package: "semiconductor-layout"),
                .product(name: "LayoutIO", package: "semiconductor-layout"),
                .product(name: "LayoutCommands", package: "semiconductor-layout"),
                .product(name: "SignoffToolSupport", package: "SignoffToolSupport"),
                .product(name: "PDKKit", package: "PDKKit"),
                .product(name: "PDKCore", package: "PDKKit"),
                .product(name: "PDKDiscovery", package: "PDKKit"),
                .product(name: "PDKStandardViews", package: "PDKKit"),
                .product(name: "PDKValidation", package: "PDKKit"),
                .product(name: "LogicDesign", package: "LogicDesign"),
                .product(name: "LogicIR", package: "LogicDesign"),
                .product(name: "PowerIntent", package: "LogicDesign"),
                .product(name: "SystemVerilogFrontend", package: "LogicDesign"),
                .product(name: "TimingEngine", package: "TimingEngine"),
                .product(name: "STAEngine", package: "TimingEngine"),
                .product(name: "SignalIntegrityEngine", package: "TimingEngine"),
                .product(name: "TimingCore", package: "TimingEngine"),
                .product(name: "LogicEngine", package: "LogicEngine"),
                .product(name: "LogicEngineCore", package: "LogicEngine"),
                .product(name: "LogicLowering", package: "LogicEngine"),
                .product(name: "LogicSimulation", package: "LogicEngine"),
                .product(name: "LogicSynthesis", package: "LogicEngine"),
                .product(name: "LogicEvidence", package: "LogicEngine"),
                .product(name: "RTLVerificationEngine", package: "RTLVerificationEngine"),
                .product(name: "RTLVerificationCore", package: "RTLVerificationEngine"),
                .product(name: "DFTCore", package: "DFTEngine"),
                .product(name: "DFTEngine", package: "DFTEngine"),
                .product(name: "ATPGEngine", package: "DFTEngine"),
                .product(name: "PhysicalDesignEngine", package: "PhysicalDesignEngine"),
                .product(name: "PhysicalDesignCore", package: "PhysicalDesignEngine"),
                .product(name: "ElectricalSignoffCore", package: "ElectricalSignoffEngine"),
                .product(name: "ElectricalSignoffEngine", package: "ElectricalSignoffEngine"),
                .product(name: "ElectricalSignoffEvidence", package: "ElectricalSignoffEngine"),
                .product(name: "ReleaseEngine", package: "ReleaseEngine"),
                .product(name: "ReleaseCore", package: "ReleaseEngine"),
                .product(name: "SignoffEngine", package: "ReleaseEngine"),
                .product(name: "TapeoutEngine", package: "ReleaseEngine"),
            ]
        ),
        .target(
            name: "XcircuiteFlowCLISupport",
            dependencies: [
                "Xcircuite",
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
                .product(name: "DesignFlowKernel", package: "DesignFlowKernel"),
            ]
        ),
        .executableTarget(
            name: "XcircuiteFlowCLI",
            dependencies: ["XcircuiteFlowCLISupport"]
        ),
        .testTarget(
            name: "XcircuiteTests",
            dependencies: [
                "Xcircuite",
                "XcircuiteFlowCLISupport",
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
                .product(name: "DRCEngine", package: "DRCEngine"),
                .product(name: "LVSEngine", package: "LVSEngine"),
                .product(name: "PEXEngine", package: "PEXEngine"),
                .product(name: "CoreSpice", package: "CoreSpice"),
                .product(name: "DesignFlowKernel", package: "DesignFlowKernel"),
                .product(name: "ToolQualification", package: "ToolQualification"),
                .product(name: "RTLVerificationEngine", package: "RTLVerificationEngine"),
                .product(name: "RTLVerificationCore", package: "RTLVerificationEngine"),
                .product(name: "LogicIR", package: "LogicDesign"),
                .product(name: "PowerIntent", package: "LogicDesign"),
                .product(name: "SystemVerilogFrontend", package: "LogicDesign"),
                .product(name: "LogicEngineCore", package: "LogicEngine"),
                .product(name: "LogicLowering", package: "LogicEngine"),
                .product(name: "LogicSimulation", package: "LogicEngine"),
                .product(name: "LogicSynthesis", package: "LogicEngine"),
                .product(name: "LogicEvidence", package: "LogicEngine"),
                .product(name: "PhysicalDesignCore", package: "PhysicalDesignEngine"),
                .product(name: "DFTCore", package: "DFTEngine"),
                .product(name: "PDKCore", package: "PDKKit"),
                .product(name: "PDKDiscovery", package: "PDKKit"),
                .product(name: "PDKStandardViews", package: "PDKKit"),
                .product(name: "PDKValidation", package: "PDKKit"),
                .product(name: "TimingCore", package: "TimingEngine"),
                .product(name: "LayoutAutoGen", package: "semiconductor-layout"),
                .product(name: "LayoutLVSExtraction", package: "semiconductor-layout"),
                .product(name: "LayoutCore", package: "semiconductor-layout"),
                .product(name: "LayoutIO", package: "semiconductor-layout"),
                .product(name: "LayoutTech", package: "semiconductor-layout"),
                .product(name: "ElectricalSignoffCore", package: "ElectricalSignoffEngine"),
                .product(name: "ElectricalSignoffEngine", package: "ElectricalSignoffEngine"),
                .product(name: "ElectricalSignoffEvidence", package: "ElectricalSignoffEngine"),
                .product(name: "ReleaseCore", package: "ReleaseEngine"),
                .product(name: "SignoffEngine", package: "ReleaseEngine"),
                .product(name: "TapeoutEngine", package: "ReleaseEngine"),
            ],
            resources: [
                .copy("Fixtures"),
            ]
        ),
    ]
)
