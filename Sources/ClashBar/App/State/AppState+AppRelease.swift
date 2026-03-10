import Foundation

@MainActor
extension AppState {
    var currentAppVersionText: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        if let short, !short.isEmpty { return short }
        if let build, !build.isEmpty { return build }
        return "0.0.1"
    }

    var availableAppUpdate: AppReleaseInfo? {
        guard let latestAppReleaseInfo else { return nil }
        guard !latestAppReleaseInfo.isDraft, !latestAppReleaseInfo.isPrerelease else { return nil }
        guard AppSemanticVersion.isNewerRelease(
            tagName: latestAppReleaseInfo.tagName,
            than: self.currentAppVersionText)
        else {
            return nil
        }
        return latestAppReleaseInfo
    }

    var appReleaseIndexURL: URL? {
        URL(string: "https://github.com/Sitoi/ClashBar/releases")
    }

    func refreshLatestAppRelease() async {
        guard !self.isLatestAppReleaseCheckInFlight else { return }

        self.isLatestAppReleaseCheckInFlight = true
        defer {
            self.isLatestAppReleaseCheckInFlight = false
        }

        do {
            let release = try await AppReleaseService.fetchLatestRelease(currentVersion: self.currentAppVersionText)
            guard !Task.isCancelled else { return }
            guard self.latestAppReleaseInfo != release else { return }
            self.latestAppReleaseInfo = release
        } catch {
            guard !Task.isCancelled else { return }
        }
    }
}
