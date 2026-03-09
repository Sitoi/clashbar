import SwiftUI

private typealias T = MenuBarLayoutTokens

extension MenuBarRoot {
    var logsTabBody: some View {
        let logs = self.visibleLogs

        return VStack(alignment: .leading, spacing: T.space6) {
            self.logsControlCard(filteredCount: logs.count)

            if logs.isEmpty {
                emptyCard(tr("ui.empty.logs"))
            } else {
                MeasurementAwareVStack(alignment: .leading, spacing: 0) {
                    SeparatedForEach(data: logs, id: \.id, separator: nativeSeparator) { log in
                        self.logEntryRow(log)
                            .padding(.horizontal, T.space4)
                            .padding(.vertical, T.space4)
                    }
                }
            }
        }
    }

    func logsControlCard(filteredCount: Int) -> some View {
        VStack(alignment: .leading, spacing: T.space4) {
            HStack(spacing: T.space6) {
                self.logsSourceFilterButtons

                Spacer(minLength: 0)

                self.logsCountSummaryBadge(filteredCount: filteredCount)
            }
            self.logsSecondaryControlRow
            TextField(tr("ui.placeholder.search_logs"), text: $logSearchText)
                .textFieldStyle(.roundedBorder)
                .font(.app(size: T.FontSize.body, weight: .regular))
                .foregroundStyle(nativePrimaryLabel)
        }
        .menuRowPadding(vertical: T.space4)
    }

    var logsSecondaryControlRow: some View {
        HStack(spacing: T.space6) {
            self.logsLevelFilterButtons

            self.compactTopIcon(
                "line.3.horizontal.decrease.circle",
                label: tr("ui.action.reset_log_filters"))
            {
                self.resetLogFilters()
            }
            .help(tr("ui.action.reset_log_filters"))
            .disabled(!self.hasActiveLogFilters)

            Spacer(minLength: 0)

            self.compactTopIcon(
                "doc.on.doc",
                label: tr("ui.action.copy_all_logs"),
                toneOverride: nativeSecondaryLabel)
            {
                appState.copyAllLogs()
            }
            .help(tr("ui.action.copy_all_logs"))
            .disabled(appState.errorLogs.isEmpty)

            self.compactTopIcon(
                "trash",
                label: tr("ui.action.clear_all_logs"),
                role: .destructive,
                warning: true)
            {
                appState.clearAllLogs()
            }
            .help(tr("ui.action.clear_all_logs"))
            .disabled(appState.errorLogs.isEmpty)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var logsSourceFilterButtons: some View {
        self.logFilterGroup(
            symbol: "line.3.horizontal.decrease.circle",
            allTitle: tr("ui.log_source.all"),
            allSelected: selectedLogSources == self.allLogSourceSelection,
            selectAll: { selectedLogSources = self.allLogSourceSelection },
            items: AppLogSource.allCases,
            itemTitle: { self.logSourcePresentation($0).label },
            itemSelected: { selectedLogSources.contains($0) },
            toggleItem: { self.toggleLogSource($0) })
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    var logsLevelFilterButtons: some View {
        self.logFilterGroup(
            symbol: "slider.horizontal.3",
            allTitle: tr("ui.log_filter.all"),
            allSelected: selectedLogLevels == self.allLogLevelSelection,
            selectAll: { selectedLogLevels = self.allLogLevelSelection },
            items: LogLevelFilter.allCases,
            itemTitle: { tr($0.titleKey) },
            itemSelected: { selectedLogLevels.contains($0) },
            toggleItem: { self.toggleLogLevel($0) })
    }

    // swiftlint:disable:next function_parameter_count
    private func logFilterGroup<V: Hashable>(
        symbol: String,
        allTitle: String,
        allSelected: Bool,
        selectAll: @escaping () -> Void,
        items: [V],
        itemTitle: @escaping (V) -> String,
        itemSelected: @escaping (V) -> Bool,
        toggleItem: @escaping (V) -> Void) -> some View
    {
        HStack(spacing: T.space2) {
            Image(systemName: symbol)
                .font(.app(size: T.FontSize.caption, weight: .semibold))
                .foregroundStyle(nativeTertiaryLabel)

            self.logFilterToggleButton(title: allTitle, selected: allSelected, action: selectAll)

            ForEach(items, id: \.self) { item in
                self.logFilterToggleButton(
                    title: itemTitle(item),
                    selected: itemSelected(item),
                    action: { toggleItem(item) })
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
            self.logFilterButtonLabel(title, action: action).buttonStyle(.borderedProminent)
        } else {
            self.logFilterButtonLabel(title, action: action).buttonStyle(.bordered)
        }
    }

    private func logFilterButtonLabel(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.app(size: T.FontSize.caption, weight: .medium))
                .lineLimit(1)
        }
        .controlSize(.small)
    }

    private static let fullLogSourceSelection = Set(AppLogSource.allCases)
    private static let fullLogLevelSelection = Set(LogLevelFilter.allCases)

    var allLogSourceSelection: Set<AppLogSource> {
        Self.fullLogSourceSelection
    }

    var allLogLevelSelection: Set<LogLevelFilter> {
        Self.fullLogLevelSelection
    }

    func logsCountSummaryBadge(filteredCount: Int) -> some View {
        self.fractionSummaryBadge(current: filteredCount, total: appState.errorLogs.count)
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
        logSearchText.trimmed
    }

    func resetLogFilters() {
        selectedLogSources = self.allLogSourceSelection
        selectedLogLevels = self.allLogLevelSelection
        logSearchText = ""
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

    func refreshVisibleLogs() {
        let source = self.appState.errorLogs.prefix(120)
        let trimmedKeyword = self.trimmedLogKeyword
        let isShowingAllSources = self.selectedLogSources == self.allLogSourceSelection
        let isShowingAllLevels = self.selectedLogLevels == self.allLogLevelSelection

        let nextLogs: [AppErrorLogEntry]
        if trimmedKeyword.isEmpty && isShowingAllSources && isShowingAllLevels {
            nextLogs = Array(source)
        } else {
            nextLogs = source.filter { log in
                guard self.selectedLogSources.contains(log.source) else { return false }
                guard trimmedKeyword.isEmpty || self.logSearchTextContent(for: log)
                    .localizedStandardContains(trimmedKeyword) else { return false }
                return self.selectedLogLevels.contains(self.logLevelFilter(self.normalizedLogLevel(log.level)))
            }
        }

        guard nextLogs != self.visibleLogs else { return }
        self.visibleLogs = nextLogs
    }

    func logEntryRow(_ log: AppErrorLogEntry) -> some View {
        let level = self.normalizedLogLevel(log.level)
        let sourceInfo = self.logSourcePresentation(log.source)
        let levelInfo = self.logLevelPresentation(level)
        let parsed = self.parseLogMessage(log.message)
        let tone = levelInfo.color
        let symbol = levelInfo.symbol

        return HStack(alignment: .center, spacing: T.space6) {
            RoundedRectangle(cornerRadius: T.cornerRadius, style: .continuous)
                .fill(tone.opacity(T.Opacity.tint))
                .frame(
                    width: T.rowLeadingIcon,
                    height: T.rowLeadingIcon)
                .overlay {
                    Image(systemName: symbol)
                        .font(.app(size: T.FontSize.caption, weight: .semibold))
                        .foregroundStyle(tone)
                }

            VStack(alignment: .leading, spacing: T.space2) {
                HStack(spacing: T.space2) {
                    Text("[\(sourceInfo.label)]")
                        .font(.app(size: T.FontSize.caption, weight: .semibold))
                        .foregroundStyle(sourceInfo.color)

                    Text("[\(levelInfo.label)]")
                        .font(.app(size: T.FontSize.caption, weight: .semibold))
                        .foregroundStyle(tone)

                    if let protocolTag = parsed.protocolTag {
                        Text(protocolTag)
                            .font(.app(size: T.FontSize.caption, weight: .semibold))
                            .foregroundStyle(parsed.protocolColor)
                    }

                    Text(ValueFormatter.dateTime(log.timestamp))
                        .font(.app(size: T.FontSize.caption, weight: .regular))
                        .foregroundStyle(nativeTertiaryLabel)
                        .lineLimit(1)
                }

                Text(parsed.mainText)
                    .font(.app(size: T.FontSize.caption, weight: .regular))
                    .foregroundStyle(nativePrimaryLabel)
                    .fixedSize(horizontal: false, vertical: true)

                if let detailText = parsed.detailText {
                    Text(detailText)
                        .font(.app(size: T.FontSize.caption, weight: .regular))
                        .foregroundStyle(nativeSecondaryLabel)
                        .lineLimit(2)
                        .padding(.leading, T.space6)
                        .overlay(alignment: .leading) {
                            Rectangle()
                                .fill(tone.opacity(T.Opacity.tint))
                                .frame(width: T.space1)
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
        let lower = raw.trimmed.lowercased()
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
            (tr("ui.log_source.mihomo"), nativeAccent.opacity(T.Opacity.solid))
        }
    }

    func logLevelPresentation(_ normalizedLevel: String)
        -> (filter: LogLevelFilter, label: String, color: Color, symbol: String)
    {
        let filter = self.logLevelFilter(normalizedLevel)
        switch filter {
        case .error:
            return (
                LogLevelFilter.error,
                tr("ui.log_filter.error"),
                nativeCritical.opacity(T.Opacity.solid),
                "exclamationmark.octagon.fill")
        case .warning:
            return (
                LogLevelFilter.warning,
                tr("ui.log_filter.warning"),
                nativeWarning.opacity(T.Opacity.solid),
                "exclamationmark.triangle.fill")
        case .info:
            return (
                LogLevelFilter.info,
                tr("ui.log_filter.info"),
                nativeAccent.opacity(T.Opacity.solid),
                "info.circle.fill")
        }
    }

    func logLevelFilter(_ normalizedLevel: String) -> LogLevelFilter {
        switch normalizedLevel {
        case "ERROR":
            .error
        case "WARNING":
            .warning
        default:
            .info
        }
    }

    func parseLogMessage(_ raw: String)
    -> (protocolTag: String?, protocolColor: Color, mainText: String, detailText: String?) {
        var message = raw.trimmed
        if message.isEmpty {
            return (nil, nativeSecondaryLabel, tr("ui.common.na"), nil)
        }

        if let extracted = firstRegexCapture(in: message, regex: CachedLogRegex.msgField), !extracted.isEmpty {
            message = extracted
        }

        var detailText: String?
        if let trailingBracket = firstRegexCapture(in: message, regex: CachedLogRegex.trailingBracket) {
            detailText = trailingBracket
            message = message.replacingOccurrences(of: trailingBracket, with: "").trimmed
        }

        var protocolTag: String?
        var protocolColor = nativeAccent.opacity(T.Opacity.solid)
        if let tag = firstRegexCapture(in: message, regex: CachedLogRegex.protocolTag) {
            protocolTag = tag
            message = message.replacingOccurrences(of: tag, with: "").trimmed

            let upper = tag.uppercased()
            if upper.contains("UDP") { protocolColor = nativeWarning.opacity(T.Opacity.solid) }
            if upper.contains("DNS") { protocolColor = nativePositive.opacity(T.Opacity.solid) }
            if upper.contains("HTTP") { protocolColor = nativeAccent.opacity(T.Opacity.solid) }
        }

        if message.isEmpty {
            message = raw.trimmed
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
