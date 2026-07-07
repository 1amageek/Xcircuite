import Foundation

public enum PostLayoutComparisonServiceError: Error, LocalizedError, Equatable {
    case invalidCSV(String)

    public var errorDescription: String? {
        switch self {
        case .invalidCSV(let message):
            return message
        }
    }
}
