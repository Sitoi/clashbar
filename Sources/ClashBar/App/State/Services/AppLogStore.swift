import Foundation

struct AppLogStore {
    let logFileURL: URL
    private static let formatterLock = NSLock()
    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    func ensureLogFileExists() {
        if !FileManager.default.fileExists(atPath: self.logFileURL.path) {
            FileManager.default.createFile(atPath: self.logFileURL.path, contents: nil)
        }
    }

    func append(level: String, message: String) {
        self.ensureLogFileExists()
        let line = "[\(Self.timestampString(from: Date()))] [\(level.uppercased())] \(message)\n"
        guard let data = line.data(using: .utf8),
              let handle = FileHandle(forWritingAtPath: logFileURL.path)
        else {
            return
        }
        defer { handle.closeFile() }
        handle.seekToEndOfFile()
        handle.write(data)
    }

    func clear() {
        if FileManager.default.fileExists(atPath: self.logFileURL.path) {
            try? Data().write(to: self.logFileURL, options: .atomic)
        } else {
            self.ensureLogFileExists()
        }
    }

    private static func timestampString(from date: Date) -> String {
        self.formatterLock.lock()
        defer { formatterLock.unlock() }
        return self.timestampFormatter.string(from: date)
    }
}
