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
            HStack(spacing: MenuBarLayoutTokens.hDense) {
                self.logsSourceFilterButtons

                Spacer(minLength: 0)

                self.logsCountSummaryBadge
            }
            self.logsSecondaryControlRow
            TextField(tr("ui.placeholder.search_logs"), text: $logSearchText)
                .textFieldStyle(.roundedBorder)
                .font(.appSystem(size: 12, weight: .regular))
                .foregroundStyle(nativePrimaryLabel)
        }
        .menuRowPadding(vertical: MenuBarLayoutTokens.vDense + 2)
        .background(nativeSectionCard())
    }

    var logsSecondaryControlRow: some View {
        HStack(spacing: MenuBarLayoutTokens.hDense) {
            self.logsLevelFilterButtons

            self.logsControlIconButton(
                "line.3.horizontal.decrease.circle",
                helpText: tr("ui.action.reset_log_filters"),
                isDisabled: !self.hasActiveLogFilters)
            {
                self.resetLogFilters()
            }

            Spacer(minLength: 0)

            self.logsControlIconButton(
                "doc.on.doc",
                helpText: tr("ui.action.copy_all_logs"),
                isDisabled: appState.errorLogs.isEmpty)
            {
                appState.copyAllLogs()
            }

            self.logsControlIconButton(
                "trash",
                helpText: tr("ui.action.clear_all_logs"),
                role: .destructive,
                isDisabled: appState.errorLogs.isEmpty)
            {
                appState.clearAllLogs()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func logsControlIconButton(
        _ symbol: String,
        helpText: String,
        role: ButtonRole? = nil,
        isDisabled: Bool = false,
        action: @escaping () -> Void) -> some View
    {
        Button(role: role, action: action) {
            Image(systemName: symbol)
                .font(.appSystem(size: 11, weight: .semibold))
                .frame(width: 12, height: 12)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(helpText)
        .accessibilityLabel(helpText)
        .disabled(isDisabled)
    }

    var logsSourceFilterButtons: some View {
        HStack(spacing: MenuBarLayoutTokens.hMicro + 1) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.appSystem(size: 10, weight: .semibold))
                .foregroundStyle(nativeTertiaryLabel)

            self.logFilterToggleButton(
                title: tr("ui.log_source.all"),
                selected: selectedLogSources == self.allLogSourceSelection,
                action: { selectedLogSources = self.allLogSourceSelection })
                .help(tr("ui.log_source.all"))

            ForEach(AppLogSource.allCases) { source in
                self.logFilterToggleButton(
                    title: self.logSourcePresentation(source).label,
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
                .font(.appSystem(size: 10, weight: .semibold))
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
                    .font(.appSystem(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        } else {
            Button(action: action) {
                Text(title)
                    .font(.appSystem(size: 11, weight: .medium))
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
                .font(.appMonospaced(size: 11, weight: .bold))
            Text("/")
                .font(.appMonospaced(size: 10, weight: .medium))
            Text("\(appState.errorLogs.count)")
                .font(.appMonospaced(size: 11, weight: .medium))
        }
        .foregroundStyle(nativeSecondaryLabel)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(nativeBadgeCapsule())
    }

    func toggleLogSource(_ source: AppLogSource) {
        self.toggleSelection(source, selection: &selectedLogSources, all: self.allLogSourceSelection)
    }

    func toggleLogLevel(_ level: LogLevelFilter) {
        self.toggleSelection(level, selection: &selectedLogLevels, all: self.allLogLevelSelection)
    }

    var hasActiveLogFilters: Bool {
        selectedLogSources != self.allLogSourceSelection || selectedLogLevels != self.allLogLevelSelection || !self
            .trimmedLogKeyword.isEmpty
    }

    var trimmedLogKeyword: String {
        logSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func resetLogFilters() {
        selectedLogSources = self.allLogSourceSelection
        selectedLogLevels = self.allLogLevelSelection
        logSearchText = ""
    }

    var filteredLogs: [AppErrorLogEntry] {
        let logs = Array(appState.errorLogs.prefix(120))
        return logs.filter { log in
            guard selectedLogSources.contains(log.source) else { return false }
            guard self.trimmedLogKeyword.isEmpty || self.logSearchTextContent(for: log)
                .localizedStandardContains(self.trimmedLogKeyword) else { return false }
            return selectedLogLevels.contains(self.logLevelPresentation(self.normalizedLogLevel(log.level)).filter)
        }
    }

    func toggleSelection<Value: Hashable>(
        _ value: Value,
        selection: inout Set<Value>,
        all: Set<Value>)
    {
        if selection.contains(value) {
            selection.remove(value)
            if selection.isEmpty {
                selection = all
            }
        } else {
            selection.insert(value)
        }
    }

    func logEntryRow(_ log: AppErrorLogEntry) -> some View {
        let level = self.normalizedLogLevel(log.level)
        let sourceInfo = self.logSourcePresentation(log.source)
        let levelInfo = self.logLevelPresentation(level)
        let parsed = self.parseLogMessage(log.message)
        let tone = levelInfo.color
        let symbol = levelInfo.symbol

        return HStack(alignment: .top, spacing: MenuBarLayoutTokens.hDense + 1) {
            RoundedRectangle(cornerRadius: MenuBarLayoutTokens.iconCornerRadius, style: .continuous)
                .fill(tone.opacity(0.14))
                .frame(width: 16, height: 16)
                .overlay {
                    Image(systemName: symbol)
                        .font(.appSystem(size: 9, weight: .semibold))
                        .foregroundStyle(tone)
                }

            VStack(alignment: .leading, spacing: MenuBarLayoutTokens.vDense) {
                HStack(spacing: MenuBarLayoutTokens.hMicro + 1) {
                    Text("[\(sourceInfo.label)]")
                        .font(.appMonospaced(size: 10, weight: .semibold))
                        .foregroundStyle(sourceInfo.color)

                    Text("[\(levelInfo.label)]")
                        .font(.appMonospaced(size: 10, weight: .semibold))
                        .foregroundStyle(tone)

                    if let protocolTag = parsed.protocolTag {
                        Text(protocolTag)
                            .font(.appMonospaced(size: 10, weight: .semibold))
                            .foregroundStyle(parsed.protocolColor)
                    }

                    Text(ValueFormatter.dateTime(log.timestamp))
                        .font(.appMonospaced(size: 10, weight: .regular))
                        .foregroundStyle(nativeTertiaryLabel)
                        .lineLimit(1)
                }

                Text(parsed.mainText)
                    .font(.appMonospaced(size: 11, weight: .regular))
                    .foregroundStyle(nativePrimaryLabel)
                    .fixedSize(horizontal: false, vertical: true)

                if let detailText = parsed.detailText {
                    Text(detailText)
                        .font(.appMonospaced(size: 10, weight: .regular))
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

    func logSourcePresentation(_ source: AppLogSource) -> (label: String, color: Color) {
        switch source {
        case .clashbar:
            (tr("ui.log_source.clashbar"), nativeSecondaryLabel)
        case .mihomo:
            (tr("ui.log_source.mihomo"), nativeAccent.opacity(0.95))
        }
    }

    func logLevelPresentation(_ normalizedLevel: String)
        -> (filter: LogLevelFilter, label: String, color: Color, symbol: String)
    {
        switch normalizedLevel {
        case "ERROR":
            (
                .error,
                tr("ui.log_filter.error"),
                nativeCritical.opacity(0.92),
                "exclamationmark.octagon.fill")
        case "WARNING":
            (
                .warning,
                tr("ui.log_filter.warning"),
                nativeWarning.opacity(0.92),
                "exclamationmark.triangle.fill")
        default:
            (
                .info,
                tr("ui.log_filter.info"),
                nativeAccent.opacity(0.9),
                "info.circle.fill")
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
        let source = self.logSourcePresentation(log.source).label
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
