import SwiftUI
import AVFoundation

// MARK: - Token Timing Types (shared between ContentView and SynthesisCoordinator)
struct TokenTime: Codable {
    let name: String
    let start: Double
    let end: Double
}
struct TokenTimesWrapper: Codable { let tokens: [TokenTime] }
struct TokenTimesResponse: Codable { let tokentimes: TokenTimesWrapper }

// MARK: - Logging (shared)
func logDebug(_ message: String) {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    print("[\(formatter.string(from: Date()))] [GriffinUI] \(message)")
    fflush(stdout)
}

// MARK: - Status colours (semantic, not raw Color values)
enum SynthesisStatusColor {
    case ready, synthesizing, speaking, error
    var color: Color {
        switch self {
        case .ready:        return .green
        case .synthesizing: return .orange
        case .speaking:     return .blue
        case .error:        return .red
        }
    }
}
