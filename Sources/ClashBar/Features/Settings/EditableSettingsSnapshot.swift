import Foundation
import MihomoKit

struct EditableSettingsSnapshot: Equatable, Codable {
    var mode: CoreMode = .rule
    var allowLan = false
    var ipv6 = false
    var tcpConcurrent = false
    var tunEnabled = false
    var logLevel = ConfigLogLevel.info.rawValue
    var port = "0"
    var socksPort = "0"
    var mixedPort = "7890"
    var redirPort = "0"
    var tproxyPort = "0"

    private static var portKeyPaths: [(key: String, path: WritableKeyPath<Self, String>)] {
        [
            ("port", \.port),
            ("socks-port", \.socksPort),
            ("mixed-port", \.mixedPort),
            ("redir-port", \.redirPort),
            ("tproxy-port", \.tproxyPort),
        ]
    }
}

extension EditableSettingsSnapshot {
    init(config: ConfigSnapshot) {
        self.mode = CoreMode(rawValue: (config.mode ?? "").lowercased()) ?? .rule
        self.allowLan = config.allowLan ?? false
        self.ipv6 = config.ipv6 ?? false
        self.tcpConcurrent = config.tcpConcurrent ?? false
        self.tunEnabled = config.tunEnabled ?? false
        self.logLevel = ConfigLogLevel(rawValue: config.logLevel ?? "")?.rawValue ?? ConfigLogLevel.info.rawValue
        self.port = config.port.map(String.init) ?? ""
        self.socksPort = config.socksPort.map(String.init) ?? ""
        self.mixedPort = config.mixedPort.map(String.init) ?? ""
        self.redirPort = config.redirPort.map(String.init) ?? ""
        self.tproxyPort = config.tproxyPort.map(String.init) ?? ""
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.mode = try container.decodeIfPresent(CoreMode.self, forKey: .mode) ?? .rule
        self.allowLan = try container.decode(Bool.self, forKey: .allowLan)
        self.ipv6 = try container.decode(Bool.self, forKey: .ipv6)
        self.tcpConcurrent = try container.decodeIfPresent(Bool.self, forKey: .tcpConcurrent) ?? false
        self.tunEnabled = try container.decodeIfPresent(Bool.self, forKey: .tunEnabled) ?? false
        self.logLevel = try container.decode(String.self, forKey: .logLevel)
        self.port = try container.decode(String.self, forKey: .port)
        self.socksPort = try container.decode(String.self, forKey: .socksPort)
        self.mixedPort = try container.decode(String.self, forKey: .mixedPort)
        self.redirPort = try container.decode(String.self, forKey: .redirPort)
        self.tproxyPort = try container.decode(String.self, forKey: .tproxyPort)
    }

    func withTunEnabled(_ enabled: Bool) -> EditableSettingsSnapshot {
        var snapshot = self
        snapshot.tunEnabled = enabled
        return snapshot
    }

    func portFields(fallback: EditableSettingsSnapshot? = nil) -> [SettingsPortField] {
        Self.portKeyPaths.map { key, path in
            SettingsPortField(
                key: key,
                value: self[keyPath: path].trimmedNonEmpty ?? fallback?[keyPath: path].trimmed ?? "")
        }
    }

    mutating func mergeRuntimeChanges(from previous: Self, to incoming: Self) {
        self.syncFields([\.allowLan, \.ipv6, \.tcpConcurrent, \.tunEnabled], from: previous, to: incoming)
        self.syncFields([\.logLevel] + Self.portKeyPaths.map(\.path), from: previous, to: incoming)
    }

    private mutating func syncFields(
        _ paths: [WritableKeyPath<Self, some Equatable>],
        from previous: Self,
        to incoming: Self)
    {
        for path in paths where self[keyPath: path] == previous[keyPath: path] {
            self[keyPath: path] = incoming[keyPath: path]
        }
    }
}
