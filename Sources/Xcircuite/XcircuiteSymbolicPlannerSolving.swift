import Foundation

public protocol XcircuiteSymbolicPlannerSolving: Sendable {
    func solve(
        request: XcircuiteSymbolicPlannerSolverRequest,
        projectRoot: URL
    ) async throws -> XcircuiteSymbolicPlannerSolverResult
}
