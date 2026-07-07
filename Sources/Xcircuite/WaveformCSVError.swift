import Foundation

enum WaveformCSVError: Error, LocalizedError, Equatable {
    case invalidCSV(String)

    var errorDescription: String? {
        switch self {
        case .invalidCSV(let message):
            message
        }
    }
}
