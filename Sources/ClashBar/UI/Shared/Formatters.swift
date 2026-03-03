import Foundation

enum ValueFormatter {
    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private static let iso8601WithFractionalKey = "clashbar.formatter.iso8601.fractional"
    private static let iso8601BasicKey = "clashbar.formatter.iso8601.basic"

    static func speed(_ value: Int64) -> String {
        if value >= 1024 * 1024 {
            return String(format: "%.2f MB/s", Double(value) / (1024 * 1024))
        }
        if value >= 1024 {
            return String(format: "%.2f KB/s", Double(value) / 1024)
        }
        return "\(value) B/s"
    }

    static func bytesInteger(_ value: Int64) -> String {
        let kb: Int64 = 1024
        let mb = kb * 1024
        let gb = mb * 1024
        let tb = gb * 1024

        if value >= tb {
            return self.roundedBytesText(value, divisor: Double(tb), unit: "TB")
        }
        if value >= gb {
            return self.roundedBytesText(value, divisor: Double(gb), unit: "GB")
        }
        if value >= mb {
            return self.roundedBytesText(value, divisor: Double(mb), unit: "MB")
        }
        if value >= kb {
            return self.roundedBytesText(value, divisor: Double(kb), unit: "KB")
        }
        return "\(value) B"
    }

    static func bytesCompact(_ value: Int64) -> String {
        if value >= 1024 * 1024 * 1024 {
            return String(format: "%.1f GB", Double(value) / (1024 * 1024 * 1024))
        }
        if value >= 1024 * 1024 {
            return String(format: "%.1f MB", Double(value) / (1024 * 1024))
        }
        if value >= 1024 {
            return String(format: "%.1f KB", Double(value) / 1024)
        }
        return "\(value) B"
    }

    static func bytesCompactNoSpace(_ value: Int64) -> String {
        if value >= 1024 * 1024 * 1024 * 1024 {
            return self.compactNoSpace(value: Double(value) / (1024 * 1024 * 1024 * 1024), unit: "TB")
        }
        if value >= 1024 * 1024 * 1024 {
            return self.compactNoSpace(value: Double(value) / (1024 * 1024 * 1024), unit: "GB")
        }
        if value >= 1024 * 1024 {
            return self.compactNoSpace(value: Double(value) / (1024 * 1024), unit: "MB")
        }
        if value >= 1024 {
            return self.compactNoSpace(value: Double(value) / 1024, unit: "KB")
        }
        return "\(value)B"
    }

    static func bytesOrDash(_ value: Int64?) -> String {
        guard let value else { return "--" }
        return self.bytesCompact(value)
    }

    static func speedAndTotal(rate: Int64, total: Int64?) -> String {
        "\(self.speed(rate)) · \(self.bytesOrDash(total))"
    }

    static func subscriptionUsed(upload: Int64?, download: Int64?) -> Int64? {
        guard let upload, let download else { return nil }
        return upload + download
    }

    static func subscriptionRemaining(total: Int64?, upload: Int64?, download: Int64?) -> Int64? {
        guard let total, let used = subscriptionUsed(upload: upload, download: download) else { return nil }
        return max(total - used, 0)
    }

    static func subscriptionRemainingRatio(total: Int64?, upload: Int64?, download: Int64?) -> Double? {
        guard let total, total > 0 else { return nil }
        guard let remaining = subscriptionRemaining(total: total, upload: upload, download: download)
        else { return nil }
        return min(max(Double(remaining) / Double(total), 0), 1)
    }

    static func dateTime(_ date: Date) -> String {
        self.timestampFormatter.string(from: date)
    }

    static func relativeTime(from input: String?, language: AppLanguage, now: Date = Date()) -> String {
        guard let input = input?.trimmingCharacters(in: .whitespacesAndNewlines), !input.isEmpty else {
            return L10n.t("fmt.common.unknown", language: language)
        }

        let parsedDate = self.parseISO8601Date(input)
        guard let date = parsedDate else { return L10n.t("fmt.common.unknown", language: language) }

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
        guard let input = input?.trimmingCharacters(in: .whitespacesAndNewlines), !input.isEmpty else {
            return "--"
        }
        guard let date = parseISO8601Date(input) else { return "--" }
        return self.timestampFormatter.string(from: date)
    }

    static func daysUntilExpiryShort(from unixSeconds: Int64?, language: AppLanguage, now: Date = Date()) -> String {
        guard let unixSeconds, unixSeconds > 0 else { return L10n.t("fmt.common.unknown", language: language) }

        let expiryDate = Date(timeIntervalSince1970: TimeInterval(unixSeconds))
        let seconds = expiryDate.timeIntervalSince(now)
        let day = 86400.0

        if seconds < 0 {
            return L10n.t("fmt.expiry_short.expired", language: language)
        }

        let days = Int(floor(seconds / day))
        if days <= 0 {
            return L10n.t("fmt.expiry_short.today", language: language)
        }
        return L10n.t("fmt.expiry_short.days", language: language, days)
    }

    private static func compactNoSpace(value: Double, unit: String) -> String {
        if abs(value.rounded() - value) < 0.05 {
            return "\(Int(value.rounded()))\(unit)"
        }
        return String(format: "%.1f%@", value, unit)
    }

    private static func roundedBytesText(_ value: Int64, divisor: Double, unit: String) -> String {
        let scaled = Double(value) / divisor
        let rounded = Int(scaled.rounded())
        return "\(rounded) \(unit)"
    }

    private static func parseISO8601Date(_ input: String) -> Date? {
        if let date = threadLocalISO8601Formatter(withFractionalSeconds: true).date(from: input) {
            return date
        }
        return self.threadLocalISO8601Formatter(withFractionalSeconds: false).date(from: input)
    }

    private static func threadLocalISO8601Formatter(withFractionalSeconds: Bool) -> ISO8601DateFormatter {
        let key = withFractionalSeconds ? self.iso8601WithFractionalKey : self.iso8601BasicKey
        if let formatter = Thread.current.threadDictionary[key] as? ISO8601DateFormatter {
            return formatter
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = withFractionalSeconds
            ? [.withInternetDateTime, .withFractionalSeconds]
            : [.withInternetDateTime]
        Thread.current.threadDictionary[key] = formatter
        return formatter
    }
}
