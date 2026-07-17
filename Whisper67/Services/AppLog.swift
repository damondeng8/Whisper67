import Foundation

/// Lightweight logging — hot-path noise only in DEBUG builds.
enum AppLog {
    static func debug(_ message: @autoclosure () -> String) {
        #if DEBUG
        print(message())
        #endif
    }
    
    static func info(_ message: @autoclosure () -> String) {
        print(message())
    }
}
