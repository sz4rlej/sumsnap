import Foundation

/// Prosty log do pliku — aplikacja bez okna nie ma gdzie pokazać błędu,
/// a `~/Library/Logs/SumSnap.log` czyta się w Konsoli albo `tail -f`.
enum Log {
    private static let url: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs", isDirectory: true)
        return dir.appendingPathComponent("SumSnap.log")
    }()

    private static let queue = DispatchQueue(label: "pl.softmasters.sumsnap.log")

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func write(_ message: String) {
        let line = "[\(stamp.string(from: Date()))] \(message)\n"
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url)
            }
        }
    }

    static func path() -> String { url.path }
}
