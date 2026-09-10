import AppKit
import Combine
import Foundation
import MihomoKit

@MainActor
final class LogsStore: ObservableObject {
    @Published var errorLogs: [AppErrorLogEntry] = []
    @Published var selectedSources: Set<AppLogSource> = [] {
        didSet { self.updateVisibleLogs() }
    }

    @Published var selectedLevels: Set<LogLevelFilter> = [] {
        didSet { self.updateVisibleLogs() }
    }

    @Published var searchText: String = "" {
        didSet { self.updateVisibleLogs() }
    }

    @Published private(set) var visibleLogs: [AppErrorLogEntry] = []

    var clashbarLogStore: AppLogStore?
    var mihomoLogStore: AppLogStore?

    let maxInMemoryLogEntries = 5000
    let hiddenPanelMaxInMemoryLogEntries = 20
    private let maxBufferedMihomoLogEntries = 40
    private let mihomoLogFlushIntervalNanoseconds: UInt64 = 150_000_000
    private var pendingMihomoLogs: [AppErrorLogEntry] = []
    private var mihomoLogFlushTask: Task<Void, Never>?

    init(clashbarLogStore: AppLogStore? = nil, mihomoLogStore: AppLogStore? = nil) {
        self.clashbarLogStore = clashbarLogStore
        self.mihomoLogStore = mihomoLogStore
    }

    func toggleSource(_ source: AppLogSource) {
        self.selectedSources.formSymmetricDifference([source])
    }

    func toggleLevel(_ level: LogLevelFilter) {
        self.selectedLevels.formSymmetricDifference([level])
    }

    func updateVisibleLogs() {
        let trimmedKeyword = self.searchText.trimmed
        let isShowingAllSources = self.selectedSources.isEmpty
        let isShowingAllLevels = self.selectedLevels.isEmpty

        let filtered: [AppErrorLogEntry] = if trimmedKeyword.isEmpty, isShowingAllSources, isShowingAllLevels {
            Array(self.errorLogs.prefix(120))
        } else {
            Array(self.errorLogs.filter { log in
                guard isShowingAllSources || self.selectedSources.contains(log.source) else { return false }
                guard isShowingAllLevels || self.selectedLevels.contains(LogLevelFilter.from(log.level))
                else { return false }
                guard trimmedKeyword.isEmpty || log.matches(keyword: trimmedKeyword) else { return false }
                return true
            }.prefix(120))
        }
        guard filtered != self.visibleLogs else { return }
        self.visibleLogs = filtered
    }

    func appendLog(level: String, message: String) {
        self.appendLog(source: .clashbar, level: level, message: message)
    }

    func appendMihomoLog(level: String, message: String) {
        self.appendLog(source: .mihomo, level: level, message: message)
    }

    func appendLog(source: AppLogSource, level: String, message: String) {
        guard !message.isEmpty else { return }

        let entry = AppErrorLogEntry(source: source, level: level, message: message)
        if source == .mihomo {
            self.enqueueBufferedMihomoLog(entry)
            return
        }

        self.appendLogEntries([entry], maxEntries: self.maxInMemoryLogEntries)
        self.persistLogEntriesToFile([entry])
    }

    func handleLogLine(_ line: LogLine) {
        let level = (line.type?.isEmpty == false) ? (line.type ?? "info") : "info"
        let message = line.payload?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !message.isEmpty {
            self.appendMihomoLog(level: level, message: message)
        }
    }

    func handleStreamEvent(_ event: MihomoStreamEvent) {
        switch event {
        case let .log(line):
            self.handleLogLine(line)
        default:
            break
        }
    }

    func flushPendingMihomoLogsIfNeeded() {
        self.mihomoLogFlushTask?.cancel()
        self.mihomoLogFlushTask = nil

        guard !self.pendingMihomoLogs.isEmpty else { return }
        let entries = self.pendingMihomoLogs
        self.pendingMihomoLogs.removeAll(keepingCapacity: true)
        self.pendingMihomoLogs.reserveCapacity(self.maxBufferedMihomoLogEntries)
        self.appendLogEntries(entries, maxEntries: self.maxInMemoryLogEntries)
        self.persistLogEntriesToFile(entries)
    }

    func trimInMemoryLogsForCurrentVisibility(isPanelPresented: Bool) {
        self.flushPendingMihomoLogsIfNeeded()
        let maxEntries = isPanelPresented ? self.maxInMemoryLogEntries : self.hiddenPanelMaxInMemoryLogEntries
        if self.errorLogs.count > maxEntries {
            self.errorLogs.removeLast(self.errorLogs.count - maxEntries)
            self.updateVisibleLogs()
        }
    }

    func clearAllLogs() {
        self.mihomoLogFlushTask?.cancel()
        self.mihomoLogFlushTask = nil
        self.pendingMihomoLogs.removeAll(keepingCapacity: true)
        self.errorLogs.removeAll(keepingCapacity: false)
        self.visibleLogs = []

        Task { [clashbarLogStore, mihomoLogStore] in
            await clashbarLogStore?.clear()
            await mihomoLogStore?.clear()
        }
    }

    func copyAllLogs() {
        self.flushPendingMihomoLogsIfNeeded()
        let content = self.errorLogs
            .map(self.formattedLogEntry)
            .joined(separator: "\n")

        self.copyTextToPasteboard(content)
        self.appendLog(level: "info", message: "Copied \(self.errorLogs.count) log entries")
    }

    func copyLogMessage(_ log: AppErrorLogEntry) {
        self.copyTextToPasteboard(log.message)
        self.appendLog(level: "info", message: "Copied log message")
    }

    func copyLogEntry(_ log: AppErrorLogEntry) {
        self.copyTextToPasteboard(self.formattedLogEntry(log))
        self.appendLog(level: "info", message: "Copied log entry")
    }

    func formattedLogEntry(_ log: AppErrorLogEntry) -> String {
        let source = log.source.rawValue.uppercased()
        return "[\(ValueFormatter.dateTime(log.timestamp))] [\(source)] [\(log.level.uppercased())] \(log.message)"
    }

    private func copyTextToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func enqueueBufferedMihomoLog(_ entry: AppErrorLogEntry) {
        self.pendingMihomoLogs.append(entry)

        if self.pendingMihomoLogs.count >= self.maxBufferedMihomoLogEntries {
            self.flushPendingMihomoLogsIfNeeded()
            return
        }

        guard self.mihomoLogFlushTask == nil else { return }
        self.mihomoLogFlushTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: self?.mihomoLogFlushIntervalNanoseconds ?? 150_000_000)
            } catch {
                return
            }

            self?.flushPendingMihomoLogsIfNeeded()
        }
    }

    private func appendLogEntries(_ entries: [AppErrorLogEntry], maxEntries: Int) {
        guard !entries.isEmpty else { return }
        self.errorLogs.insert(contentsOf: entries.reversed(), at: 0)
        if self.errorLogs.count > maxEntries {
            self.errorLogs.removeLast(self.errorLogs.count - maxEntries)
        }
        self.updateVisibleLogs()
    }

    private func persistLogEntriesToFile(_ entries: [AppErrorLogEntry]) {
        guard !entries.isEmpty else { return }

        var clashbarEntries: [AppErrorLogEntry] = []
        var mihomoEntries: [AppErrorLogEntry] = []
        clashbarEntries.reserveCapacity(entries.count)
        mihomoEntries.reserveCapacity(entries.count)

        for entry in entries {
            switch entry.source {
            case .clashbar:
                clashbarEntries.append(entry)
            case .mihomo:
                mihomoEntries.append(entry)
            }
        }

        Task { [clashbarLogStore, mihomoLogStore] in
            if !clashbarEntries.isEmpty {
                await clashbarLogStore?.append(entries: clashbarEntries)
            }
            if !mihomoEntries.isEmpty {
                await mihomoLogStore?.append(entries: mihomoEntries)
            }
        }
    }
}
