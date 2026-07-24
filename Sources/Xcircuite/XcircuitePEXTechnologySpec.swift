import Foundation
import DesignFlowKernel
import PEXEngine

public enum XcircuitePEXTechnologySpec: Sendable, Hashable, Codable {
    case jsonFile(path: String)
    case input(XcircuiteFlowInputReference)
    case inline(TechnologyIR)

    private enum CodingKeys: String, CodingKey {
        case type
        case path
        case value
    }

    private enum Kind: String, Codable {
        case jsonFile
        case input
        case inline
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .type)
        switch kind {
        case .jsonFile:
            self = .jsonFile(path: try container.decode(String.self, forKey: .path))
        case .input:
            self = .input(try container.decode(XcircuiteFlowInputReference.self, forKey: .value))
        case .inline:
            self = .inline(try container.decode(TechnologyIR.self, forKey: .value))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .jsonFile(let path):
            try container.encode(Kind.jsonFile, forKey: .type)
            try container.encode(path, forKey: .path)
        case .input(let input):
            try container.encode(Kind.input, forKey: .type)
            try container.encode(input, forKey: .value)
        case .inline(let value):
            try container.encode(Kind.inline, forKey: .type)
            try container.encode(value, forKey: .value)
        }
    }

    func makeTechnologyInput(projectRoot: URL) throws -> TechnologyInput {
        switch self {
        case .jsonFile(let path):
            .jsonFile(try XcircuiteFlowRuntimeSpec.resolvePath(path, projectRoot: projectRoot))
        case .input:
            throw XcircuiteFlowRuntimeSpecError.invalidPath("PEX technology input requires run context")
        case .inline(let technology):
            .inline(technology)
        }
    }

    func makeTechnologyInput(
        projectRoot: URL,
        runDirectory: URL,
        infrastructure: any FlowRunInfrastructure
    ) async throws -> TechnologyInput {
        switch self {
        case .jsonFile(let path):
            .jsonFile(try XcircuiteFlowRuntimeSpec.resolvePath(path, projectRoot: projectRoot))
        case .input(let input):
            .jsonFile(try await input.resolveExisting(
                projectRoot: projectRoot,
                runDirectory: runDirectory,
                infrastructure: infrastructure
            ))
        case .inline(let technology):
            .inline(technology)
        }
    }
}
