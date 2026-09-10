import Foundation

@MainActor
enum ValueFormatter {
    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    private static let shortTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let shortDateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MM-dd HH:mm"
        return f
    }()

    static func speed(_ value: Int64) -> String {
        let normalized = max(0, value)
        if normalized >= 1024 * 1024 {
            return String(format: "%.2f MB/s", Double(normalized) / (1024 * 1024))
        }
        return String(format: "%.2f KB/s", Double(normalized) / 1024)
    }

    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .binary
        return f
    }()

    static func bytesCompact(_ value: Int64) -> String {
        self.byteFormatter.string(fromByteCount: max(0, value))
    }

    static func bytesCompactNoSpace(_ value: Int64) -> String {
        self.byteFormatter.string(fromByteCount: max(0, value)).replacingOccurrences(of: " ", with: "")
    }

    static func bytesOrDash(_ value: Int64?) -> String {
        guard let value else { return "--" }
        return self.bytesCompact(value)
    }

    static func speedAndTotal(rate: Int64, total: Int64?) -> String {
        "\(self.speed(rate)) · \(self.bytesOrDash(total))"
    }

    static func dateTime(_ date: Date) -> String {
        self.timestampFormatter.string(from: date)
    }

    static func relativeTime(from input: String?, language: AppLanguage, now: Date = Date()) -> String {
        guard let input = input?.trimmingCharacters(in: .whitespacesAndNewlines), !input.isEmpty else {
            return L10n.t("fmt.common.unknown", language: language)
        }

        guard let date = self.parseISO8601Date(input) else {
            return L10n.t("fmt.common.unknown", language: language)
        }

        let interval = max(0, now.timeIntervalSince(date))
        let minutes = Int(interval / 60)
        if minutes < 60 {
            return L10n.t("fmt.relative.minutes", language: language, minutes)
        }

        let hours = Int(interval / 3600)
        if hours < 24 {
            return L10n.t("fmt.relative.hours", language: language, hours)
        }

        let days = Int(interval / 86400)
        return L10n.t("fmt.relative.days", language: language, days)
    }

    static func dateTimeFromISO(_ input: String?) -> String {
        guard let input = input?.trimmingCharacters(in: .whitespacesAndNewlines), !input.isEmpty,
              let date = parseISO8601Date(input)
        else { return "--" }
        return self.dateTime(date)
    }

    static func daysUntilExpiryShort(from unixSeconds: Int64?, language: AppLanguage, now: Date = Date()) -> String {
        guard let unixSeconds else { return L10n.t("fmt.common.unknown", language: language) }
        if unixSeconds == 0 {
            return L10n.t("fmt.expiry_short.long_term", language: language)
        }
        guard unixSeconds > 0 else { return L10n.t("fmt.common.unknown", language: language) }

        let expiryDate = Date(timeIntervalSince1970: TimeInterval(unixSeconds))
        let seconds = expiryDate.timeIntervalSince(now)

        if seconds < 0 {
            return L10n.t("fmt.expiry_short.expired", language: language)
        }

        let days = Int(floor(seconds / 86400.0))
        if days <= 0 {
            return L10n.t("fmt.expiry_short.today", language: language)
        }
        return L10n.t("fmt.expiry_short.days", language: language, days)
    }

    static func parseISO8601Date(_ input: String) -> Date? {
        try? Date(input, strategy: .iso8601)
    }

    static func remoteConfigMenuStatusLine(
        autoUpdateEnabled: Bool,
        nextUpdateAt: Date?,
        lastUpdateAt: Date?,
        language: AppLanguage,
        now: Date = Date()) -> String?
    {
        var parts: [String] = []

        if autoUpdateEnabled, let next = nextUpdateAt {
            let remaining = max(0, Int(next.timeIntervalSince(now)))
            let minutes = (remaining / 60) % 60
            let hours = remaining / 3600
            if hours > 0 {
                parts.append(L10n.t("fmt.remote_config.next_update_hours_minutes", language: language, hours, minutes))
            } else {
                parts.append(L10n.t("fmt.remote_config.next_update_minutes", language: language, max(1, minutes)))
            }
        }

        if let last = lastUpdateAt {
            let calendar = Calendar.current
            let formatted = calendar.isDate(last, inSameDayAs: now)
                ? self.shortTimeFormatter.string(from: last)
                : self.shortDateTimeFormatter.string(from: last)
            parts.append(L10n.t("fmt.remote_config.last_update", language: language, formatted))
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
