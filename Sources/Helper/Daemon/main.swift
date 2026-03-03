import Foundation
import ProxyHelperShared
import Security
import SystemConfiguration

private enum ProxyHelperError: LocalizedError {
    case invalidHost
    case invalidPort
    case missingPreferences
    case missingCurrentSet
    case noEnabledNetworkServices
    case systemConfigurationFailure(action: String, code: Int32, detail: String)

    var errorDescription: String? {
        switch self {
        case .invalidHost:
            "Invalid proxy host"
        case .invalidPort:
            "Invalid proxy port"
        case .missingPreferences:
            "Unable to access system network preferences"
        case .missingCurrentSet:
            "Unable to find current network set"
        case .noEnabledNetworkServices:
            "No enabled network services found"
        case let .systemConfigurationFailure(action, _, detail):
            "\(action) failed: \(detail)"
        }
    }
}

private final class SystemProxyConfigurator {
    private struct ProxyEntrySpec {
        let enableKey: String
        let hostKey: String
        let portKey: String
    }

    private static let proxyEntrySpecs: [ProxyEntrySpec] = [
        ProxyEntrySpec(
            enableKey: kSCPropNetProxiesHTTPEnable as String,
            hostKey: kSCPropNetProxiesHTTPProxy as String,
            portKey: kSCPropNetProxiesHTTPPort as String),
        ProxyEntrySpec(
            enableKey: kSCPropNetProxiesHTTPSEnable as String,
            hostKey: kSCPropNetProxiesHTTPSProxy as String,
            portKey: kSCPropNetProxiesHTTPSPort as String),
        ProxyEntrySpec(
            enableKey: kSCPropNetProxiesSOCKSEnable as String,
            hostKey: kSCPropNetProxiesSOCKSProxy as String,
            portKey: kSCPropNetProxiesSOCKSPort as String),
    ]

    func setSystemProxy(host: String, httpPort: Int, httpsPort: Int, socksPort: Int) throws {
        try self.validate(host: host)
        let ports = try validatedPorts(
            httpPort: httpPort,
            httpsPort: httpsPort,
            socksPort: socksPort,
            requiresEnabledProxy: true)

        try withMutableProxyProtocols { protocols in
            for proxyProtocol in protocols {
                var config = self.configuration(for: proxyProtocol)
                let portValues = [ports.httpPort, ports.httpsPort, ports.socksPort]
                for (spec, portValue) in zip(Self.proxyEntrySpecs, portValues) {
                    self.configureProxyEntry(
                        config: &config,
                        spec: spec,
                        host: host,
                        port: portValue)
                }

                guard SCNetworkProtocolSetConfiguration(proxyProtocol, config as CFDictionary) else {
                    throw self.systemConfigurationError(action: "Set proxy configuration")
                }
            }
        }
    }

    func clearSystemProxy() throws {
        try self.withMutableProxyProtocols { protocols in
            for proxyProtocol in protocols {
                var config = self.configuration(for: proxyProtocol)
                for spec in Self.proxyEntrySpecs {
                    self.configureProxyEntry(config: &config, spec: spec, host: "", port: 0)
                }

                guard SCNetworkProtocolSetConfiguration(proxyProtocol, config as CFDictionary) else {
                    throw self.systemConfigurationError(action: "Clear proxy configuration")
                }
            }
        }
    }

    func isSystemProxyEnabled() throws -> Bool {
        let preferences = try makePreferences()
        let protocols = try proxyProtocols(from: preferences)

        for proxyProtocol in protocols {
            let config = self.configuration(for: proxyProtocol)
            if Self.proxyEntrySpecs.contains(where: { isEnabled(config: config, key: $0.enableKey) }) {
                return true
            }
        }

        return false
    }

    func isSystemProxyConfigured(host: String, httpPort: Int, httpsPort: Int, socksPort: Int) throws -> Bool {
        try self.validate(host: host)
        let ports = try validatedPorts(
            httpPort: httpPort,
            httpsPort: httpsPort,
            socksPort: socksPort,
            requiresEnabledProxy: true)

        let preferences = try makePreferences()
        let protocols = try proxyProtocols(from: preferences)
        let expectedPorts = [ports.httpPort, ports.httpsPort, ports.socksPort]

        for proxyProtocol in protocols {
            let config = self.configuration(for: proxyProtocol)
            for (spec, expectedPort) in zip(Self.proxyEntrySpecs, expectedPorts) {
                guard self.proxyMatchesExpectedState(
                    config: config,
                    spec: spec,
                    expectedHost: host,
                    expectedPort: expectedPort)
                else {
                    return false
                }
            }
        }

        return true
    }

    private func validate(host: String) throws {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else {
            throw ProxyHelperError.invalidHost
        }
    }

    private func validatedPorts(
        httpPort: Int,
        httpsPort: Int,
        socksPort: Int,
        requiresEnabledProxy: Bool) throws -> (httpPort: Int, httpsPort: Int, socksPort: Int)
    {
        let httpPort = try validatedPort(httpPort)
        let httpsPort = try validatedPort(httpsPort)
        let socksPort = try validatedPort(socksPort)

        if requiresEnabledProxy, httpPort == 0, httpsPort == 0, socksPort == 0 {
            throw ProxyHelperError.invalidPort
        }

        return (httpPort: httpPort, httpsPort: httpsPort, socksPort: socksPort)
    }

    private func validatedPort(_ value: Int) throws -> Int {
        guard (0...65535).contains(value) else {
            throw ProxyHelperError.invalidPort
        }
        return value
    }

    private func configureProxyEntry(
        config: inout [String: Any],
        spec: ProxyEntrySpec,
        host: String,
        port: Int)
    {
        if port > 0 {
            config[spec.enableKey] = 1
            config[spec.hostKey] = host
            config[spec.portKey] = port
        } else {
            config[spec.enableKey] = 0
            config[spec.hostKey] = ""
            config[spec.portKey] = 0
        }
    }

    private func withMutableProxyProtocols(_ update: ([SCNetworkProtocol]) throws -> Void) throws {
        let preferences = try makePreferences()

        guard SCPreferencesLock(preferences, true) else {
            throw self.systemConfigurationError(action: "Lock system preferences")
        }
        defer { SCPreferencesUnlock(preferences) }

        let protocols = try proxyProtocols(from: preferences)
        try update(protocols)

        guard SCPreferencesCommitChanges(preferences) else {
            throw self.systemConfigurationError(action: "Commit proxy preferences")
        }
        guard SCPreferencesApplyChanges(preferences) else {
            throw self.systemConfigurationError(action: "Apply proxy preferences")
        }
    }

    private func makePreferences() throws -> SCPreferences {
        guard let preferences = SCPreferencesCreate(nil, "com.clashbar.helper" as CFString, nil) else {
            throw ProxyHelperError.missingPreferences
        }
        return preferences
    }

    private func proxyProtocols(from preferences: SCPreferences) throws -> [SCNetworkProtocol] {
        guard let currentSet = SCNetworkSetCopyCurrent(preferences) else {
            throw ProxyHelperError.missingCurrentSet
        }

        guard let services = SCNetworkSetCopyServices(currentSet) as? [SCNetworkService] else {
            throw ProxyHelperError.noEnabledNetworkServices
        }

        let protocols = services.compactMap { service -> SCNetworkProtocol? in
            guard SCNetworkServiceGetEnabled(service) else {
                return nil
            }
            return SCNetworkServiceCopyProtocol(service, kSCNetworkProtocolTypeProxies)
        }

        guard !protocols.isEmpty else {
            throw ProxyHelperError.noEnabledNetworkServices
        }

        return protocols
    }

    private func configuration(for proxyProtocol: SCNetworkProtocol) -> [String: Any] {
        (SCNetworkProtocolGetConfiguration(proxyProtocol) as? [String: Any]) ?? [:]
    }

    private func isEnabled(config: [String: Any], key: String) -> Bool {
        if let value = config[key] as? NSNumber {
            return value.intValue != 0
        }
        if let value = config[key] as? Int {
            return value != 0
        }
        if let value = config[key] as? Bool {
            return value
        }
        return false
    }

    private func proxyHostAndPortMatch(
        config: [String: Any],
        spec: ProxyEntrySpec,
        expectedHost: String,
        expectedPort: Int) -> Bool
    {
        let currentHost = (config[spec.hostKey] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        let normalizedExpectedHost = expectedHost
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard currentHost == normalizedExpectedHost else {
            return false
        }

        return self.intValue(config[spec.portKey]) == expectedPort
    }

    private func proxyMatchesExpectedState(
        config: [String: Any],
        spec: ProxyEntrySpec,
        expectedHost: String,
        expectedPort: Int) -> Bool
    {
        let enabled = self.isEnabled(config: config, key: spec.enableKey)
        if expectedPort == 0 {
            return !enabled
        }
        guard enabled else {
            return false
        }
        return self.proxyHostAndPortMatch(
            config: config,
            spec: spec,
            expectedHost: expectedHost,
            expectedPort: expectedPort)
    }

    private func intValue(_ value: Any?) -> Int? {
        if let intValue = value as? Int {
            return intValue
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let string = value as? String {
            return Int(string)
        }
        return nil
    }

    private func systemConfigurationError(action: String) -> ProxyHelperError {
        let code = SCError()
        let detail = String(cString: SCErrorString(code))
        return .systemConfigurationFailure(action: action, code: code, detail: detail)
    }
}

private final class ProxyHelperService: NSObject, ProxyHelperProtocol {
    private let configurator = SystemProxyConfigurator()

    func setSystemProxy(
        host: String,
        httpPort: Int,
        httpsPort: Int,
        socksPort: Int,
        completion: @escaping (Bool, String?) -> Void)
    {
        do {
            try self.configurator.setSystemProxy(
                host: host,
                httpPort: httpPort,
                httpsPort: httpsPort,
                socksPort: socksPort)
            completion(true, nil)
        } catch {
            completion(false, error.localizedDescription)
        }
    }

    func clearSystemProxy(completion: @escaping (Bool, String?) -> Void) {
        do {
            try self.configurator.clearSystemProxy()
            completion(true, nil)
        } catch {
            completion(false, error.localizedDescription)
        }
    }

    func getSystemProxyState(completion: @escaping (Bool, Bool, String?) -> Void) {
        do {
            let enabled = try configurator.isSystemProxyEnabled()
            completion(true, enabled, nil)
        } catch {
            completion(false, false, error.localizedDescription)
        }
    }

    func isSystemProxyConfigured(
        host: String,
        httpPort: Int,
        httpsPort: Int,
        socksPort: Int,
        completion: @escaping (Bool, Bool, String?) -> Void)
    {
        do {
            let configured = try configurator.isSystemProxyConfigured(
                host: host,
                httpPort: httpPort,
                httpsPort: httpsPort,
                socksPort: socksPort)
            completion(true, configured, nil)
        } catch {
            completion(false, false, error.localizedDescription)
        }
    }
}

private struct SigningIdentity {
    let identifier: String
    let teamIdentifier: String?
}

private final class XPCClientValidator {
    private lazy var helperIdentity: SigningIdentity? = signingIdentityForCurrentProcess()

    func isValid(connection: NSXPCConnection) -> Bool {
        guard let clientIdentity = signingIdentity(for: connection.processIdentifier) else {
            return false
        }

        guard clientIdentity.identifier == ProxyHelperConstants.allowedClientBundleIdentifier else {
            return false
        }

        guard let helperIdentity else {
            return false
        }

        if let helperTeamIdentifier = helperIdentity.teamIdentifier,
           let clientTeamIdentifier = clientIdentity.teamIdentifier
        {
            return helperTeamIdentifier == clientTeamIdentifier
        }

        // Ad-hoc/local builds do not provide Team ID. Keep identifier-based checks active
        // and rely on launchd registration + code signing requirement gate.
        return true
    }

    private func signingIdentityForCurrentProcess() -> SigningIdentity? {
        var code: SecCode?
        guard SecCodeCopySelf(SecCSFlags(), &code) == errSecSuccess, let code else {
            return nil
        }
        return self.signingIdentity(for: code)
    }

    private func signingIdentity(for pid: pid_t) -> SigningIdentity? {
        let attributes: [String: Any] = [kSecGuestAttributePid as String: pid]
        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes as CFDictionary, SecCSFlags(), &code) == errSecSuccess,
              let code
        else {
            return nil
        }
        return self.signingIdentity(for: code)
    }

    private func signingIdentity(for code: SecCode) -> SigningIdentity? {
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess,
              let staticCode
        else {
            return nil
        }
        return self.signingIdentity(for: staticCode)
    }

    private func signingIdentity(for staticCode: SecStaticCode) -> SigningIdentity? {
        var signingInformation: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &signingInformation) == errSecSuccess,
            let signingInformation = signingInformation as? [String: Any],
            let identifier = signingInformation[kSecCodeInfoIdentifier as String] as? String
        else {
            return nil
        }

        let teamIdentifier = signingInformation[kSecCodeInfoTeamIdentifier as String] as? String
        return SigningIdentity(identifier: identifier, teamIdentifier: teamIdentifier)
    }
}

private final class ProxyHelperListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let service = ProxyHelperService()
    private let validator = XPCClientValidator()

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        guard self.validator.isValid(connection: newConnection) else {
            return false
        }
        newConnection.exportedInterface = NSXPCInterface(with: ProxyHelperProtocol.self)
        newConnection.exportedObject = self.service
        newConnection.resume()
        return true
    }
}

@main
private struct ClashBarProxyHelperMain {
    static func main() {
        let delegate = ProxyHelperListenerDelegate()
        let listener = NSXPCListener(machServiceName: ProxyHelperConstants.machServiceName)
        listener.delegate = delegate
        listener.setConnectionCodeSigningRequirement(ProxyHelperConstants.allowedClientRequirement)
        listener.resume()
        dispatchMain()
    }
}
