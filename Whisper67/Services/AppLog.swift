import Foundation

/// Lightweight logging. `debug` is always printed for paste/dictation diagnostics
/// (menu-bar apps have no console UI — Console.app filters by process name Whisper67).
enum AppLog {
    static func debug(_ message: @autoclosure () -> String) {
        print(message())
    }
    
    static func info(_ message: @autoclosure () -> String) {
        print(message())
    }
}
