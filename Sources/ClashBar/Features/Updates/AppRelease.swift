import Foundation

struct AppReleaseInfo: Decodable, Equatable {
    let tagName: String
    let name: String?
    let releaseURL: URL
    let isDraft: Bool
    let isPrerelease: Bool

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case releaseURL = "html_url"
        case isDraft = "draft"
        case isPrerelease = "prerelease"
    }

    var displayVersion: String {
        AppSemanticVersion.normalizedDisplayVersion(from: self.tagName)
    }
}

enum AppSemanticVersion {
    static func normalizedDisplayVersion(from rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let clean = trimmed.drop(while: { !$0.isNumber })
        let versionPart = clean.split(whereSeparator: { $0 == "-" || $0 == "+" }).first ?? clean
        return versionPart.isEmpty ? trimmed : String(versionPart)
    }

    static func isNewerRelease(tagName: String, than currentVersion: String) -> Bool {
        let tag = self.normalizedDisplayVersion(from: tagName)
        let current = self.normalizedDisplayVersion(from: currentVersion)
        return tag.compare(current, options: .numeric) == .orderedDescending
    }
}
