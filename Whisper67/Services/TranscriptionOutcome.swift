import Foundation

/// Typed result from STT (+ polish). Avoids encoding errors as fake transcript strings.
enum TranscriptionOutcome: Sendable, Equatable {
    case success(text: String, durationSeconds: Double)
    case failure(message: String, durationSeconds: Double)
    
    var durationSeconds: Double {
        switch self {
        case .success(_, let d), .failure(_, let d): return d
        }
    }
}
