import Foundation

enum CoreLifecycleStatus: Equatable, Sendable {
    case stopped
    case starting
    case running(pid: Int32)
    case failed(reason: String)
}

protocol MihomoControlling: AnyObject, Sendable {
    var status: CoreLifecycleStatus { get }
    var isRunning: Bool { get }
    var detectedBinaryPath: String? { get }
    func validateConfig(configPath: String) throws
    func validateConfigAsync(configPath: String) async throws
    @discardableResult
    func start(configPath: String, controller: String) throws -> CoreLifecycleStatus
    @discardableResult
    func startAsync(configPath: String, controller: String) async throws -> CoreLifecycleStatus
    func stop()
    func stopAsync() async
    @discardableResult
    func restart(configPath: String, controller: String) throws -> CoreLifecycleStatus
    @discardableResult
    func restartAsync(configPath: String, controller: String) async throws -> CoreLifecycleStatus
}
