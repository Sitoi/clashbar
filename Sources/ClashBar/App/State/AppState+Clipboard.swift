import AppKit

@MainActor
extension AppState {
    func resolvedConnectionHost(for connection: ConnectionSummary) -> String? {
        let host = connection.metadata?.host?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !host.isEmpty {
            return host
        }

        let destinationIP = connection.metadata?.destinationIP?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !destinationIP.isEmpty {
            return destinationIP
        }
        return nil
    }

    func copyConnectionHost(_ host: String) {
        self.copyAndLog(host, message: tr("log.connection.copy_host", host))
    }

    func copyConnectionID(_ id: String) {
        self.copyAndLog(id, message: tr("log.connection.copy_id", id))
    }

    func copyLogMessage(_ log: AppErrorLogEntry) {
        self.copyAndLog(log.message, message: tr("log.logs.copied_message"))
    }

    func copyLogEntry(_ log: AppErrorLogEntry) {
        self.copyAndLog(self.formattedLogEntry(log), message: tr("log.logs.copied_entry"))
    }

    func copyTextToPasteboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    func formattedLogEntry(_ log: AppErrorLogEntry) -> String {
        let source = log.source.rawValue.uppercased()
        return "[\(ValueFormatter.dateTime(log.timestamp))] [\(source)] [\(log.level.uppercased())] \(log.message)"
    }

    private func copyAndLog(_ text: String, message: String) {
        // DRY: all copy actions share the same pasteboard + info-log behavior.
        self.copyTextToPasteboard(text)
        appendLog(level: "info", message: message)
    }
}
