import Foundation

/// Tiny timestamped log written to Documents/debug.log. Used by the CI player test to measure
/// how long each step takes on a real simulator; harmless in normal use (it is truncated on launch).
enum DebugLog {
    private static let start = Date()
    private static let queue = DispatchQueue(label: "debuglog")
    private static let url: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let file = dir.appendingPathComponent("debug.log")
        try? Data().write(to: file)
        return file
    }()

    static func log(_ message: String) {
        let line = String(format: "[%7.2fs] ", Date().timeIntervalSince(start)) + message + "\n"
        #if DEBUG
        print(line, terminator: "")
        #endif
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            }
        }
    }
}
