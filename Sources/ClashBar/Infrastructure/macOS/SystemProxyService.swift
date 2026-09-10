import Foundation
import os
import ProxyHelperShared
import Security
import ServiceManagement

enum SystemProxyHelperRegistrationState: Equatable, Sendable {
    case enabled
    case requiresApproval
    case notRegistered
    case unavailable
}

enum SystemProxyHelperFailureReason: String, Equatable, Sendable {
    case backgroundActivityDisabled
    case helperNotRegistered
    case helperStartTimedOut
    case helperConnectionFailed
    case helperOperationFailed
    case appNotInApplications
    case helperNotBundled
    case signatureMismatch
    case unknown
}

struct SystemProxyHelperHealthSnapshot: Equatable, Sendable {
    let registrationState: SystemProxyHelperRegistrationState
    let backgroundActivityAllowed: Bool
    let processRunning: Bool
    let failureReason: SystemProxyHelperFailureReason?
    let rawMessage: String?
}

enum SystemProxyServiceError: LocalizedError {
    case invalidHost
    case invalidPort
    case helperNotBundled
    case helperRequiresInstallToApplications
    case helperNeedsApproval
    case helperNotRegistered(String?)
    case helperStartTimedOut
    case helperInvalidSignature(String)
    case helperConnectionFailed(String)
    case helperOperationFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidHost:
            return "Invalid proxy host."
        case .invalidPort:
            return "Invalid proxy port."
        case .helperNotBundled:
            return "Privileged helper not found in app bundle. Please rebuild and run the packaged app."
        case .helperRequiresInstallToApplications:
            return "Privileged helper can only be installed from /Applications. " +
                "Move ClashBar.app to /Applications and reopen it."
        case .helperNeedsApproval:
            return "Privileged helper requires approval in System Settings > Login Items."
        case let .helperNotRegistered(message):
            if let message, !message.isEmpty {
                return "Privileged helper is not registered: \(message)"
            }
            return "Privileged helper is not registered."
        case .helperStartTimedOut:
            return "Privileged helper did not start in time."
        case let .helperInvalidSignature(message):
            return "Privileged helper signature invalid: \(message)"
        case let .helperConnectionFailed(message):
            return "Failed to connect privileged helper: \(message)"
        case let .helperOperationFailed(message):
            return "Privileged helper operation failed: \(message)"
        }
    }
}

struct SystemProxyService {
    private let helperResponseTimeoutNanoseconds: UInt64 = 4_000_000_000
    private let helperLaunchRetryDelayNanoseconds: UInt64 = 250_000_000
    private let helperLaunchRetryAttempts = 4

    private static let systemSettingsOpenGate = SystemSettingsOpenGate()

    private final class SystemSettingsOpenGate: Sendable {
        private let state = OSAllocatedUnfairLock(initialState: Date.distantPast)

        func openIfNeeded(minimumInterval: TimeInterval) {
            let shouldOpen = self.state.withLock { lastOpened in
                let now = Date()
                guard now.timeIntervalSince(lastOpened) >= minimumInterval else {
                    return false
                }
                lastOpened = now
                return true
            }

            if shouldOpen {
                SMAppService.openSystemSettingsLoginItems()
            }
        }
    }

    private enum HelperRegistrationResult {
        case ready
        case needsApproval
        case failed(String?)
    }

    func warmUpHelperIfPossible() async {
        guard self.isHelperBundledInMainApp() else { return }
        guard self.isRunningFromApplicationsDirectory() else { return }
        do {
            try self.validateHelperSigningRequirements()
        } catch {
            return
        }

        switch self.attemptHelperRegistration() {
        case .ready:
            _ = try? await self.triggerHelperDemandLaunchAndWait()
            try? await self.ensureHelperVersionCompatible()
        case .needsApproval, .failed:
            return
        }
    }

    func apply(enabled: Bool, host: String, ports: SystemProxyPorts) async throws {
        try self.validateHost(host)
        try await self.ensureHelperReadyForUse()

        if enabled {
            let resolvedPorts = try self.validateAndResolvePorts(ports, requiresEnabledPort: true)
            try await self.invokeMutation { helper, completion in
                helper.setSystemProxy(
                    host: host,
                    httpPort: resolvedPorts.httpPort,
                    httpsPort: resolvedPorts.httpsPort,
                    socksPort: resolvedPorts.socksPort,
                    completion: completion)
            }
        } else {
            try await self.invokeMutation { helper, completion in
                helper.clearSystemProxy(completion: completion)
            }
        }
    }

    func isEnabled() async throws -> Bool {
        try await self.ensureHelperReadyForUse()
        return try await self.invokeStateQuery()
    }

    func readActiveDisplay() async throws -> String? {
        try await self.ensureHelperReadyForUse()
        guard let target = try await self.invokeActiveTargetQuery() else {
            return nil
        }
        return self.formatProxyDisplay(host: target.host, port: target.port)
    }

    func readExceptionsList() async throws -> [String] {
        try await self.ensureHelperReadyForUse()
        return try await self.invokeExceptionsQuery()
    }

    func setExceptionsList(_ exceptions: [String]) async throws {
        try await self.ensureHelperReadyForUse()
        let serialized = self.serializeExceptions(exceptions)
        try await self.invokeMutation { helper, completion in
            helper.setSystemProxyExceptions(serializedExceptions: serialized, completion: completion)
        }
    }

    func readHelperHealthSnapshot() async -> SystemProxyHelperHealthSnapshot {
        let registrationState = self.registrationState(from: self.helperService().status)
        let backgroundActivityAllowed = registrationState != .requiresApproval

        do {
            let processRunning = try self.isHelperProcessRunning()
            try self.validateHelperEnvironment()

            switch registrationState {
            case .enabled:
                return SystemProxyHelperHealthSnapshot(
                    registrationState: registrationState,
                    backgroundActivityAllowed: backgroundActivityAllowed,
                    processRunning: processRunning,
                    failureReason: nil,
                    rawMessage: nil)
            case .requiresApproval:
                let error = SystemProxyServiceError.helperNeedsApproval
                return self.failedHealthSnapshot(
                    registrationState: registrationState,
                    backgroundActivityAllowed: backgroundActivityAllowed,
                    processRunning: processRunning,
                    error: error)
            case .notRegistered, .unavailable:
                let error = SystemProxyServiceError.helperNotRegistered(nil)
                return self.failedHealthSnapshot(
                    registrationState: registrationState,
                    backgroundActivityAllowed: backgroundActivityAllowed,
                    processRunning: processRunning,
                    error: error)
            }
        } catch {
            return self.failedHealthSnapshot(
                registrationState: registrationState,
                backgroundActivityAllowed: backgroundActivityAllowed,
                processRunning: false,
                error: error)
        }
    }

    func isConfigured(host: String, ports: SystemProxyPorts) async throws -> Bool {
        try self.validateHost(host)
        let resolvedPorts = try self.validateAndResolvePorts(ports, requiresEnabledPort: true)
        try await self.ensureHelperReadyForUse()
        return try await self.invokeBooleanQuery { helper, completion in
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
        let httpPort = try self.normalizePort(ports.httpPort)
        let httpsPort = try self.normalizePort(ports.httpsPort)
        let socksPort = try self.normalizePort(ports.socksPort)

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

    private func validateHelperEnvironment() throws {
        guard self.isHelperBundledInMainApp() else {
            throw SystemProxyServiceError.helperNotBundled
        }
        guard self.isRunningFromApplicationsDirectory() else {
            throw SystemProxyServiceError.helperRequiresInstallToApplications
        }
        try self.validateHelperSigningRequirements()
    }

    private func ensureHelperReadyForUse() async throws {
        try self.validateHelperEnvironment()
        try self.ensureHelperRegistered()
        try await self.ensureHelperProcessResponsive()
        try await self.ensureHelperVersionCompatible()
    }

    private func ensureHelperVersionCompatible() async throws {
        do {
            let version = try await self.invokeVersionQuery()
            let targetVersion = ProxyHelperConstants.currentVersion
            if self.isVersion(version, lowerThan: targetVersion) || version != targetVersion {
                try await self.reregisterHelper()
                _ = try await self.triggerHelperDemandLaunchAndWait()
            }
        } catch {
            try await self.reregisterHelper()
            _ = try await self.triggerHelperDemandLaunchAndWait()
        }
    }

    private func isVersion(_ v1: String, lowerThan v2: String) -> Bool {
        let parts1 = v1.split(separator: ".").compactMap { Int($0) }
        let parts2 = v2.split(separator: ".").compactMap { Int($0) }
        let maxCount = max(parts1.count, parts2.count)
        for i in 0..<maxCount {
            let p1 = i < parts1.count ? parts1[i] : 0
            let p2 = i < parts2.count ? parts2[i] : 0
            if p1 < p2 {
                return true
            }
            if p1 > p2 {
                return false
            }
        }
        return false
    }

    private func invokeVersionQuery() async throws -> String {
        try await self.invokeHelperOnce { helper, completion in
            helper.getVersion { version in
                completion(.success(version))
            }
        }
    }

    private func ensureHelperRegistered() throws {
        if self.helperService().status == .enabled {
            return
        }

        switch self.attemptHelperRegistration() {
        case .ready:
            return
        case .needsApproval:
            self.openSystemSettingsLoginItemsIfNeeded()
            throw SystemProxyServiceError.helperNeedsApproval
        case let .failed(message):
            let status = self.helperService().status
            throw SystemProxyServiceError.helperNotRegistered(message ?? "status=\(status.rawValue)")
        }
    }

    private func ensureHelperProcessResponsive() async throws {
        if try self.isHelperProcessRunning() {
            return
        }

        if try await self.triggerHelperDemandLaunchAndWait() {
            return
        }

        try await self.reregisterHelper()

        if try await self.triggerHelperDemandLaunchAndWait() {
            return
        }

        throw SystemProxyServiceError.helperStartTimedOut
    }

    private func registrationState(from status: SMAppService.Status) -> SystemProxyHelperRegistrationState {
        switch status {
        case .enabled:
            .enabled
        case .requiresApproval:
            .requiresApproval
        case .notRegistered:
            .notRegistered
        case .notFound:
            .unavailable
        @unknown default:
            .unavailable
        }
    }

    private func failedHealthSnapshot(
        registrationState: SystemProxyHelperRegistrationState,
        backgroundActivityAllowed: Bool,
        processRunning: Bool,
        error: Error) -> SystemProxyHelperHealthSnapshot
    {
        SystemProxyHelperHealthSnapshot(
            registrationState: registrationState,
            backgroundActivityAllowed: backgroundActivityAllowed,
            processRunning: processRunning,
            failureReason: self.helperFailureReason(for: error),
            rawMessage: self.helperFailureMessage(error))
    }

    private func helperFailureReason(for error: Error) -> SystemProxyHelperFailureReason {
        guard let serviceError = error as? SystemProxyServiceError else {
            return .unknown
        }

        switch serviceError {
        case .helperNotBundled:
            return .helperNotBundled
        case .helperRequiresInstallToApplications:
            return .appNotInApplications
        case .helperNeedsApproval:
            return .backgroundActivityDisabled
        case .helperNotRegistered:
            return .helperNotRegistered
        case .helperStartTimedOut:
            return .helperStartTimedOut
        case .helperInvalidSignature:
            return .signatureMismatch
        case .helperConnectionFailed:
            return .helperConnectionFailed
        case .helperOperationFailed:
            return .helperOperationFailed
        case .invalidHost, .invalidPort:
            return .unknown
        }
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

    private func isRunningFromApplicationsDirectory() -> Bool {
        let bundlePath = Bundle.main.bundleURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
        return bundlePath.hasPrefix("/Applications/") && bundlePath.hasSuffix(".app")
    }

    private func attemptHelperRegistration() -> HelperRegistrationResult {
        let daemonService = self.helperService()
        if daemonService.status == .enabled {
            return .ready
        }

        do {
            try daemonService.register()
        } catch {
            if daemonService.status == .enabled {
                return .ready
            }
            if daemonService.status == .requiresApproval || self.isLikelyApprovalError(error) {
                return .needsApproval
            }
            return .failed(error.localizedDescription)
        }

        switch daemonService.status {
        case .enabled:
            return .ready
        case .requiresApproval:
            return .needsApproval
        case .notRegistered, .notFound:
            return .failed("status=\(daemonService.status.rawValue)")
        @unknown default:
            return .failed("status=\(daemonService.status.rawValue)")
        }
    }

    private func isLikelyApprovalError(_ error: Error) -> Bool {
        let normalized = error.localizedDescription.lowercased()
        return normalized.contains("operation not permitted")
            || normalized.contains("disallowed")
            || normalized.contains("denied")
            || normalized.contains("launch constraint")
            || normalized.contains("background item")
            || normalized.contains("approval")
    }

    private func reregisterHelper() async throws {
        let daemonService = self.helperService()
        try? await daemonService.unregister()
        try self.ensureHelperRegistered()
    }

    private func triggerHelperDemandLaunchAndWait() async throws -> Bool {
        do {
            try await self.invokeHelperPing()
        } catch {
            guard self.isHelperConnectionFailure(error) else {
                throw error
            }
        }

        for attempt in 0..<self.helperLaunchRetryAttempts {
            if try self.isHelperProcessRunning() {
                return true
            }
            if attempt < self.helperLaunchRetryAttempts - 1 {
                try await Task.sleep(nanoseconds: self.helperLaunchRetryDelayNanoseconds)
            }
        }

        return false
    }

    private func invokeHelperPing() async throws {
        try await self.invokeHelperOnce { helper, completion in
            helper.ping { success, message in
                completion(Self.mapHelperResult(success: success, message: message, value: ()))
            }
        }
    }

    private static func mapHelperResult<Value>(
        success: Bool,
        message: String?,
        value: @autoclosure () -> Value) -> Result<Value, Error>
    {
        if success {
            return .success(value())
        }
        return .failure(SystemProxyServiceError.helperOperationFailed(message ?? "Unknown helper error."))
    }

    private func helperService() -> SMAppService {
        SMAppService.daemon(plistName: ProxyHelperConstants.daemonPlistName)
    }

    private func openSystemSettingsLoginItemsIfNeeded() {
        Self.systemSettingsOpenGate.openIfNeeded(minimumInterval: 60)
    }

    private func isHelperProcessRunning() throws -> Bool {
        let result = try self.runProcessSynchronously(
            executable: "/usr/bin/pgrep",
            arguments: ["-x", ProxyHelperConstants.machServiceName])
        switch result.exitCode {
        case 0:
            return true
        case 1:
            return false
        default:
            throw SystemProxyServiceError.helperOperationFailed(result.combinedOutput)
        }
    }

    private func validateHelperSigningRequirements() throws {
        let appURL = Bundle.main.bundleURL
        let helperURL = appURL.appendingPathComponent(ProxyHelperConstants.helperBundleProgram, isDirectory: false)

        let appTeam = self.signingTeamIdentifier(at: appURL)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let helperTeam = self.signingTeamIdentifier(at: helperURL)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let appHasTeam = !appTeam.isEmpty
        let helperHasTeam = !helperTeam.isEmpty

        if !appHasTeam, !helperHasTeam {
            return
        }

        guard appHasTeam == helperHasTeam else {
            throw SystemProxyServiceError.helperInvalidSignature(
                "App/helper signing mode mismatch (one has TeamIdentifier, the other does not).")
        }

        guard appTeam == helperTeam else {
            throw SystemProxyServiceError.helperInvalidSignature(
                "App and helper TeamIdentifier mismatch (\(appTeam) != \(helperTeam)).")
        }
    }

    private func signingTeamIdentifier(at url: URL) -> String? {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, SecCSFlags(), &staticCode) == errSecSuccess,
              let staticCode
        else { return nil }

        var info: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &info) == errSecSuccess,
            let dict = info as? [String: Any]
        else { return nil }

        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }

    private func invokeStateQuery() async throws -> Bool {
        try await self.invokeBooleanQuery { helper, completion in
            helper.getSystemProxyState(completion: completion)
        }
    }

    private func invokeMutation(
        _ invoke: @escaping (ProxyHelperProtocol, @escaping (Bool, String?) -> Void) -> Void) async throws
    {
        try await self.invokeHelper { helper, completion in
            invoke(helper) { success, message in
                completion(Self.mapHelperResult(success: success, message: message, value: ()))
            }
        }
    }

    private func invokeBooleanQuery(
        _ invoke: @escaping (ProxyHelperProtocol, @escaping (Bool, Bool, String?) -> Void) -> Void) async throws
        -> Bool
    {
        try await self.invokeHelper { helper, completion in
            invoke(helper) { success, boolValue, message in
                completion(Self.mapHelperResult(success: success, message: message, value: boolValue))
            }
        }
    }

    private func invokeActiveTargetQuery() async throws -> (host: String, port: Int)? {
        try await self.invokeHelper { helper, completion in
            helper.getSystemProxyActiveTarget { success, host, port, message in
                let target: (host: String, port: Int)? = if let host,
                                                            !host.trimmingCharacters(in: .whitespacesAndNewlines)
                                                                .isEmpty, port > 0
                {
                    (host: host, port: port)
                } else {
                    nil
                }
                completion(Self.mapHelperResult(success: success, message: message, value: target))
            }
        }
    }

    private func invokeExceptionsQuery() async throws -> [String] {
        try await self.invokeHelper { helper, completion in
            helper.getSystemProxyExceptions { success, serialized, message in
                completion(Self.mapHelperResult(
                    success: success,
                    message: message,
                    value: self.deserializeExceptions(serialized)))
            }
        }
    }

    private func formatProxyDisplay(host: String, port: Int) -> String {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedHost.contains(":"), !trimmedHost.hasPrefix("[") {
            return "[\(trimmedHost)]:\(port)"
        }
        return "\(trimmedHost):\(port)"
    }

    private func serializeExceptions(_ exceptions: [String]) -> String {
        exceptions.joined(separator: "\n")
    }

    private func deserializeExceptions(_ serialized: String?) -> [String] {
        guard let serialized else { return [] }

        var result: [String] = []
        var seen: Set<String> = []

        for value in serialized.components(separatedBy: .newlines) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { continue }
            result.append(trimmed)
        }

        return result
    }

    private func helperFailureMessage(_ error: Error) -> String {
        if let serviceError = error as? SystemProxyServiceError {
            return serviceError.localizedDescription
        }
        return error.localizedDescription
    }

    private func isHelperConnectionFailure(_ error: Error) -> Bool {
        if let serviceError = error as? SystemProxyServiceError,
           case .helperConnectionFailed = serviceError
        {
            return true
        }
        return false
    }

    private struct ProcessResult {
        let exitCode: Int32
        let stdout: String
        let stderr: String

        var combinedOutput: String {
            [self.stderr, self.stdout]
                .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown command error."
        }
    }

    private func runProcessSynchronously(executable: String, arguments: [String]) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw SystemProxyServiceError.helperOperationFailed(error.localizedDescription)
        }

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return ProcessResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
    }

    private func invokeHelper<Value: Sendable>(
        _ invoke: @escaping (ProxyHelperProtocol, @escaping (Result<Value, Error>) -> Void) -> Void) async throws
        -> Value
    {
        do {
            return try await self.invokeHelperOnce(invoke)
        } catch {
            guard self.isHelperConnectionFailure(error) else {
                throw error
            }
            try self.ensureHelperRegistered()
            try await self.ensureHelperProcessResponsive()
            return try await self.invokeHelperOnce(invoke)
        }
    }

    private func invokeHelperOnce<Value: Sendable>(
        _ invoke: @escaping (ProxyHelperProtocol, @escaping (Result<Value, Error>) -> Void) -> Void) async throws
        -> Value
    {
        try await withCheckedThrowingContinuation { continuation in
            let connection = self.makeConnection()
            let box = OSAllocatedUnfairLock(initialState: Optional(continuation))
            let resume: @Sendable (Result<Value, Error>) -> Void = { result in
                let cont = box.withLock { c -> CheckedContinuation<Value, Error>? in
                    let current = c
                    c = nil
                    return current
                }
                cont?.resume(with: result)
            }
            let timeoutWorkItem = DispatchWorkItem {
                connection.invalidate()
                resume(.failure(SystemProxyServiceError.helperConnectionFailed("Helper response timed out.")))
            }
            let timeoutInterval = DispatchTimeInterval.nanoseconds(Int(self.helperResponseTimeoutNanoseconds))
            DispatchQueue.global(qos: .userInitiated).asyncAfter(
                deadline: .now() + timeoutInterval,
                execute: timeoutWorkItem)

            guard let helper = connection.remoteObjectProxyWithErrorHandler({ error in
                timeoutWorkItem.cancel()
                connection.invalidate()
                resume(.failure(SystemProxyServiceError.helperConnectionFailed(error.localizedDescription)))
            }) as? ProxyHelperProtocol else {
                timeoutWorkItem.cancel()
                connection.invalidate()
                resume(.failure(SystemProxyServiceError.helperConnectionFailed("Unable to create XPC proxy.")))
                return
            }

            invoke(helper) { result in
                timeoutWorkItem.cancel()
                defer { connection.invalidate() }
                resume(result)
            }
        }
    }

    func clearBlocking(timeout: TimeInterval = 2.0) {
        let semaphore = DispatchSemaphore(value: 0)

        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let connection = self.makeConnection()

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
