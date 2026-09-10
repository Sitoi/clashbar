import Foundation
import MihomoKit

enum TerminalProxyCommandBuilder {
    static func terminalProxyCommand(host: String, httpPort: Int, socksPort: Int) -> String {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let formattedHost = trimmedHost.contains(":") && !trimmedHost.hasPrefix("[") ? "[\(trimmedHost)]" : trimmedHost
        return "export https_proxy=http://\(formattedHost):\(httpPort) " +
            "http_proxy=http://\(formattedHost):\(httpPort) " +
            "all_proxy=socks5://\(formattedHost):\(socksPort)"
    }

    static func buildSystemProxyDisplayString(host: String, ports: SystemProxyPorts) -> String? {
        guard let port = ports.primaryPort, port > 0 else { return nil }
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedHost.contains(":"), !trimmedHost.hasPrefix("[") {
            return "[\(trimmedHost)]:\(port)"
        }
        return "\(trimmedHost):\(port)"
    }

    static func managedEndpointProxyCommandHost(
        isRemoteTarget: Bool,
        controllerHost: String,
        configuredHost: String?,
        allowLan: Bool) -> String
    {
        guard !isRemoteTarget else {
            return controllerHost
        }

        let effectiveHost = configuredHost ?? controllerHost
        guard allowLan else {
            return effectiveHost
        }
        guard self.shouldUseCurrentDeviceIPv4ForProxyCommand(host: effectiveHost) else {
            return effectiveHost
        }

        return DeviceIPv4AddressResolver.currentAddress() ?? controllerHost
    }

    static func shouldUseCurrentDeviceIPv4ForProxyCommand(host: String) -> Bool {
        switch host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "", "localhost", "127.0.0.1", "::1", "0.0.0.0", "::", "0:0:0:0:0:0:0:0":
            true
        default:
            false
        }
    }
}
