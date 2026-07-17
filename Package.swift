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
        .executable(name: "xcircuite-flow", targets: ["XcircuiteFlowCLI"]),
    ],
    dependencies: [
        workspaceDependency(
            named: "CircuiteFoundation",
            revision: "2ec6ee13a89ac6885be3c26b41a9ee0ef89948ac"
        ),
        workspaceDependency(
            named: "ToolQualification",
            revision: "f6cacdbf64038a35ab62d70f575a8dd8349e5604"
        ),
        workspaceDependency(
            named: "DesignFlowKernel",
            revision: "68e247274e34e56b1337df125b74480196209901"
        ),
        workspaceDependency(
            named: "DRCEngine",
            revision: "4ea4f288c43a66bad93863eb88010966d721732f"
        ),
        workspaceDependency(
            named: "LVSEngine",
            revision: "959e21f770c44c2e5a49b33964d2ba82555736b7"
        ),
        workspaceDependency(
            named: "PEXEngine",
            revision: "f3078e12af274a714e27ec523f19c5c29abd42dd"
        ),
        workspaceDependency(
            named: "CoreSpice",
            revision: "a1dff52b12f40bca8696aee914d7d65d55e6fed5"
        ),
        workspaceDependency(
            named: "semiconductor-layout",
            revision: "61cc2be603f57d12f3c582a2fc0fd148c1e62ad9"
        ),
        workspaceDependency(
            named: "SignoffToolSupport",
            revision: "2c8ce00a8f873934e74e3f219e0cbd122a862fe9"
        ),
        workspaceDependency(
            named: "PDKKit",
            revision: "28f3b83304ad2bbb0c2e0269d26616081d90d992"
        ),
        workspaceDependency(
            named: "LogicDesign",
            revision: "09768ed203d97d1d0f79f786f9988fcb2cd39155"
        ),
        workspaceDependency(
            named: "TimingEngine",
            revision: "81898ed51ab05c62712ebca5b1b03869b89f7682"
        ),
        workspaceDependency(
            named: "LogicEngine",
            revision: "52c24ed6b5e6406fd462b9276cf449ffd50003d4"
        ),
        workspaceDependency(
            named: "RTLVerificationEngine",
            revision: "efc9a5fc580edb2aedeaae4b8a682fb45266af73"
        ),
        workspaceDependency(
            named: "DFTEngine",
            revision: "724015a944ca0ec10084600a269bd37a8d014801"
        ),
        workspaceDependency(
            named: "PhysicalDesignEngine",
            revision: "a98c0895c0c0340326f79d7838ddc37ba86cfa2b"
        ),
        workspaceDependency(
            named: "ElectricalSignoffEngine",
            revision: "328ded423f3bc925e202b3ae7e2be925b11c030b"
        ),
        workspaceDependency(
            named: "ReleaseEngine",
            revision: "28c77369345a536905e9c80ebd16ad3f6040bb63"
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
                .product(name: "PhysicalDesignEngine", package: "PhysicalDesignEngine"),
                .product(name: "PhysicalDesignCore", package: "PhysicalDesignEngine"),
                .product(name: "ElectricalSignoffCore", package: "ElectricalSignoffEngine"),
                .product(name: "ElectricalSignoffEngine", package: "ElectricalSignoffEngine"),
                .product(name: "ElectricalSignoffEvidence", package: "ElectricalSignoffEngine"),
                .product(name: "ReleaseEngine", package: "ReleaseEngine"),
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
