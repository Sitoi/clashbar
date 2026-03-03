import Foundation
import SwiftUI

extension MenuBarRoot {
    var logsTabBody: some View {
        let logs = self.filteredLogs

        return VStack(alignment: .leading, spacing: MenuBarLayoutTokens.sectionGap) {
            self.logsControlCard

            if logs.isEmpty {
                emptyCard(tr("ui.empty.logs"))
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(logs.enumerated()), id: \.element.id) { index, log in
                        self.logEntryRow(log)
                            .padding(.horizontal, MenuBarLayoutTokens.hRow)
                            .padding(.vertical, MenuBarLayoutTokens.vDense + 2)

                        if index < logs.count - 1 {
                            Rectangle()
                                .fill(nativeSeparator)
                                .frame(height: MenuBarLayoutTokens.hairline)
                        }
                    }
                }
                .background(nativeSectionCard())
            }
        }
    }

    var logsControlCard: some View {
        VStack(alignment: .leading, spacing: MenuBarLayoutTokens.vDense + 2) {
            self.logsPrimaryControlRow
            self.logsSecondaryControlRow
            self.logsSearchControlRow
        }
        .menuRowPadding(vertical: MenuBarLayoutTokens.vDense + 2)
        .background(nativeSectionCard())
    }

    var logsPrimaryControlRow: some View {
        HStack(spacing: MenuBarLayoutTokens.hDense) {
            self.logsSourceFilterButtons

            Spacer(minLength: 0)

            self.logsCountSummaryBadge
        }
    }

    var logsSecondaryControlRow: some View {
        HStack(spacing: MenuBarLayoutTokens.hDense) {
            self.logsLevelFilterButtons

            Button {
                self.resetLogFilters()
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 12, height: 12)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(tr("ui.action.reset_log_filters"))
            .accessibilityLabel(tr("ui.action.reset_log_filters"))
            .disabled(!self.hasActiveLogFilters)

            Spacer(minLength: 0)

            Button {
                appState.copyAllLogs()
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 12, height: 12)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(tr("ui.action.copy_all_logs"))
            .accessibilityLabel(tr("ui.action.copy_all_logs"))
            .disabled(appState.errorLogs.isEmpty)

            Button(role: .destructive) {
                appState.clearAllLogs()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 12, height: 12)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(tr("ui.action.clear_all_logs"))
            .accessibilityLabel(tr("ui.action.clear_all_logs"))
            .disabled(appState.errorLogs.isEmpty)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var logsSearchControlRow: some View {
        TextField(tr("ui.placeholder.search_logs"), text: $logSearchText)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(nativePrimaryLabel)
    }

    var logsSourceFilterButtons: some View {
        HStack(spacing: MenuBarLayoutTokens.hMicro + 1) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(nativeTertiaryLabel)

            self.logFilterToggleButton(
                title: tr("ui.log_source.all"),
                selected: selectedLogSources == self.allLogSourceSelection,
                action: { selectedLogSources = self.allLogSourceSelection })
                .help(tr("ui.log_source.all"))

            ForEach(AppLogSource.allCases) { source in
                self.logFilterToggleButton(
                    title: self.localizedLogSourceLabel(source),
                    selected: selectedLogSources.contains(source),
                    action: { self.toggleLogSource(source) })
                    .help(tr("ui.log_source.all"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var logsLevelFilterButtons: some View {
        HStack(spacing: MenuBarLayoutTokens.hMicro + 1) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(nativeTertiaryLabel)

            self.logFilterToggleButton(
                title: tr("ui.log_filter.all"),
                selected: selectedLogLevels == self.allLogLevelSelection,
                action: { selectedLogLevels = self.allLogLevelSelection })
                .help(tr("ui.log_filter.all"))

            ForEach(self.logSelectableLevels, id: \.self) { level in
                self.logFilterToggleButton(
                    title: tr(level.titleKey),
                    selected: selectedLogLevels.contains(level),
                    action: { self.toggleLogLevel(level) })
                    .help(tr("ui.settings.log_level"))
            }
        }
    }

    @ViewBuilder
    func logFilterToggleButton(
        title: String,
        selected: Bool,
        action: @escaping () -> Void) -> some View
    {
        if selected {
            Button(action: action) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        } else {
            Button(action: action) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    var logSelectableLevels: [LogLevelFilter] {
        [.info, .warning, .error]
    }

    var allLogSourceSelection: Set<AppLogSource> {
        Set(AppLogSource.allCases)
    }

    var allLogLevelSelection: Set<LogLevelFilter> {
        Set(self.logSelectableLevels)
    }

    var logsCountSummaryBadge: some View {
        HStack(spacing: MenuBarLayoutTokens.hMicro) {
            Text("\(self.filteredLogs.count)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
            Text("/")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
            Text("\(appState.errorLogs.count)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
        }
        .foregroundStyle(nativeSecondaryLabel)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(nativeBadgeCapsule())
    }

    func toggleLogSource(_ source: AppLogSource) {
        if selectedLogSources.contains(source) {
            selectedLogSources.remove(source)
            if selectedLogSources.isEmpty {
                selectedLogSources = self.allLogSourceSelection
            }
        } else {
            selectedLogSources.insert(source)
        }
    }

    func toggleLogLevel(_ level: LogLevelFilter) {
        if selectedLogLevels.contains(level) {
            selectedLogLevels.remove(level)
            if selectedLogLevels.isEmpty {
                selectedLogLevels = self.allLogLevelSelection
            }
        } else {
            selectedLogLevels.insert(level)
        }
    }

    var hasActiveLogFilters: Bool {
        selectedLogSources != self.allLogSourceSelection || selectedLogLevels != self.allLogLevelSelection || !self
            .trimmedLogKeyword.isEmpty
    }

    var trimmedLogKeyword: String {
        logSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var logsMatchingSourceAndSearch: [AppErrorLogEntry] {
        let logs = Array(appState.errorLogs.prefix(120))
        return logs.filter { log in
            guard selectedLogSources.contains(log.source) else { return false }
            guard !self.trimmedLogKeyword.isEmpty else { return true }
            return self.logSearchTextContent(for: log).localizedStandardContains(self.trimmedLogKeyword)
        }
    }

    func resetLogFilters() {
        selectedLogSources = self.allLogSourceSelection
        selectedLogLevels = self.allLogLevelSelection
        logSearchText = ""
    }

    var filteredLogs: [AppErrorLogEntry] {
        self.logsMatchingSourceAndSearch.filter { log in
            selectedLogLevels.contains(self.levelFilterOption(from: self.normalizedLogLevel(log.level)))
        }
    }

    func levelFilterOption(from normalizedLevel: String) -> LogLevelFilter {
        switch normalizedLevel {
        case "ERROR":
            .error
        case "WARNING":
            .warning
        default:
            .info
        }
    }

    func logEntryRow(_ log: AppErrorLogEntry) -> some View {
        let level = self.normalizedLogLevel(log.level)
        let sourceLabel = self.localizedLogSourceLabel(log.source)
        let sourceTone = self.logSourceStyle(log.source)
        let displayLevel = self.localizedLogLevelLabel(level)
        let parsed = self.parseLogMessage(log.message)
        let tone = self.logLevelStyle(level)
        let symbol = self.logLevelSymbol(level)

        return HStack(alignment: .top, spacing: MenuBarLayoutTokens.hDense + 1) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(tone.opacity(0.14))
                .frame(width: 16, height: 16)
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(tone)
                }

            VStack(alignment: .leading, spacing: MenuBarLayoutTokens.vDense) {
                HStack(spacing: MenuBarLayoutTokens.hMicro + 1) {
                    Text("[\(sourceLabel)]")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(sourceTone)

                    Text("[\(displayLevel)]")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(tone)

                    if let protocolTag = parsed.protocolTag {
                        Text(protocolTag)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(parsed.protocolColor)
                    }

                    Text(ValueFormatter.dateTime(log.timestamp))
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(nativeTertiaryLabel)
                        .lineLimit(1)
                }

                Text(parsed.mainText)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(nativePrimaryLabel)
                    .fixedSize(horizontal: false, vertical: true)

                if let detailText = parsed.detailText {
                    Text(detailText)
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(nativeSecondaryLabel)
                        .lineLimit(2)
                        .padding(.leading, MenuBarLayoutTokens.hDense)
                        .overlay(alignment: .leading) {
                            Rectangle()
                                .fill(tone.opacity(0.30))
                                .frame(width: MenuBarLayoutTokens.opticalNudge)
                        }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contextMenu {
            Button {
                appState.copyLogMessage(log)
            } label: {
                Label(tr("ui.action.copy_log_message"), systemImage: "doc.on.doc")
            }

            Button {
                appState.copyLogEntry(log)
            } label: {
                Label(tr("ui.action.copy_log_entry"), systemImage: "doc.plaintext")
            }
        }
    }

    func normalizedLogLevel(_ raw: String) -> String {
        let lower = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower.contains("error") || lower.contains("err") {
            return "ERROR"
        }
        if lower.contains("warn") {
            return "WARNING"
        }
        return "INFO"
    }

    func localizedLogLevelLabel(_ level: String) -> String {
        switch level {
        case "ERROR":
            tr("ui.log_filter.error")
        case "WARNING":
            tr("ui.log_filter.warning")
        default:
            tr("ui.log_filter.info")
        }
    }

    func localizedLogSourceLabel(_ source: AppLogSource) -> String {
        switch source {
        case .clashbar:
            tr("ui.log_source.clashbar")
        case .mihomo:
            tr("ui.log_source.mihomo")
        }
    }

    func logSourceStyle(_ source: AppLogSource) -> Color {
        switch source {
        case .clashbar:
            nativeSecondaryLabel
        case .mihomo:
            nativeAccent.opacity(0.95)
        }
    }

    func logLevelStyle(_ level: String) -> Color {
        switch level {
        case "ERROR":
            nativeCritical.opacity(0.92)
        case "WARNING":
            nativeWarning.opacity(0.92)
        default:
            nativeAccent.opacity(0.9)
        }
    }

    func logLevelSymbol(_ level: String) -> String {
        switch level {
        case "ERROR":
            "exclamationmark.octagon.fill"
        case "WARNING":
            "exclamationmark.triangle.fill"
        default:
            "info.circle.fill"
        }
    }

    func parseLogMessage(_ raw: String)
    -> (protocolTag: String?, protocolColor: Color, mainText: String, detailText: String?) {
        var message = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if message.isEmpty {
            return (nil, nativeSecondaryLabel, tr("ui.common.na"), nil)
        }

        if let extracted = firstRegexCapture(in: message, regex: CachedLogRegex.msgField), !extracted.isEmpty {
            message = extracted
        }

        var detailText: String?
        if let trailingBracket = firstRegexCapture(in: message, regex: CachedLogRegex.trailingBracket) {
            detailText = trailingBracket
            message = message.replacingOccurrences(of: trailingBracket, with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var protocolTag: String?
        var protocolColor = nativeAccent.opacity(0.90)
        if let tag = firstRegexCapture(in: message, regex: CachedLogRegex.protocolTag) {
            protocolTag = tag
            message = message.replacingOccurrences(of: tag, with: "").trimmingCharacters(in: .whitespacesAndNewlines)

            let upper = tag.uppercased()
            if upper.contains("UDP") { protocolColor = nativeWarning.opacity(0.90) }
            if upper.contains("DNS") { protocolColor = nativePositive.opacity(0.90) }
            if upper.contains("HTTP") { protocolColor = nativeAccent.opacity(0.90) }
        }

        if message.isEmpty {
            message = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return (protocolTag, protocolColor, message, detailText)
    }

    func firstRegexCapture(in text: String, regex: NSRegularExpression?) -> String? {
        guard let regex else { return nil }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        guard let match = regex.firstMatch(in: text, options: [], range: range), match.numberOfRanges > 1 else {
            return nil
        }
        let captureRange = match.range(at: 1)
        guard captureRange.location != NSNotFound else { return nil }
        return nsText.substring(with: captureRange)
    }

    func logSearchTextContent(for log: AppErrorLogEntry) -> String {
        let source = self.localizedLogSourceLabel(log.source)
        let level = self.normalizedLogLevel(log.level)
        let time = ValueFormatter.dateTime(log.timestamp)
        let message = log.message
        return "\(source) \(level) \(time) \(message)"
    }
}

private enum CachedLogRegex {
    static let msgField = try? NSRegularExpression(pattern: #"msg="([^"]+)""#, options: [])
    static let trailingBracket = try? NSRegularExpression(pattern: #"(?:\s|^)(\[[^\[\]]+\])\s*$"#, options: [])
    static let protocolTag = try? NSRegularExpression(pattern: #"(\[(?:TCP|UDP|DNS|HTTP|HTTPS)\])"#, options: [])
}
