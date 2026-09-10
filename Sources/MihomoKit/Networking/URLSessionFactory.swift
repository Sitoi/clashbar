import Foundation

public enum URLSessionFactory {
    public static func makeEphemeralSession(
        requestTimeout: TimeInterval = 15,
        resourceTimeout: TimeInterval = 30,
        maxConnectionsPerHost: Int? = nil,
        waitsForConnectivity: Bool = false,
        cachePolicy: URLRequest.CachePolicy = .reloadIgnoringLocalCacheData) -> URLSession
    {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = requestTimeout
        config.timeoutIntervalForResource = resourceTimeout
        config.waitsForConnectivity = waitsForConnectivity
        config.requestCachePolicy = cachePolicy
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        if let maxConnectionsPerHost {
            config.httpMaximumConnectionsPerHost = maxConnectionsPerHost
        }
        return URLSession(configuration: config)
    }
}
