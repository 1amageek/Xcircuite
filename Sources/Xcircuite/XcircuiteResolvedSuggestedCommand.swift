import Foundation
import XcircuitePackage

public struct XcircuiteResolvedSuggestedCommand: Sendable, Hashable, Codable {
    public var selection: XcircuiteSuggestedCommandSelection
    public var commandName: String
    public var dispatchArguments: [String]

    public init(
        selection: XcircuiteSuggestedCommandSelection,
        commandName: String,
        dispatchArguments: [String]
    ) {
        self.selection = selection
        self.commandName = commandName
        self.dispatchArguments = dispatchArguments
    }
}
