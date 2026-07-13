import CoreSpiceIO
import Foundation
import LayoutCommands
import LayoutCore
import LayoutIO
import LayoutTech
import LVSEngine
import DesignFlowKernel

extension XcircuiteCandidatePlanExecutor {
    func projectRelativePath(for url: URL, projectRoot: URL) throws -> String {
        try ProjectPathBoundary().relativePath(for: url, projectRoot: projectRoot)
    }

    func runActionSeverity(_ severity: String) -> XcircuiteRunActionDiagnosticSeverity {
        switch severity {
        case "info":
            return .info
        case "warning":
            return .warning
        default:
            return .error
        }
    }
}
