import Foundation

public enum ProxyHelperConstants {
    public static let machServiceName = "com.clashbar.helper"
    public static let daemonPlistName = "com.clashbar.helper.plist"
    public static let helperBundleProgram = "Contents/Library/HelperTools/com.clashbar.helper"
    public static let allowedClientBundleIdentifier = "com.clashbar"
    public static let allowedClientRequirement = "identifier \"\(allowedClientBundleIdentifier)\""
}

@objc(ProxyHelperProtocol)
public protocol ProxyHelperProtocol {
    func setSystemProxy(
        host: String,
        httpPort: Int,
        httpsPort: Int,
        socksPort: Int,
        completion: @escaping (Bool, String?) -> Void)
    func clearSystemProxy(completion: @escaping (Bool, String?) -> Void)
    func getSystemProxyState(completion: @escaping (Bool, Bool, String?) -> Void)
    func isSystemProxyConfigured(
        host: String,
        httpPort: Int,
        httpsPort: Int,
        socksPort: Int,
        completion: @escaping (Bool, Bool, String?) -> Void)
}
