import Foundation

public struct XcircuiteXcodebuildTestInvocation: Codable, Sendable, Hashable {
    public var timeoutSeconds: Int
    public var xcodebuildPath: String
    public var scheme: String
    public var destination: String
    public var onlyTesting: String

    public init(
        timeoutSeconds: Int = 120,
        xcodebuildPath: String = "/usr/bin/xcodebuild",
        scheme: String,
        destination: String = "platform=macOS",
        onlyTesting: String
    ) {
        self.timeoutSeconds = timeoutSeconds
        self.xcodebuildPath = xcodebuildPath
        self.scheme = scheme
        self.destination = destination
        self.onlyTesting = onlyTesting
    }

    public var command: [String] {
        [
            "perl", "-e", "alarm shift; exec @ARGV", "\(timeoutSeconds)",
            xcodebuildPath, "test",
            "-scheme", scheme,
            "-destination", destination,
            "-only-testing:\(onlyTesting)",
        ]
    }

    func validate() throws {
        guard timeoutSeconds > 0, timeoutSeconds <= 120,
              !scheme.isEmpty,
              xcodebuildPath.hasPrefix("/"),
              !destination.isEmpty,
              !onlyTesting.isEmpty,
              [xcodebuildPath, scheme, destination, onlyTesting].allSatisfy({ value in
                  !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
              }) else {
            throw XcircuitePlatformCapabilityTestRunnerError.invalidCommand
        }
    }
}
