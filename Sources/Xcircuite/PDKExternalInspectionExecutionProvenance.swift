import CircuiteFoundation
import Foundation

enum PDKExternalInspectionExecutionProvenance {
    static func make(
        executablePath: String,
        arguments: [String],
        workingDirectory: URL,
        requestReference: ArtifactReference,
        startedAt: Date,
        completedAt: Date,
        executableDigest: ContentDigest,
        digester: any ContentDigesting = SHA256ContentDigester()
    ) throws -> ExecutionProvenance {
        let executableURL = URL(filePath: executablePath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let executableName = executableURL.lastPathComponent
        let version = "sha256-\(executableDigest.hexadecimalValue)"
        let producer = try ProducerIdentity(
            kind: .tool,
            identifier: executableName,
            version: version
        )
        let toolchain = "\(executableName)-\(version)"
        let platform = platformDescription()
        let architecture = try runningArchitecture()
        let environmentManifest = EnvironmentManifest(
            platform: platform,
            architecture: architecture,
            toolchain: toolchain
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let environmentDigest = try digester.digest(
            data: encoder.encode(environmentManifest),
            using: .sha256
        )

        return try ExecutionProvenance(
            producer: producer,
            inputs: [requestReference],
            invocation: ExecutionInvocation.externalProcess(
                executable: executableURL.path(percentEncoded: false),
                arguments: arguments,
                workingDirectory: workingDirectory.path(percentEncoded: false)
            ),
            environment: ExecutionEnvironmentFingerprint(
                platform: platform,
                architecture: architecture,
                toolchain: toolchain,
                environmentDigest: environmentDigest
            ),
            startedAt: startedAt,
            completedAt: completedAt
        )
    }

    private static func platformDescription() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS-\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    private static func runningArchitecture() throws -> String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        throw PDKExternalInspectionProcessError.processFailed(
            "The running architecture cannot be identified."
        )
        #endif
    }

    private struct EnvironmentManifest: Encodable {
        let platform: String
        let architecture: String
        let toolchain: String
    }
}
