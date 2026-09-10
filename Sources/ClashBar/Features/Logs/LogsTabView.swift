import SwiftUI

// swiftlint:disable:next type_name
private typealias T = MenuBarLayoutTokens

struct LogsTabView: TranslatingView {
    @EnvironmentObject var appViewModel: AppViewModel
    @EnvironmentObject var logsStore: LogsStore

    var body: some View {
        let logs = self.logsStore.visibleLogs

        return VStack(alignment: .leading, spacing: T.space6) {
            self.logsControlCard(filteredCount: logs.count)

            if logs.isEmpty {
                emptyCard(self.tr("ui.empty.logs"))
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(logs) { log in
                        self.logEntryRow(log)
                            .padding(.horizontal, T.space4)
                            .padding(.vertical, T.space4)
                        if log.id != logs.last?.id {
                            Divider()
                        }
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

                self.fractionSummaryBadge(current: filteredCount, total: self.logsStore.errorLogs.count)
            }
            self.logsSecondaryControlRow
            TextField(self.tr("ui.placeholder.search_logs"), text: self.$logsStore.searchText)
                .textFieldStyle(.roundedBorder)
                .font(.app(size: T.FontSize.body, weight: .regular))
                .foregroundStyle(nativePrimaryLabel)
        }
        .menuRowPadding(vertical: T.space4)
    }

    var logsSecondaryControlRow: some View {
        HStack(spacing: T.space6) {
            self.logsLevelFilterButtons

            Spacer(minLength: 0)

            self.compactTopIcon(
                "doc.on.doc",
                label: self.tr("ui.action.copy_all_logs"),
                toneOverride: nativeSecondaryLabel)
            {
                self.logsStore.copyAllLogs()
            }
            .help(self.tr("ui.action.copy_all_logs"))
            .disabled(self.logsStore.errorLogs.isEmpty)

            self.compactTopIcon(
                "trash",
                label: self.tr("ui.action.clear_all_logs"),
                role: .destructive,
                warning: true)
            {
                self.logsStore.clearAllLogs()
            }
            .help(self.tr("ui.action.clear_all_logs"))
            .disabled(self.logsStore.errorLogs.isEmpty)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var logsSourceFilterButtons: some View {
        HStack(spacing: T.space2) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.app(size: T.FontSize.caption, weight: .semibold))
                .foregroundStyle(nativeTertiaryLabel)

            self.filterChip(
                title: self.tr("ui.log_source.all"),
                selected: self.logsStore.selectedSources.isEmpty,
                action: { self.logsStore.selectedSources = [] })

            ForEach(AppLogSource.allCases, id: \.self) { source in
                self.filterChip(
                    title: self.logSourcePresentation(source).label,
                    selected: self.logsStore.selectedSources.contains(source),
                    action: { self.logsStore.toggleSource(source) })
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var logsLevelFilterButtons: some View {
        HStack(spacing: T.space2) {
            Image(systemName: "slider.horizontal.3")
                .font(.app(size: T.FontSize.caption, weight: .semibold))
                .foregroundStyle(nativeTertiaryLabel)

            self.filterChip(
                title: self.tr("ui.log_filter.all"),
                selected: self.logsStore.selectedLevels.isEmpty,
                action: { self.logsStore.selectedLevels = [] })

            ForEach(LogLevelFilter.allCases, id: \.self) { filter in
                self.filterChip(
                    title: self.tr(filter.titleKey),
                    selected: self.logsStore.selectedLevels.contains(filter),
                    action: { self.logsStore.toggleLevel(filter) })
            }
        }
    }

    func logEntryRow(_ log: AppErrorLogEntry) -> some View {
        let level = self.normalizedLogLevel(log.level)
        let sourceInfo = self.logSourcePresentation(log.source)
        let levelInfo = self.logLevelPresentation(level)
        let parsed = self.parseLogMessage(log.message)
        let tone = levelInfo.color
        let symbol = levelInfo.symbol

        return HStack(alignment: .center, spacing: T.space6) {
            Image(systemName: symbol)
                .font(.app(size: T.FontSize.caption, weight: .semibold))
                .foregroundStyle(tone)
                .frame(width: T.rowLeadingIcon, height: T.rowLeadingIcon)

            VStack(alignment: .leading, spacing: T.space2) {
                HStack(spacing: T.space2) {
                    Text(sourceInfo.label)
                        .font(.app(size: T.FontSize.caption, weight: .semibold))
                        .foregroundStyle(sourceInfo.color)

                    if let protocolTag = parsed.protocolTag {
                        self.logMetadataSeparator
                        Text(protocolTag)
                            .font(.app(size: T.FontSize.caption, weight: .semibold))
                            .foregroundStyle(parsed.protocolColor)
                    }

                    self.logMetadataSeparator
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
                self.logsStore.copyLogMessage(log)
            } label: {
                Label(self.tr("ui.action.copy_log_message"), systemImage: "doc.on.doc")
            }

            Button {
                self.logsStore.copyLogEntry(log)
            } label: {
                Label(self.tr("ui.action.copy_log_entry"), systemImage: "doc.plaintext")
            }
        }
    }

    var logMetadataSeparator: some View {
        Text("•")
            .font(.app(size: T.FontSize.caption, weight: .regular))
            .foregroundStyle(nativeTertiaryLabel)
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
            (self.tr("ui.log_source.clashbar"), nativeSecondaryLabel)
        case .mihomo:
            (self.tr("ui.log_source.mihomo"), nativeAccent.opacity(T.Opacity.solid))
        }
    }

    func logLevelPresentation(_ normalizedLevel: String)
        -> (filter: LogLevelFilter, label: String, color: Color, symbol: String)
    {
        let filter = LogLevelFilter.from(normalizedLevel)
        switch filter {
        case .error:
            return (
                LogLevelFilter.error,
                self.tr("ui.log_filter.error"),
                nativeCritical.opacity(T.Opacity.solid),
                "exclamationmark.octagon.fill")
        case .warning:
            return (
                LogLevelFilter.warning,
                self.tr("ui.log_filter.warning"),
                nativeWarning.opacity(T.Opacity.solid),
                "exclamationmark.triangle.fill")
        case .info:
            return (
                LogLevelFilter.info,
                self.tr("ui.log_filter.info"),
                nativeAccent.opacity(T.Opacity.solid),
                "info.circle.fill")
        }
    }

    func parseLogMessage(_ raw: String)
    -> (protocolTag: String?, protocolColor: Color, mainText: String, detailText: String?) {
        var message = raw.trimmed
        if message.isEmpty {
            return (nil, nativeSecondaryLabel, self.tr("ui.common.na"), nil)
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
            if upper.contains("UDP") {
                protocolColor = nativeWarning.opacity(T.Opacity.solid)
            }
            if upper.contains("DNS") {
                protocolColor = nativePositive.opacity(T.Opacity.solid)
            }
            if upper.contains("HTTP") {
                protocolColor = nativeAccent.opacity(T.Opacity.solid)
            }
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
}

private enum CachedLogRegex {
    static let msgField = try? NSRegularExpression(pattern: #"msg="([^"]+)""#, options: [])
    static let trailingBracket = try? NSRegularExpression(pattern: #"(?:\s|^)(\[[^\[\]]+\])\s*$"#, options: [])
    static let protocolTag = try? NSRegularExpression(pattern: #"(\[(?:TCP|UDP|DNS|HTTP|HTTPS)\])"#, options: [])
}
