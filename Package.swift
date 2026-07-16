// swift-tools-version: 6.3
import PackageDescription
import Foundation

let workspaceRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()

func workspaceDependency(named name: String, revision: String) -> Package.Dependency {
    let siblingManifest = workspaceRoot
        .appendingPathComponent(name)
        .appendingPathComponent("Package.swift")

    if FileManager.default.fileExists(atPath: siblingManifest.path) {
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
            revision: "1856a1bc5660febbe2f0358d3e5e0262e496b3d3"
        ),
        workspaceDependency(
            named: "DesignFlowKernel",
            revision: "5a8e7452bc04e10455f64b380aad8ffc7645371b"
        ),
        workspaceDependency(
            named: "DRCEngine",
            revision: "1fe16e33b370d8123071e296095261d4e8f8b21d"
        ),
        workspaceDependency(
            named: "LVSEngine",
            revision: "6787b1dead085e5073f8a7cec10a2cf5c7d14037"
        ),
        workspaceDependency(
            named: "PEXEngine",
            revision: "e60a3b1fdb27879fd95c41a81c313750f7a45485"
        ),
        workspaceDependency(
            named: "CoreSpice",
            revision: "20d5663a05b9dd98acc1171a8936eda22713add1"
        ),
        workspaceDependency(
            named: "semiconductor-layout",
            revision: "eb4f8ac93dbe4c35410ae55e6bb00794376c8333"
        ),
        workspaceDependency(
            named: "SignoffToolSupport",
            revision: "7bfd1864edd147c59a1dc79e58f297120d165323"
        ),
        workspaceDependency(
            named: "PDKKit",
            revision: "29cc9f6f8d24562a7dcb5fd43d8dc6437e695c21"
        ),
        workspaceDependency(
            named: "LogicDesign",
            revision: "cc39c974bf14624e6ce29fd8722620385fde0762"
        ),
        workspaceDependency(
            named: "TimingEngine",
            revision: "0fecd6f568c7c21ec98ddc3b96aad8eacac44c8c"
        ),
        workspaceDependency(
            named: "LogicEngine",
            revision: "c8b51432501d67b5b790032dbb9ce150cf1f69ea"
        ),
        workspaceDependency(
            named: "RTLVerificationEngine",
            revision: "b76251c49f2eca89cacd549f864b7fb1f5acd832"
        ),
        workspaceDependency(
            named: "DFTEngine",
            revision: "e9547539f8f9522c300c4aa9ee3d983049d50bc4"
        ),
        workspaceDependency(
            named: "PhysicalDesignEngine",
            revision: "43e4c92c03386a3bbce8311e146ec5bdce41b229"
        ),
        workspaceDependency(
            named: "ElectricalSignoffEngine",
            revision: "136aab262566e66dc3783dbcaaee6e290ff3df28"
        ),
        workspaceDependency(
            named: "ReleaseEngine",
            revision: "2fd9c5c787537702279d0ab7f5661dcc12abf4ec"
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
