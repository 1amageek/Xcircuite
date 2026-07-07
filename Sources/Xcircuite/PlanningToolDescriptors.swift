import Foundation
import ToolQualification
import XcircuitePackage

public enum PlanningToolDescriptors {
    public static func symbolicPlannerSolver(
        toolID: String = "external-symbolic-planner",
        displayName: String = "External Symbolic Planner",
        version: String = "external",
        executablePath: String,
        level: ToolQualificationLevel = .unknown
    ) -> ToolDescriptor {
        ToolDescriptor(
            toolID: toolID,
            displayName: displayName,
            kind: .planning,
            version: version,
            capabilities: [
                ToolCapability(
                    operationID: "solve-pddl-symbolic-plan",
                    inputFormats: [.text],
                    outputFormats: [.text, .json],
                    limitations: [
                        "Qualification is scoped to the PDDL subset and corpus cases recorded in the run artifacts.",
                    ]
                ),
            ],
            trustProfile: ToolTrustProfile(
                level: level,
                knownLimitations: [
                    "External solver acceptance still requires typed candidate-plan verification.",
                ]
            ),
            environment: ToolEnvironment(
                executablePath: executablePath,
                platform: "macOS"
            )
        )
    }
}
