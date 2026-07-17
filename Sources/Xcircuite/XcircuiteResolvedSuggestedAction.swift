import DesignFlowKernel
import Foundation

/// A semantic flow action projected into the local Xcircuite CLI surface.
public struct XcircuiteResolvedSuggestedAction: Sendable, Hashable, Codable {
    public var selection: FlowRunSuggestedActionSelection
    public var command: XcircuiteFlowActionCommand
    public var dispatchArguments: [String]

    public init(
        selection: FlowRunSuggestedActionSelection,
        command: XcircuiteFlowActionCommand,
        dispatchArguments: [String]
    ) {
        self.selection = selection
        self.command = command
        self.dispatchArguments = dispatchArguments
    }
}
