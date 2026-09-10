import Foundation

struct SystemProxyPorts: Equatable {
    let httpPort: Int?
    let httpsPort: Int?
    let socksPort: Int?

    static let disabled = SystemProxyPorts(httpPort: nil, httpsPort: nil, socksPort: nil)

    var hasEnabledPort: Bool {
        self.primaryPort != nil
    }

    var primaryPort: Int? {
        self.httpPort ?? self.httpsPort ?? self.socksPort
    }

    static func resolve(mixedPort: Int?, httpPort: Int?, socksPort: Int?) -> SystemProxyPorts {
        let norm = { (value: Int?) -> Int? in
            guard let value, (1...65535).contains(value) else { return nil }
            return value
        }
        if let mixed = norm(mixedPort) {
            return SystemProxyPorts(httpPort: mixed, httpsPort: mixed, socksPort: mixed)
        }
        let resolvedHTTP = norm(httpPort)
        return SystemProxyPorts(httpPort: resolvedHTTP, httpsPort: resolvedHTTP, socksPort: norm(socksPort))
    }
}
