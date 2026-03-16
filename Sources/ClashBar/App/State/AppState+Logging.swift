import Foundation

@MainActor
extension AppState {
    func ensureLogFileExists() {
        self.flushPendingMihomoLogsIfNeeded()
        clashbarLogStore?.ensureLogFileExists()
        mihomoLogStore?.ensureLogFileExists()
    }

    func clearAllLogs() {
        mihomoLogFlushTask?.cancel()
        mihomoLogFlushTask = nil
        pendingMihomoLogs.removeAll(keepingCapacity: true)
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
        guard !safeMessage.isEmpty else { return }

        let entry = AppErrorLogEntry(source: source, level: level, message: safeMessage)
        if source == .mihomo {
            self.enqueueBufferedMihomoLog(entry)
            return
        }

        self.appendLogEntries([entry])
        self.persistLogEntriesToFile([entry])
    }

    func flushPendingMihomoLogsIfNeeded() {
        mihomoLogFlushTask?.cancel()
        mihomoLogFlushTask = nil

        guard !pendingMihomoLogs.isEmpty else { return }
        let entries = pendingMihomoLogs
        pendingMihomoLogs.removeAll(keepingCapacity: true)
        pendingMihomoLogs.reserveCapacity(maxBufferedMihomoLogEntries)
        self.appendLogEntries(entries)
        self.persistLogEntriesToFile(entries)
    }

    func trimInMemoryLogsForCurrentVisibility() {
        self.flushPendingMihomoLogsIfNeeded()
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

    private func enqueueBufferedMihomoLog(_ entry: AppErrorLogEntry) {
        pendingMihomoLogs.append(entry)

        if pendingMihomoLogs.count >= maxBufferedMihomoLogEntries {
            self.flushPendingMihomoLogsIfNeeded()
            return
        }

        guard mihomoLogFlushTask == nil else { return }
        mihomoLogFlushTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: self?.mihomoLogFlushIntervalNanoseconds ?? 150_000_000)
            } catch {
                return
            }

            self?.flushPendingMihomoLogsIfNeeded()
        }
    }

    private func appendLogEntries(_ entries: [AppErrorLogEntry]) {
        guard !entries.isEmpty else { return }

        // Single-allocation prepend: avoids O(n) in-place shift + separate removeLast
        let maxEntries = isPanelPresented ? maxLogEntries : hiddenPanelMaxInMemoryLogEntries
        let combined = entries.reversed() + errorLogs
        errorLogs = Array(combined.prefix(maxEntries))
    }

    private func persistLogEntriesToFile(_ entries: [AppErrorLogEntry]) {
        guard !entries.isEmpty else { return }

        let clashbarEntries = entries.filter { $0.source == .clashbar }
        if !clashbarEntries.isEmpty {
            clashbarLogStore?.append(entries: clashbarEntries)
        }

        let mihomoEntries = entries.filter { $0.source == .mihomo }
        if !mihomoEntries.isEmpty {
            mihomoLogStore?.append(entries: mihomoEntries)
        }
    }
}
