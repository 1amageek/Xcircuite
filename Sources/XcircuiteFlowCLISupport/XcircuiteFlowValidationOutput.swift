import Foundation

struct XcircuiteFlowValidationOutput: Sendable, Hashable, Codable {
    let status: String
    let validated: [String]
    let runSpecPath: String?
    let runtimeConfigPath: String?
    let runStageCount: Int?
    let runtimeExecutorCount: Int?
}
