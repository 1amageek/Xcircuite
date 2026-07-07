import Darwin
import Foundation
import XcircuiteFlowCLISupport

@main
struct XcircuiteFlowCLIEntry {
    static func main() async {
        do {
            let output = try await XcircuiteFlowCLICommand.run(
                arguments: Array(CommandLine.arguments.dropFirst())
            )
            if !output.isEmpty {
                print(output)
            }
        } catch let error as XcircuiteFlowCLIError {
            writeError(error.message)
            exit(Int32(error.exitCode))
        } catch {
            writeError("Unexpected error: \(error.localizedDescription)")
            exit(1)
        }
    }

    private static func writeError(_ message: String) {
        if let data = "\(message)\n".data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
    }
}
