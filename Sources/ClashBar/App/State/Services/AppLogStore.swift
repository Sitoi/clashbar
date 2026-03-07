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

    func append(entries: [AppErrorLogEntry]) {
        self.append(records: entries.map {
            (timestamp: $0.timestamp, level: $0.level, message: $0.message)
        })
    }

    private func append(records: [(timestamp: Date, level: String, message: String)]) {
        guard !records.isEmpty else { return }
        self.ensureLogFileExists()
        let content = records.map {
            "[\(Self.timestampString(from: $0.timestamp))] [\($0.level.uppercased())] \($0.message)\n"
        }.joined()

        guard let data = content.data(using: .utf8),
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
