import Foundation

public enum ProxyHelperConstants {
    public static let machServiceName = "com.clashbar.helper"
    public static let daemonPlistName = "com.clashbar.helper.plist"
    public static let helperBundleProgram = "Contents/Library/HelperTools/com.clashbar.helper"
    public static let allowedClientBundleIdentifier = "com.clashbar"
    public static let allowedClientRequirement = "identifier \"\(allowedClientBundleIdentifier)\""
    public static let currentVersion = "1.0.1"
}

@objc(ProxyHelperProtocol)
public protocol ProxyHelperProtocol {
    func getVersion(completion: @escaping (String) -> Void)
    func ping(completion: @escaping (Bool, String?) -> Void)
    func setSystemProxy(
        host: String,
        httpPort: Int,
        httpsPort: Int,
        socksPort: Int,
        completion: @escaping (Bool, String?) -> Void)
    func clearSystemProxy(completion: @escaping (Bool, String?) -> Void)
    func getSystemProxyState(completion: @escaping (Bool, Bool, String?) -> Void)
    func getSystemProxyActiveTarget(completion: @escaping (Bool, String?, Int, String?) -> Void)
    func isSystemProxyConfigured(
        host: String,
        httpPort: Int,
        httpsPort: Int,
        socksPort: Int,
        completion: @escaping (Bool, Bool, String?) -> Void)
    func getSystemProxyExceptions(completion: @escaping (Bool, String?, String?) -> Void)
    func setSystemProxyExceptions(serializedExceptions: String, completion: @escaping (Bool, String?) -> Void)
}
