import Foundation

@MainActor
extension AppState {
    func ensureLogFileExists() {
        clashbarLogStore?.ensureLogFileExists()
        mihomoLogStore?.ensureLogFileExists()
    }

    func clearAllLogs() {
        errorLogs.removeAll(keepingCapacity: false)
        clashbarLogStore?.clear()
        mihomoLogStore?.clear()
    }

    func appendLog(level: String, message: String) {
        self.appendLog(source: .clashbar, level: level, message: message)
    }

    func appendMihomoLog(level: String, message: String) {
        self.appendLog(source: .mihomo, level: level, message: message)
    }

    func appendLog(source: AppLogSource, level: String, message: String) {
        let safeMessage = LogSanitizer.redact(message)
        errorLogs.insert(AppErrorLogEntry(source: source, level: level, message: safeMessage), at: 0)
        self.persistLogToFile(source: source, level: level, message: safeMessage)
        let maxEntries = isPanelPresented ? maxLogEntries : hiddenPanelMaxInMemoryLogEntries
        if errorLogs.count > maxEntries {
            errorLogs.removeLast(errorLogs.count - maxEntries)
        }
    }

    func persistLogToFile(source: AppLogSource, level: String, message: String) {
        switch source {
        case .clashbar:
            clashbarLogStore?.append(level: level, message: message)
        case .mihomo:
            mihomoLogStore?.append(level: level, message: message)
        }
    }

    func trimInMemoryLogsForCurrentVisibility() {
        let maxEntries = isPanelPresented ? maxLogEntries : hiddenPanelMaxInMemoryLogEntries
        guard errorLogs.count > maxEntries else { return }
        errorLogs.removeLast(errorLogs.count - maxEntries)
    }

    func tr(_ key: String) -> String {
        L10n.t(key, language: uiLanguage)
    }

    func tr(_ key: String, _ args: CVarArg...) -> String {
        L10n.t(key, language: uiLanguage, args: args)
    }
}
