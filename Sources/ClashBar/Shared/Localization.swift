import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case zhHans = "zh-Hans"
    case en

    var id: String {
        rawValue
    }

    var localeIdentifier: String {
        switch self {
        case .zhHans:
            "zh_Hans_CN"
        case .en:
            "en_US_POSIX"
        }
    }
}

enum L10n {
    private static let bundleLock = NSLock()
    private nonisolated(unsafe) static var cachedBundles: [AppLanguage: Bundle] = [:]

    static func t(_ key: String, language: AppLanguage, _ args: CVarArg...) -> String {
        self.t(key, language: language, args: args)
    }

    static func t(_ key: String, language: AppLanguage, args: [CVarArg]) -> String {
        let format = self.localizedString(for: key, language: language)
        guard !args.isEmpty else { return format }
        return String(format: format, locale: self.locale(for: language), arguments: args)
    }

    private static func localizedBundle(for language: AppLanguage) -> Bundle? {
        self.bundleLock.withLock {
            if let cached = self.cachedBundles[language] {
                return cached
            }
            for bundle in AppResourceBundleLocator.candidateBundles() {
                if let found = self.localizationBundle(in: bundle, language: language) {
                    self.cachedBundles[language] = found
                    return found
                }
            }
            return nil
        }
    }

    private static func localizedString(for key: String, language: AppLanguage) -> String {
        if let bundle = self.localizedBundle(for: language) {
            let value = bundle.localizedString(forKey: key, value: key, table: nil)
            if value != key {
                return value
            }
        }

        if language != .zhHans, let fallbackBundle = self.localizedBundle(for: .zhHans) {
            let fallbackValue = fallbackBundle.localizedString(forKey: key, value: key, table: nil)
            if fallbackValue != key {
                return fallbackValue
            }
        }

        return key
    }

    private static func localizationBundle(in bundle: Bundle, language: AppLanguage) -> Bundle? {
        let candidateLocalizationNames = self.localizationNames(in: bundle, for: language)
        let candidatePaths: [String?] = candidateLocalizationNames.flatMap { localizationName in
            [
                bundle.path(forResource: localizationName, ofType: "lproj"),
                bundle.path(forResource: localizationName, ofType: "lproj", inDirectory: "Localization"),
                bundle.resourceURL?
                    .appendingPathComponent("Localization", isDirectory: true)
                    .appendingPathComponent("\(localizationName).lproj", isDirectory: true)
                    .path,
            ]
        }

        for path in candidatePaths.compactMap(\.self) {
            if let localizedBundle = Bundle(path: path) {
                return localizedBundle
            }
        }

        return nil
    }

    private static func localizationNames(in bundle: Bundle, for language: AppLanguage) -> [String] {
        let requestedName = language.rawValue
        let normalizedRequestedName = self.normalizedLocalizationName(requestedName)

        var names: [String] = [requestedName]
        for localization in bundle.localizations where
            self.normalizedLocalizationName(localization) == normalizedRequestedName
        {
            names.append(localization)
        }

        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }

    private static func normalizedLocalizationName(_ name: String) -> String {
        name
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
    }

    private static let zhHansLocale = Locale(identifier: "zh_Hans_CN")
    private static let enLocale = Locale(identifier: "en_US_POSIX")

    private static func locale(for language: AppLanguage) -> Locale {
        switch language {
        case .zhHans: self.zhHansLocale
        case .en: self.enLocale
        }
    }
}
