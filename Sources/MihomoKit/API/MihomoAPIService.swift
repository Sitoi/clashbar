import Foundation

public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case put = "PUT"
    case post = "POST"
    case patch = "PATCH"
    case delete = "DELETE"
}

public enum JSONValue: Sendable {
    case string(String)
    case int(Int)
    case bool(Bool)
    case double(Double)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public var foundationObject: Any {
        switch self {
        case let .string(value):
            value
        case let .int(value):
            value
        case let .bool(value):
            value
        case let .double(value):
            value
        case let .object(value):
            value.mapValues(\.foundationObject)
        case let .array(value):
            value.map(\.foundationObject)
        case .null:
            NSNull()
        }
    }
}

public enum Endpoint: Sendable {
    private static let proxyProvidersPath = "/providers/proxies"
    private static let ruleProvidersPath = "/providers/rules"
    private static let coreUpgradeRequestBody: [String: String] = ["path": "", "payload": ""]

    case version
    case traffic
    case memory
    case logs(level: String?)

    case getConfigs
    case putConfigs(force: Bool)
    case patchConfigs(body: [String: JSONValue])

    case groupDelay(name: String, url: String, timeout: Int)

    case proxies
    case proxyDelay(name: String, url: String, timeout: Int)
    case switchProxy(name: String, target: String)

    case proxyProviders
    case proxyProvider(name: String)
    case updateProxyProvider(name: String)
    case proxyProviderHealthcheck(name: String, url: String, timeout: Int)
    case proxyProviderProxyHealthcheck(provider: String, proxy: String, url: String, timeout: Int)

    case rules
    case ruleProviders
    case updateRuleProvider(name: String)

    case connections(interval: Int?)
    case closeAllConnections
    case closeConnection(id: String)
    case flushFakeIPCache
    case flushDNSCache
    case upgradeCore
    case upgradeGeo

    public var method: HTTPMethod {
        switch self {
        case .version, .traffic, .memory, .logs, .getConfigs, .groupDelay, .proxies, .proxyDelay, .proxyProviders,
             .proxyProvider, .proxyProviderHealthcheck, .proxyProviderProxyHealthcheck, .rules,
             .ruleProviders, .connections:
            .get
        case .putConfigs, .switchProxy, .updateProxyProvider, .updateRuleProvider:
            .put
        case .patchConfigs:
            .patch
        case .closeAllConnections, .closeConnection:
            .delete
        case .flushFakeIPCache, .flushDNSCache, .upgradeCore, .upgradeGeo:
            .post
        }
    }

    public var path: String {
        switch self {
        case .version: "/version"
        case .traffic: "/traffic"
        case .memory: "/memory"
        case .logs: "/logs"
        case .getConfigs, .putConfigs, .patchConfigs: "/configs"
        case let .groupDelay(name, _, _): "/group/\(name.urlPathSegmentEscaped)/delay"
        case .proxies: "/proxies"
        case let .proxyDelay(name, _, _): "/proxies/\(name.urlPathSegmentEscaped)/delay"
        case let .switchProxy(name, _): "/proxies/\(name.urlPathSegmentEscaped)"
        case .proxyProviders:
            Self.proxyProvidersPath
        case let .proxyProvider(name), let .updateProxyProvider(name):
            self.proxyProviderPath(name)
        case let .proxyProviderHealthcheck(name, _, _):
            "\(self.proxyProviderPath(name))/healthcheck"
        case let .proxyProviderProxyHealthcheck(provider, proxy, _, _):
            "\(self.proxyProviderPath(provider))/\(proxy.urlPathSegmentEscaped)/healthcheck"
        case .rules: "/rules"
        case .ruleProviders:
            Self.ruleProvidersPath
        case let .updateRuleProvider(name):
            "\(Self.ruleProvidersPath)/\(name.urlPathSegmentEscaped)"
        case .connections, .closeAllConnections: "/connections"
        case let .closeConnection(id): "/connections/\(id.urlPathSegmentEscaped)"
        case .flushFakeIPCache: "/cache/fakeip/flush"
        case .flushDNSCache: "/cache/dns/flush"
        case .upgradeCore: "/upgrade"
        case .upgradeGeo: "/upgrade/geo"
        }
    }

    public var queryItems: [URLQueryItem] {
        switch self {
        case let .logs(level):
            self.optionalQueryItem(name: "level", value: level)
        case let .putConfigs(force):
            force ? [URLQueryItem(name: "force", value: "true")] : []
        case let .groupDelay(_, url, timeout), let .proxyDelay(_, url, timeout):
            self.healthcheckQueryItems(url: url, timeout: timeout)
        case let .proxyProviderHealthcheck(_, url, timeout), let .proxyProviderProxyHealthcheck(_, _, url, timeout):
            self.healthcheckQueryItems(url: url, timeout: timeout)
        case let .connections(interval):
            self.optionalQueryItem(name: "interval", value: interval.map(String.init))
        default:
            []
        }
    }

    public var body: Data? {
        switch self {
        case let .patchConfigs(body):
            try? JSONSerialization.data(withJSONObject: body.mapValues(\.foundationObject))
        case let .switchProxy(_, target):
            try? JSONSerialization.data(withJSONObject: ["name": target])
        case .upgradeCore, .upgradeGeo:
            try? JSONSerialization.data(withJSONObject: Self.coreUpgradeRequestBody)
        default:
            nil
        }
    }

    public var timeoutInterval: TimeInterval {
        switch self {
        case .proxyProviderHealthcheck:
            180
        case let .groupDelay(_, _, timeout),
             let .proxyDelay(_, _, timeout),
             let .proxyProviderProxyHealthcheck(_, _, _, timeout):
            max(5, TimeInterval(timeout) / 1000.0 + 2)
        case .upgradeCore, .upgradeGeo:
            60
        default:
            2
        }
    }

    public var usesLongRunningSession: Bool {
        switch self {
        case .groupDelay, .proxyDelay, .proxyProviderHealthcheck, .proxyProviderProxyHealthcheck:
            true
        default:
            false
        }
    }

    private func proxyProviderPath(_ name: String) -> String {
        "\(Self.proxyProvidersPath)/\(name.urlPathSegmentEscaped)"
    }

    private func healthcheckQueryItems(url: String, timeout: Int) -> [URLQueryItem] {
        [
            URLQueryItem(name: "url", value: url),
            URLQueryItem(name: "timeout", value: "\(timeout)"),
        ]
    }

    private func optionalQueryItem(name: String, value: String?) -> [URLQueryItem] {
        guard let value, !value.isEmpty else { return [] }
        return [URLQueryItem(name: name, value: value)]
    }
}

public enum APIError: Error, LocalizedError, Sendable {
    case invalidURL
    case invalidResponse
    case statusCode(Int, String)
    case clientUnavailable

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Controller URL is invalid"
        case .invalidResponse:
            "Invalid API response"
        case let .statusCode(code, message):
            "API request failed (\(code)): \(message)"
        case .clientUnavailable:
            "API client is unavailable"
        }
    }
}

public final class MihomoAPIService: @unchecked Sendable {
    private let lock = NSLock()
    private let controlSession: URLSession
    private let longRunningSession: URLSession
    private let decoder = JSONDecoder()

    public private(set) var controller: String
    public private(set) var secret: String?

    public init(
        controller: String,
        secret: String?,
        session: URLSession? = nil,
        longRunningSession: URLSession? = nil)
    {
        self.controller = controller
        self.secret = secret

        if let session {
            self.controlSession = session
        } else {
            self.controlSession = Self.makeSession(
                timeoutIntervalForRequest: 2,
                timeoutIntervalForResource: 240,
                httpMaximumConnectionsPerHost: 6)
        }

        if let longRunningSession {
            self.longRunningSession = longRunningSession
        } else if let session {
            self.longRunningSession = session
        } else {
            self.longRunningSession = Self.makeSession(
                timeoutIntervalForRequest: 2,
                timeoutIntervalForResource: 240,
                httpMaximumConnectionsPerHost: 12)
        }
    }

    public func updateCredentials(controller: String, secret: String?) {
        self.lock.withLock {
            self.controller = controller
            self.secret = secret
        }
    }

    public func request<T: Decodable>(_ endpoint: Endpoint) async throws -> T {
        let data = try await send(endpoint)
        return try self.decoder.decode(T.self, from: data)
    }

    public func requestNoResponse(_ endpoint: Endpoint) async throws {
        _ = try await self.send(endpoint)
    }

    public func makeWebSocketTask(for endpoint: Endpoint) throws -> URLSessionWebSocketTask {
        let request = try buildWebSocketRequest(for: endpoint)
        return self.controlSession.webSocketTask(with: request)
    }

    private func send(_ endpoint: Endpoint) async throws -> Data {
        var lastError: Error?

        let maxAttempts = endpoint.method == .get ? 3 : 1
        let session = self.session(for: endpoint)

        for attempt in 0..<maxAttempts {
            do {
                let request = try buildRequest(for: endpoint)
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw APIError.invalidResponse
                }

                guard 200..<300 ~= http.statusCode else {
                    let message = String(data: data, encoding: .utf8) ?? "unknown error"
                    throw APIError.statusCode(http.statusCode, message)
                }
                return data
            } catch {
                lastError = error
                guard Self.shouldRetry(error: error), attempt < maxAttempts - 1 else {
                    throw error
                }
                try await Task.sleep(nanoseconds: 250_000_000)
            }
        }

        throw lastError ?? APIError.invalidResponse
    }

    private static func shouldRetry(error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .timedOut,
             .networkConnectionLost,
             .cannotConnectToHost,
             .notConnectedToInternet,
             .dnsLookupFailed,
             .cannotFindHost,
             .resourceUnavailable:
            return true
        default:
            return false
        }
    }

    private func session(for endpoint: Endpoint) -> URLSession {
        endpoint.usesLongRunningSession ? self.longRunningSession : self.controlSession
    }

    private static func makeSession(
        timeoutIntervalForRequest: TimeInterval,
        timeoutIntervalForResource: TimeInterval,
        httpMaximumConnectionsPerHost: Int) -> URLSession
    {
        URLSessionFactory.makeEphemeralSession(
            requestTimeout: timeoutIntervalForRequest,
            resourceTimeout: timeoutIntervalForResource,
            maxConnectionsPerHost: httpMaximumConnectionsPerHost)
    }

    private func buildRequest(for endpoint: Endpoint) throws -> URLRequest {
        let (controller, secret) = self.lock.withLock {
            (self.controller, self.secret)
        }
        let url = try endpointURL(for: endpoint, controller: controller, webSocket: false)
        var request = self.authorizedRequest(url: url, secret: secret)
        request.httpMethod = endpoint.method.rawValue
        request.httpBody = endpoint.body
        request.timeoutInterval = endpoint.timeoutInterval
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func buildWebSocketRequest(for endpoint: Endpoint) throws -> URLRequest {
        let (controller, secret) = self.lock.withLock {
            (self.controller, self.secret)
        }
        let url = try endpointURL(for: endpoint, controller: controller, webSocket: true)
        return self.authorizedRequest(url: url, secret: secret)
    }

    private func endpointURL(for endpoint: Endpoint, controller: String, webSocket: Bool) throws -> URL {
        guard var components = URLComponents(string: normalizedControllerAddress(controller, webSocket: webSocket))
        else {
            throw APIError.invalidURL
        }
        components.path = endpoint.path
        if !endpoint.queryItems.isEmpty {
            components.queryItems = endpoint.queryItems
        }
        guard let url = components.url else { throw APIError.invalidURL }
        return url
    }

    private func authorizedRequest(url: URL, secret: String?) -> URLRequest {
        var request = URLRequest(url: url)
        if let secret, !secret.isEmpty {
            request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func normalizedControllerAddress(_ controller: String, webSocket: Bool) -> String {
        let hasHTTPScheme = controller.hasPrefix("http://") || controller.hasPrefix("https://")

        if !webSocket {
            return hasHTTPScheme ? controller : "http://\(controller)"
        }

        if controller.hasPrefix("ws://") || controller.hasPrefix("wss://") {
            return controller
        }
        if hasHTTPScheme {
            return controller
                .replacingOccurrences(of: "https://", with: "wss://")
                .replacingOccurrences(of: "http://", with: "ws://")
        }
        return "ws://\(controller)"
    }
}

extension String {
    private static let urlPathSegmentAllowedCharacters: CharacterSet = {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return allowed
    }()

    public var urlPathSegmentEscaped: String {
        self.addingPercentEncoding(withAllowedCharacters: Self.urlPathSegmentAllowedCharacters) ?? self
    }
}
