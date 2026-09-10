import Foundation
import MihomoKit

enum WebUIEndpointBuilder {
    static func normalizeControllerAddress(_ value: String) -> String {
        if value.hasPrefix("http://") || value.hasPrefix("https://") {
            return value
        }
        return "http://\(value)"
    }

    static func makeControllerUIURL(
        controller: String,
        secret: String? = nil,
        hasConfiguredExternalUI: Bool = false,
        externalUIName: String? = nil) -> String
    {
        if hasConfiguredExternalUI {
            return self.configuredControllerUIURL(controller: controller, externalUIName: externalUIName)
        }
        return self.metaCubeXDSetupURL(controller: controller, secret: secret)
    }

    static func configuredControllerUIURL(controller: String, externalUIName: String?) -> String {
        let normalized = self.normalizeControllerAddress(controller)
        guard var components = URLComponents(string: normalized) else {
            return "\(normalized)/ui"
        }

        var path = "/ui"
        if let externalUIName = externalUIName?.trimmedNonEmpty {
            path += "/\(externalUIName.urlPathSegmentEscaped)"
        }
        components.path = path
        components.query = nil
        components.fragment = nil
        return components.string ?? "\(normalized)\(path)"
    }

    static func metaCubeXDSetupURL(controller: String, secret: String?) -> String {
        let controllerComponents = URLComponents(string: self.normalizeControllerAddress(controller))
        let usesHTTPS = controllerComponents?.scheme?.lowercased() == "https"
        let host = controllerComponents?.host?.trimmedNonEmpty ?? "127.0.0.1"
        let port = controllerComponents?.port ?? (usesHTTPS ? 443 : 80)

        var fragmentComponents = URLComponents()
        fragmentComponents.path = "/setup"
        fragmentComponents.queryItems = [
            URLQueryItem(name: "http", value: usesHTTPS ? "false" : "true"),
            URLQueryItem(name: "hostname", value: host),
            URLQueryItem(name: "port", value: String(port)),
            URLQueryItem(name: "secret", value: secret?.trimmed ?? ""),
        ]

        var components = URLComponents(string: "https://metacubex.github.io/metacubexd/")!
        components.fragment = fragmentComponents.string
        return components.string ?? "https://metacubex.github.io/metacubexd/#/setup"
    }

    static func isExternalControllerWildcardIPv4(host: String?) -> Bool {
        guard let host = host?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return false
        }
        return host == "0.0.0.0"
    }
}
