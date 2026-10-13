import Foundation

enum AppConfig {
    /// Change this to your Mac's LAN IP when testing on your physical iPhone (e.g., "192.168.1.50:3000")
    #if targetEnvironment(simulator)
    static let host = "127.0.0.1:3000"
    #else
    static let host = "192.168.1.141:3000" // Update with your Mac's Wi-Fi IP
    #endif

    static var httpBaseURL: URL {
        URL(string: "http://\(host)")!
    }

    static var wsBaseURL: URL {
        URL(string: "ws://\(host)/ws")!
    }

    static func audioURL(for path: String) -> URL {
        httpBaseURL.appendingPathComponent("audio").appendingPathComponent(path)
    }
}