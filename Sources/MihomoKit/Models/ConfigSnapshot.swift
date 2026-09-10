import Foundation

public struct ConfigSnapshot: Decodable, Equatable, Sendable {
    public struct TunConfig: Decodable, Equatable, Sendable {
        public let enable: Bool?
        public let stack: String?

        private enum CodingKeys: String, CodingKey {
            case enable
            case stack
        }

        public init(enable: Bool?, stack: String?) {
            self.enable = enable
            self.stack = stack
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.enable = container.decodeFlexibleBool(forKey: .enable)
            self.stack = container.decodeFlexibleString(forKey: .stack)
        }
    }

    public let allowLan: Bool?
    public let mode: String?
    public let logLevel: String?
    public let ipv6: Bool?
    public let tcpConcurrent: Bool?
    public let port: Int?
    public let socksPort: Int?
    public let redirPort: Int?
    public let tproxyPort: Int?
    public let mixedPort: Int?
    public let tun: TunConfig?
    public let externalController: String?
    public let externalUIURL: String?
    public let externalUIName: String?

    public var tunEnabled: Bool? {
        self.tun?.enable
    }

    private enum CodingKeys: String, CodingKey {
        case allowLan = "allow-lan"
        case mode
        case logLevel = "log-level"
        case ipv6
        case tcpConcurrent = "tcp-concurrent"
        case port
        case socksPort = "socks-port"
        case redirPort = "redir-port"
        case tproxyPort = "tproxy-port"
        case mixedPort = "mixed-port"
        case tun
        case externalController = "external-controller"
        case externalUIURL = "external-ui-url"
        case externalUIName = "external-ui-name"
    }

    public init(
        allowLan: Bool? = nil,
        mode: String? = nil,
        logLevel: String? = nil,
        ipv6: Bool? = nil,
        tcpConcurrent: Bool? = nil,
        port: Int? = nil,
        socksPort: Int? = nil,
        redirPort: Int? = nil,
        tproxyPort: Int? = nil,
        mixedPort: Int? = nil,
        tun: TunConfig? = nil,
        externalController: String? = nil,
        externalUIURL: String? = nil,
        externalUIName: String? = nil)
    {
        self.allowLan = allowLan
        self.mode = mode
        self.logLevel = logLevel
        self.ipv6 = ipv6
        self.tcpConcurrent = tcpConcurrent
        self.port = port
        self.socksPort = socksPort
        self.redirPort = redirPort
        self.tproxyPort = tproxyPort
        self.mixedPort = mixedPort
        self.tun = tun
        self.externalController = externalController
        self.externalUIURL = externalUIURL
        self.externalUIName = externalUIName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.allowLan = container.decodeFlexibleBool(forKey: .allowLan)
        self.mode = container.decodeFlexibleString(forKey: .mode)
        self.logLevel = container.decodeFlexibleString(forKey: .logLevel)
        self.ipv6 = container.decodeFlexibleBool(forKey: .ipv6)
        self.tcpConcurrent = container.decodeFlexibleBool(forKey: .tcpConcurrent)
        self.port = container.decodeFlexibleInt(forKey: .port)
        self.socksPort = container.decodeFlexibleInt(forKey: .socksPort)
        self.redirPort = container.decodeFlexibleInt(forKey: .redirPort)
        self.tproxyPort = container.decodeFlexibleInt(forKey: .tproxyPort)
        self.mixedPort = container.decodeFlexibleInt(forKey: .mixedPort)
        self.tun = try? container.decodeIfPresent(TunConfig.self, forKey: .tun)
        self.externalController = container.decodeFlexibleString(forKey: .externalController)
        self.externalUIURL = container.decodeFlexibleString(forKey: .externalUIURL)
        self.externalUIName = container.decodeFlexibleString(forKey: .externalUIName)
    }
}
