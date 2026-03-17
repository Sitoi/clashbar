import Foundation
import ProxyHelperShared
import ServiceManagement

enum SystemProxyServiceError: LocalizedError {
    case invalidHost
    case invalidPort
    case helperNotBundled
    case helperRequiresInstallToApplications
    case helperNeedsApproval
    case helperRegistrationFailed(String)
    case helperRecoveryFailed(String)
    case helperConnectionFailed(String)
    case helperOperationFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidHost:
            "Invalid proxy host."
        case .invalidPort:
            "Invalid proxy port."
        case .helperNotBundled:
            "Privileged helper not found in app bundle. Please rebuild and run the packaged app."
        case .helperRequiresInstallToApplications:
            "Privileged helper can only be installed from /Applications. " +
                "Move ClashBar.app to /Applications and reopen it."
        case .helperNeedsApproval:
            "Privileged helper requires approval in System Settings > Login Items."
        case let .helperRegistrationFailed(message):
            "Failed to register privileged helper: \(message)"
        case let .helperRecoveryFailed(message):
            "Failed to recover privileged helper: \(message)"
        case let .helperConnectionFailed(message):
            "Failed to connect privileged helper: \(message)"
        case let .helperOperationFailed(message):
            "Privileged helper operation failed: \(message)"
        }
    }
}

private final class ContinuationBox<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?

    init(_ continuation: CheckedContinuation<Value, Error>) {
        self.continuation = continuation
    }

    func resume(with result: Result<Value, Error>) {
        self.lock.lock()
        guard let continuation else {
            self.lock.unlock()
            return
        }
        self.continuation = nil
        self.lock.unlock()

        switch result {
        case let .success(value):
            continuation.resume(returning: value)
        case let .failure(error):
            continuation.resume(throwing: error)
        }
    }
}

struct SystemProxyService {
    private let helperRecoveryMaxAttempts = 3
    private let helperRecoveryDelayNanoseconds: UInt64 = 1_500_000_000
    private let helperResponseTimeoutNanoseconds: UInt64 = 4_000_000_000

    func applySystemProxy(enabled: Bool, host: String, ports: SystemProxyPorts) async throws {
        try self.validateHost(host)

        if enabled {
            let resolvedPorts = try validateAndResolvePorts(ports, requiresEnabledPort: true)
            try await invokeMutationWithRecovery { helper, completion in
                helper.clearSystemProxy(completion: completion)
            }
            try await invokeMutationWithRecovery { helper, completion in
                helper.setSystemProxy(
                    host: host,
                    httpPort: resolvedPorts.httpPort,
                    httpsPort: resolvedPorts.httpsPort,
                    socksPort: resolvedPorts.socksPort,
                    completion: completion)
            }
        } else {
            try await self.invokeMutationWithRecovery { helper, completion in
                helper.clearSystemProxy(completion: completion)
            }
        }
    }

    func isSystemProxyEnabled() async throws -> Bool {
        let daemonService = self.helperService()
        guard daemonService.status == .enabled else {
            return false
        }

        return try await self.invokeStateQueryWithRecovery()
    }

    func isSystemProxyConfigured(host: String, ports: SystemProxyPorts) async throws -> Bool {
        try self.validateHost(host)
        let resolvedPorts = try validateAndResolvePorts(ports, requiresEnabledPort: true)
        let daemonService = self.helperService()
        guard daemonService.status == .enabled else {
            return false
        }

        return try await self.invokeBooleanQueryWithRecovery { helper, completion in
            helper.isSystemProxyConfigured(
                host: host,
                httpPort: resolvedPorts.httpPort,
                httpsPort: resolvedPorts.httpsPort,
                socksPort: resolvedPorts.socksPort,
                completion: completion)
        }
    }

    private func validateHost(_ host: String) throws {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else {
            throw SystemProxyServiceError.invalidHost
        }
    }

    private func validateAndResolvePorts(
        _ ports: SystemProxyPorts,
        requiresEnabledPort: Bool) throws -> (httpPort: Int, httpsPort: Int, socksPort: Int)
    {
        let httpPort = try normalizePort(ports.httpPort)
        let httpsPort = try normalizePort(ports.httpsPort)
        let socksPort = try normalizePort(ports.socksPort)

        if requiresEnabledPort, httpPort == 0, httpsPort == 0, socksPort == 0 {
            throw SystemProxyServiceError.invalidPort
        }

        return (httpPort: httpPort, httpsPort: httpsPort, socksPort: socksPort)
    }

    private func normalizePort(_ value: Int?) throws -> Int {
        guard let value else { return 0 }
        guard (1...65535).contains(value) else {
            throw SystemProxyServiceError.invalidPort
        }
        return value
    }

    private func ensureHelperReadyForWrite() throws {
        guard self.isHelperBundledInMainApp() else {
            throw SystemProxyServiceError.helperNotBundled
        }
        guard !self.isRunningFromReadOnlyVolume() else {
            throw SystemProxyServiceError.helperRequiresInstallToApplications
        }

        let daemonService = self.helperService()
        do {
            try daemonService.register()
        } catch {
            if daemonService.status == .enabled {
                return
            }
            if daemonService.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
                throw SystemProxyServiceError.helperNeedsApproval
            }
            throw SystemProxyServiceError.helperRegistrationFailed(error.localizedDescription)
        }

        if daemonService.status == .enabled {
            return
        }

        if daemonService.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
            throw SystemProxyServiceError.helperNeedsApproval
        }

        throw SystemProxyServiceError
            .helperRegistrationFailed(
                "Service remains unavailable after register call. status=\(daemonService.status.rawValue)")
    }

    private func isHelperBundledInMainApp() -> Bool {
        let bundleURL = Bundle.main.bundleURL
        let fileManager = FileManager.default

        let plistURL = bundleURL
            .appendingPathComponent("Contents/Library/LaunchDaemons", isDirectory: true)
            .appendingPathComponent(ProxyHelperConstants.daemonPlistName, isDirectory: false)
        let helperURL = bundleURL
            .appendingPathComponent(ProxyHelperConstants.helperBundleProgram, isDirectory: false)

        return fileManager.fileExists(atPath: plistURL.path) && fileManager.fileExists(atPath: helperURL.path)
    }

    private func isRunningFromReadOnlyVolume() -> Bool {
        do {
            let values = try Bundle.main.bundleURL.resourceValues(forKeys: [.volumeIsReadOnlyKey])
            return values.volumeIsReadOnly == true
        } catch {
            return false
        }
    }

    private func helperService() -> SMAppService {
        SMAppService.daemon(plistName: ProxyHelperConstants.daemonPlistName)
    }

    private func invokeMutationWithRecovery(
        _ invoke: @escaping (ProxyHelperProtocol, @escaping (Bool, String?) -> Void) -> Void) async throws
    {
        var attempt = 0
        var lastError: Error?

        while attempt < self.helperRecoveryMaxAttempts {
            do {
                try self.ensureHelperReadyForWrite()
                try await self.invokeMutation(invoke)
                return
            } catch {
                lastError = error
                let shouldRetry = self.shouldRetryAfterRecovery(error)
                if !shouldRetry || attempt == self.helperRecoveryMaxAttempts - 1 {
                    throw error
                }
                try await self.recoverHelperForRetry(error: error)
                attempt += 1
            }
        }

        throw lastError ?? SystemProxyServiceError.helperOperationFailed("Unknown helper mutation failure.")
    }

    private func invokeStateQueryWithRecovery() async throws -> Bool {
        try await self.invokeBooleanQueryWithRecovery { helper, completion in
            helper.getSystemProxyState(completion: completion)
        }
    }

    private func invokeBooleanQueryWithRecovery(
        _ invoke: @escaping (ProxyHelperProtocol, @escaping (Bool, Bool, String?) -> Void) -> Void) async throws -> Bool
    {
        var attempt = 0
        var lastError: Error?

        while attempt < self.helperRecoveryMaxAttempts {
            do {
                return try await self.invokeBooleanQuery(invoke)
            } catch {
                lastError = error
                guard self.shouldRetryAfterRecovery(error) else { throw error }
                guard attempt < self.helperRecoveryMaxAttempts - 1 else { throw error }
                try? await Task.sleep(nanoseconds: self.helperRecoveryDelayNanoseconds)
                attempt += 1
            }
        }

        throw lastError ?? SystemProxyServiceError.helperOperationFailed("Unknown helper query failure.")
    }

    private func shouldRetryAfterRecovery(_ error: Error) -> Bool {
        guard let serviceError = error as? SystemProxyServiceError else {
            return false
        }

        switch serviceError {
        case .helperConnectionFailed, .helperOperationFailed, .helperRegistrationFailed:
            return true
        case .helperNeedsApproval, .helperNotBundled, .helperRequiresInstallToApplications, .invalidHost, .invalidPort,
             .helperRecoveryFailed:
            return false
        }
    }

    private func recoverHelperForRetry(error previousError: Error) async throws {
        let daemonService = self.helperService()
        do {
            try daemonService.register()
        } catch {
            switch daemonService.status {
            case .enabled:
                // Helper 已注册且已批准，register() 抛出 "already registered" 属于正常情况，
                // 此时 daemon 可能正由 launchd 启动中，等待即可
                break
            case .requiresApproval:
                SMAppService.openSystemSettingsLoginItems()
                throw SystemProxyServiceError.helperNeedsApproval
            default:
                throw SystemProxyServiceError.helperRecoveryFailed(
                    "\(previousError.localizedDescription) -> \(error.localizedDescription)")
            }
        }

        if daemonService.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
            throw SystemProxyServiceError.helperNeedsApproval
        }

        try? await Task.sleep(nanoseconds: self.helperRecoveryDelayNanoseconds)
    }

    private func invokeMutation(
        _ invoke: @escaping (ProxyHelperProtocol, @escaping (Bool, String?) -> Void) -> Void) async throws
    {
        try await self.invokeHelper { helper, completion in
            invoke(helper) { success, message in
                if success {
                    completion(.success(()))
                    return
                }
                completion(.failure(SystemProxyServiceError.helperOperationFailed(message ?? "Unknown helper error.")))
            }
        }
    }

    private func invokeBooleanQuery(
        _ invoke: @escaping (ProxyHelperProtocol, @escaping (Bool, Bool, String?) -> Void) -> Void) async throws -> Bool
    {
        try await self.invokeHelper { helper, completion in
            invoke(helper) { success, boolValue, message in
                if success {
                    completion(.success(boolValue))
                    return
                }
                completion(.failure(SystemProxyServiceError.helperOperationFailed(message ?? "Unknown helper error.")))
            }
        }
    }

    private func invokeHelper<Value: Sendable>(
        _ invoke: @escaping (ProxyHelperProtocol, @escaping (Result<Value, Error>) -> Void) -> Void) async throws
        -> Value
    {
        try await withCheckedThrowingContinuation { continuation in
            let connection = self.makeConnection()
            let box = ContinuationBox<Value>(continuation)
            let timeoutWorkItem = DispatchWorkItem {
                connection.invalidate()
                box.resume(
                    with: .failure(
                        SystemProxyServiceError.helperConnectionFailed("Helper response timed out.")))
            }
            let timeoutInterval = DispatchTimeInterval.nanoseconds(Int(self.helperResponseTimeoutNanoseconds))
            DispatchQueue.global(qos: .userInitiated).asyncAfter(
                deadline: .now() + timeoutInterval,
                execute: timeoutWorkItem)

            guard let helper = connection.remoteObjectProxyWithErrorHandler({ error in
                timeoutWorkItem.cancel()
                connection.invalidate()
                box.resume(with: .failure(SystemProxyServiceError.helperConnectionFailed(error.localizedDescription)))
            }) as? ProxyHelperProtocol else {
                timeoutWorkItem.cancel()
                connection.invalidate()
                box
                    .resume(with: .failure(SystemProxyServiceError
                            .helperConnectionFailed("Unable to create XPC proxy.")))
                return
            }

            invoke(helper) { result in
                timeoutWorkItem.cancel()
                defer { connection.invalidate() }
                box.resume(with: result)
            }
        }
    }

    func clearSystemProxyBlocking(timeout: TimeInterval = 2.0) {
        let semaphore = DispatchSemaphore(value: 0)

        DispatchQueue.global(qos: .userInitiated).async {
            let connection = NSXPCConnection(
                machServiceName: ProxyHelperConstants.machServiceName,
                options: .privileged)
            connection.remoteObjectInterface = NSXPCInterface(with: ProxyHelperProtocol.self)
            connection.activate()

            guard let helper = connection.remoteObjectProxyWithErrorHandler({ _ in
                semaphore.signal()
            }) as? ProxyHelperProtocol else {
                connection.invalidate()
                semaphore.signal()
                return
            }

            helper.clearSystemProxy { _, _ in
                connection.invalidate()
                semaphore.signal()
            }
        }

        _ = semaphore.wait(timeout: .now() + timeout)
    }

    private func makeConnection() -> NSXPCConnection {
        let connection = NSXPCConnection(
            machServiceName: ProxyHelperConstants.machServiceName,
            options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: ProxyHelperProtocol.self)
        connection.activate()
        return connection
    }
}
