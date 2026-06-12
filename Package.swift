// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "Xcircuite",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "Xcircuite", targets: ["Xcircuite"]),
    ],
    dependencies: [
        .package(path: "../XcircuitePackage"),
        .package(path: "../ToolQualification"),
        .package(path: "../DesignFlowKernel"),
        .package(path: "../DRCEngine"),
        .package(path: "../LVSEngine"),
        .package(path: "../PEXEngine"),
        .package(path: "../CoreSpice"),
    ],
    targets: [
        .target(
            name: "Xcircuite",
            dependencies: [
                .product(name: "XcircuitePackage", package: "XcircuitePackage"),
                .product(name: "ToolQualification", package: "ToolQualification"),
                .product(name: "DesignFlowKernel", package: "DesignFlowKernel"),
                .product(name: "DRCEngine", package: "DRCEngine"),
                .product(name: "LVSEngine", package: "LVSEngine"),
                .product(name: "PEXEngine", package: "PEXEngine"),
                .product(name: "CoreSpice", package: "CoreSpice"),
                .product(name: "CoreSpiceIO", package: "CoreSpice"),
            ]
        ),
        .testTarget(
            name: "XcircuiteTests",
            dependencies: [
                "Xcircuite",
                .product(name: "DRCEngine", package: "DRCEngine"),
                .product(name: "LVSEngine", package: "LVSEngine"),
                .product(name: "PEXEngine", package: "PEXEngine"),
                .product(name: "DesignFlowKernel", package: "DesignFlowKernel"),
                .product(name: "ToolQualification", package: "ToolQualification"),
                .product(name: "XcircuitePackage", package: "XcircuitePackage"),
            ]
        ),
    ]
)
