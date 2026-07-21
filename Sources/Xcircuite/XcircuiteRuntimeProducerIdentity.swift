import CircuiteFoundation
import Foundation

public enum XcircuiteRuntimeProducerIdentity {
    public static func current(
        bundle: Bundle = .main,
        arguments: [String] = CommandLine.arguments,
        digester: any ContentDigesting = SHA256ContentDigester()
    ) throws -> ProducerIdentity {
        let executableURL: URL
        if let bundledExecutable = bundle.executableURL {
            executableURL = bundledExecutable
        } else if let executableArgument = arguments.first, !executableArgument.isEmpty {
            executableURL = URL(fileURLWithPath: executableArgument).standardizedFileURL
        } else {
            throw XcircuiteRuntimeIdentityError.executableUnavailable
        }

        let digest = try digester.digest(fileAt: executableURL, using: .sha256)
        return try ProducerIdentity(
            kind: .library,
            identifier: "Xcircuite",
            version: "1.0.0",
            build: digest.hexadecimalValue
        )
    }
}
