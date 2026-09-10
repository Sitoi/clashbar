import Darwin
import Foundation

public enum CoreLifecycleStatus: Equatable, Sendable {
    case stopped
    case starting
    case running(pid: Int32)
    case failed(reason: String)
}

public enum MihomoBinaryResolutionError: LocalizedError, Sendable {
    case binaryNotFound(expectedDirectory: String)

    public var errorDescription: String? {
        switch self {
        case let .binaryNotFound(expectedDirectory):
            "mihomo binary not found. Expected an executable named 'mihomo' in \(expectedDirectory)."
        }
    }
}

public enum MihomoConfigValidationError: LocalizedError, Sendable {
    case launchFailed(String)
    case timedOut(seconds: Int, details: String)
    case failed(exitCode: Int32, details: String)

    public var errorDescription: String? {
        switch self {
        case let .launchFailed(message):
            return message
        case let .timedOut(seconds, details):
            let normalizedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
            if normalizedDetails.isEmpty {
                return "mihomo -t timed out after \(seconds) seconds."
            }
            return "mihomo -t timed out after \(seconds) seconds.\n\(normalizedDetails)"
        case let .failed(exitCode, details):
            let normalizedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
            if normalizedDetails.isEmpty {
                return "mihomo -t exited with code \(exitCode)."
            }
            return normalizedDetails
        }
    }
}

public struct MihomoProcessConfiguration: Sendable {
    public var coreDirectoryURL: URL
    public var managedBinaryURL: URL
    public var candidateBinaryRoots: [URL]
    public var bootstrapDirectories: (@Sendable (FileManager) throws -> Void)?

    public init(
        coreDirectoryURL: URL,
        managedBinaryURL: URL? = nil,
        candidateBinaryRoots: [URL] = [],
        bootstrapDirectories: (@Sendable (FileManager) throws -> Void)? = nil)
    {
        self.coreDirectoryURL = coreDirectoryURL
        self.managedBinaryURL = managedBinaryURL
            ?? coreDirectoryURL.appendingPathComponent("mihomo", isDirectory: false)
        self.candidateBinaryRoots = candidateBinaryRoots
        self.bootstrapDirectories = bootstrapDirectories
    }
}

/// Caps how much core output reaches the app so a spinning mihomo (dead TUN fd
/// re-logging `batch read packet: ...` at ~160k lines/s) cannot pile up unbounded
/// main-actor tasks and file writes. Collapses consecutive duplicates, caps the
/// line rate per window, and reports how many lines it dropped.
/// Unlocked like `LineAccumulator`: one instance per pipe, and `readabilityHandler`
/// is already serial per handle.
private final class LogFloodGate: @unchecked Sendable {
    private let maxLinesPerWindow = 200
    private let windowNanoseconds: UInt64 = 1_000_000_000
    private var windowStart: UInt64 = 0
    private var emitted = 0
    private var dropped = 0
    private var lastLine: String?

    func accept(_ lines: [String], now: UInt64 = DispatchTime.now().uptimeNanoseconds) -> [String] {
        var accepted: [String] = []
        for line in lines {
            if now &- self.windowStart >= self.windowNanoseconds {
                if self.dropped > 0 {
                    accepted.append("[mihomo log] dropped \(self.dropped) flooding lines")
                }
                self.windowStart = now
                self.emitted = 0
                self.dropped = 0
                self.lastLine = nil
            }
            guard line != self.lastLine, self.emitted < self.maxLinesPerWindow else {
                self.dropped += 1
                continue
            }
            self.lastLine = line
            self.emitted += 1
            accepted.append(line)
        }
        return accepted
    }
}

private final class LineAccumulator: @unchecked Sendable {
    private var carry = Data()

    func append(_ data: Data) -> [String] {
        self.carry.append(data)
        var lines: [String] = []
        while let newlineIndex = self.carry.firstIndex(of: 0x0A) {
            let lineData = self.carry.subdata(in: self.carry.startIndex..<newlineIndex)
            self.carry.removeSubrange(self.carry.startIndex...newlineIndex)
            if let line = Self.normalize(lineData) {
                lines.append(line)
            }
        }
        return lines
    }

    func flushRemaining() -> String? {
        guard !self.carry.isEmpty else { return nil }
        let tail = self.carry
        self.carry = Data()
        return Self.normalize(tail)
    }

    private static func normalize(_ data: Data) -> String? {
        guard let raw = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

public final class MihomoProcessManager: @unchecked Sendable {
    public private(set) var status: CoreLifecycleStatus = .stopped
    private var process: Process?
    private var stdoutHandle: FileHandle?
    private var stderrHandle: FileHandle?
    private var intentionalStop = false
    private let lock = NSLock()
    private let fileManager: FileManager
    public var configuration: MihomoProcessConfiguration
    private let lifecycleQueue: DispatchQueue
    private let validationQueue: DispatchQueue
    private let configValidationTimeout: TimeInterval

    public var onLog: ((String) -> Void)?
    public var onTermination: ((Int32) -> Void)?

    public var detectedBinaryPath: String? {
        try? self.resolveMihomoBinary()
    }

    public var isRunning: Bool {
        self.lock.withLock {
            self.process?.isRunning == true
        }
    }

    public init(
        configuration: MihomoProcessConfiguration,
        fileManager: FileManager = .default,
        configValidationTimeout: TimeInterval = 10,
        lifecycleQueue: DispatchQueue? = nil,
        validationQueue: DispatchQueue? = nil)
    {
        self.configuration = configuration
        self.fileManager = fileManager
        self.configValidationTimeout = configValidationTimeout
        self.lifecycleQueue = lifecycleQueue
            ?? DispatchQueue(label: "com.clashbar.mihomo-process.operations", qos: .userInitiated)
        self.validationQueue = validationQueue
            ?? DispatchQueue(label: "com.clashbar.mihomo-process.validation", qos: .userInitiated)
    }

    deinit {
        stop()
    }

    public func validateConfig(configPath: String) throws {
        let binary = try resolveMihomoBinary()

        let workingDirectoryURL = Self.resolveWorkingDirectoryURL(configPath: configPath)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binary)
        proc.currentDirectoryURL = workingDirectoryURL
        proc.arguments = ["-d", workingDirectoryURL.path, "-f", configPath, "-t"]

        let outputPipe = Pipe()
        proc.standardOutput = outputPipe
        proc.standardError = outputPipe
        nonisolated(unsafe) var outputData = Data()
        let outputDrainGroup = DispatchGroup()
        outputDrainGroup.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            outputDrainGroup.leave()
        }

        do {
            try proc.run()
        } catch {
            throw MihomoConfigValidationError.launchFailed("Failed to run mihomo -t: \(error.localizedDescription)")
        }

        let didExit = self.waitForProcessExit(proc, timeout: self.configValidationTimeout)
        if !didExit {
            self.onLog?("[mihomo config test] timeout after \(self.normalizedValidationTimeoutSeconds())s")
            proc.terminate()
            if !self.waitForProcessExit(proc, timeout: 1.0) {
                _ = Darwin.kill(proc.processIdentifier, SIGKILL)
                _ = self.waitForProcessExit(proc, timeout: 0.5)
            }
        }

        _ = outputDrainGroup.wait(timeout: .now() + 1.0)
        let outputText = String(data: outputData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard didExit else {
            throw MihomoConfigValidationError.timedOut(
                seconds: self.normalizedValidationTimeoutSeconds(),
                details: outputText)
        }

        guard proc.terminationStatus == 0 else {
            throw MihomoConfigValidationError.failed(exitCode: proc.terminationStatus, details: outputText)
        }

        if !outputText.isEmpty {
            self.onLog?("[mihomo config test] \(outputText)")
        }
    }

    public func validateConfigAsync(configPath: String) async throws {
        try await self.runBlockingOperation(on: self.validationQueue) {
            try self.validateConfig(configPath: configPath)
        }
    }

    @discardableResult
    public func start(configPath: String, controller: String) throws -> CoreLifecycleStatus {
        if let runningPid = lock.withLock({ process?.isRunning == true ? process?.processIdentifier : nil }) {
            return .running(pid: runningPid)
        }

        self.lock.withLock {
            self.intentionalStop = false
            self.status = .starting
        }

        let binary = try resolveMihomoBinary()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binary)

        let workingDirectoryURL = Self.resolveWorkingDirectoryURL(configPath: configPath)
        proc.currentDirectoryURL = workingDirectoryURL

        let args = ["-d", workingDirectoryURL.path, "-f", configPath, "-ext-ctl", controller]
        proc.arguments = args

        let stdout = Pipe()
        let stderr = Pipe()
        proc.standardOutput = stdout
        proc.standardError = stderr
        self.stdoutHandle = stdout.fileHandleForReading
        self.stderrHandle = stderr.fileHandleForReading

        self.wireLogPipe(stdout.fileHandleForReading)
        self.wireLogPipe(stderr.fileHandleForReading)

        proc.terminationHandler = { [weak self] terminatedProcess in
            guard let self else { return }
            let code = terminatedProcess.terminationStatus
            self.handleProcessTermination(terminatedProcess, code: code)
        }

        do {
            try proc.run()
            self.lock.withLock {
                self.process = proc
                self.status = .running(pid: proc.processIdentifier)
            }
            let startMessage =
                "[mihomo started] pid=\(proc.processIdentifier) " +
                "controller=\(controller) " +
                "binary=\(binary) " +
                "workdir=\(workingDirectoryURL.path)"
            self.onLog?(startMessage)
            return self.status
        } catch {
            let reason = "Failed to launch mihomo: \(error.localizedDescription)"
            self.lock.withLock {
                self.status = .failed(reason: reason)
                self.intentionalStop = false
                self.releasePipeHandlesLocked()
            }
            self.onLog?("[mihomo error] \(reason)")
            throw error
        }
    }

    @discardableResult
    public func startAsync(configPath: String, controller: String) async throws -> CoreLifecycleStatus {
        try await self.runBlockingOperation(on: self.lifecycleQueue) {
            try self.start(configPath: configPath, controller: controller)
        }
    }

    public func stop() {
        let running: Process? = self.lock.withLock {
            self.intentionalStop = true
            return self.process
        }

        guard let running else {
            self.lock.withLock {
                self.status = .stopped
                self.intentionalStop = false
                self.releasePipeHandlesLocked()
            }
            return
        }

        guard running.isRunning else {
            self.handleProcessTermination(running, code: running.terminationStatus)
            return
        }

        self.onLog?("[mihomo stop] terminate signal sent pid=\(running.processIdentifier)")
        running.terminate()

        if self.waitForProcessExit(running, timeout: 2.0) {
            self.handleProcessTermination(running, code: running.terminationStatus)
            return
        }

        self.onLog?("[mihomo stop] force kill pid=\(running.processIdentifier)")
        _ = Darwin.kill(running.processIdentifier, SIGKILL)
        _ = self.waitForProcessExit(running, timeout: 1.0)
        self.handleProcessTermination(running, code: running.terminationStatus)
    }

    public func stopAsync() async {
        await self.runBlockingOperation(on: self.lifecycleQueue) {
            self.stop()
        }
    }

    @discardableResult
    public func restart(configPath: String, controller: String) throws -> CoreLifecycleStatus {
        self.stop()
        return try self.start(configPath: configPath, controller: controller)
    }

    @discardableResult
    public func restartAsync(configPath: String, controller: String) async throws -> CoreLifecycleStatus {
        try await self.runBlockingOperation(on: self.lifecycleQueue) {
            try self.restart(configPath: configPath, controller: controller)
        }
    }

    private func handleProcessTermination(_ terminatedProcess: Process, code: Int32) {
        let outcome = self.lock.withLock { () -> (handled: Bool, intentional: Bool) in
            guard let current = process, current === terminatedProcess else {
                return (false, false)
            }

            let intentional = self.intentionalStop
            self.intentionalStop = false
            self.process = nil
            self.status = .stopped
            self.releasePipeHandlesLocked()
            return (true, intentional)
        }

        guard outcome.handled else { return }

        if outcome.intentional {
            self.onLog?("[mihomo stopped] exit=\(code)")
        } else {
            self.onLog?("[mihomo terminated] exit=\(code)")
            self.onTermination?(code)
        }
    }

    private func waitForProcessExit(_ process: Process, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            usleep(50000)
        }
        return !process.isRunning
    }

    private func runBlockingOperation<Value: Sendable>(
        on queue: DispatchQueue,
        _ operation: @escaping @Sendable () throws -> Value) async throws -> Value
    {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    try continuation.resume(returning: operation())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func runBlockingOperation(
        on queue: DispatchQueue,
        _ operation: @escaping @Sendable () -> Void) async
    {
        try? await self.runBlockingOperation(on: queue) { () throws in
            operation()
        }
    }

    private func normalizedValidationTimeoutSeconds() -> Int {
        max(1, Int(self.configValidationTimeout.rounded(.awayFromZero)))
    }

    public func resolveMihomoBinary() throws -> String {
        if let bootstrap = self.configuration.bootstrapDirectories {
            try bootstrap(self.fileManager)
        } else {
            try self.fileManager.createDirectory(
                at: self.configuration.coreDirectoryURL,
                withIntermediateDirectories: true)
        }

        let managedBinaryPath = self.configuration.managedBinaryURL.path

        if self.fileManager.fileExists(atPath: managedBinaryPath) {
            try self.ensureExecutableIfNeeded(at: managedBinaryPath)
            if self.fileManager.isExecutableFile(atPath: managedBinaryPath) {
                try self.validateBinarySecurity(at: managedBinaryPath)
                return managedBinaryPath
            }
        }

        if let bundledBinaryPath = self.firstBundledExecutableBinaryPath() {
            try self.validateBinarySecurity(at: bundledBinaryPath)
            let migratedBinaryPath = try self.copyBundledBinaryToManagedCore(
                bundledPath: bundledBinaryPath,
                managedPath: managedBinaryPath)
            try self.validateBinarySecurity(at: migratedBinaryPath)
            return migratedBinaryPath
        }

        guard let bundledCompressedBinaryPath = self.firstBundledCompressedBinaryPath() else {
            throw MihomoBinaryResolutionError.binaryNotFound(
                expectedDirectory: self.configuration.coreDirectoryURL.path)
        }

        try self.validateBinarySecurity(at: bundledCompressedBinaryPath)
        let migratedBinaryPath = try self.decompressBundledBinaryToManagedCore(
            compressedPath: bundledCompressedBinaryPath,
            managedPath: managedBinaryPath)
        try self.validateBinarySecurity(at: migratedBinaryPath)
        return migratedBinaryPath
    }

    private func firstBundledExecutableBinaryPath() -> String? {
        for candidate in self.bundledBinaryCandidates() where self.fileManager.isExecutableFile(atPath: candidate) {
            return candidate
        }
        return nil
    }

    private func firstBundledCompressedBinaryPath() -> String? {
        for candidate in self.bundledCompressedBinaryCandidates() where self.fileManager.fileExists(atPath: candidate) {
            return candidate
        }
        return nil
    }

    private func bundledBinaryCandidates() -> [String] {
        Self.bundledBinaryCandidates(binaryName: "mihomo", roots: self.configuration.candidateBinaryRoots)
    }

    private func bundledCompressedBinaryCandidates() -> [String] {
        Self.bundledBinaryCandidates(binaryName: "mihomo.gz", roots: self.configuration.candidateBinaryRoots)
    }

    private static func bundledBinaryCandidates(binaryName: String, roots: [URL]) -> [String] {
        let relativeLayouts = [binaryName, "bin/\(binaryName)", "Resources/bin/\(binaryName)"]

        var deduplicated: [String] = []
        var seen = Set<String>()
        for root in roots {
            for relative in relativeLayouts {
                let normalized = root.appendingPathComponent(relative).standardizedFileURL.path
                if seen.insert(normalized).inserted {
                    deduplicated.append(normalized)
                }
            }
        }
        return deduplicated
    }

    private func copyBundledBinaryToManagedCore(bundledPath: String, managedPath: String) throws -> String {
        if self.fileManager.fileExists(atPath: managedPath) {
            try self.fileManager.removeItem(atPath: managedPath)
        }

        do {
            try self.fileManager.copyItem(atPath: bundledPath, toPath: managedPath)
            self.onLog?("[mihomo binary] copied bundled core to \(managedPath)")
            try self.ensureExecutableIfNeeded(at: managedPath)
            return managedPath
        } catch {
            throw NSError(
                domain: "ClashBar.Core",
                code: 500,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "failed to migrate mihomo binary to \(managedPath): \(error.localizedDescription)",
                ])
        }
    }

    private func decompressBundledBinaryToManagedCore(compressedPath: String, managedPath: String) throws -> String {
        let temporaryPath = managedPath + ".tmp"
        if self.fileManager.fileExists(atPath: temporaryPath) {
            try self.fileManager.removeItem(atPath: temporaryPath)
        }
        if self.fileManager.fileExists(atPath: managedPath) {
            try self.fileManager.removeItem(atPath: managedPath)
        }

        self.fileManager.createFile(atPath: temporaryPath, contents: nil)
        let outputURL = URL(fileURLWithPath: temporaryPath)
        let outputHandle = try FileHandle(forWritingTo: outputURL)
        let errorPipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/gunzip")
        process.arguments = ["-c", compressedPath]
        process.standardOutput = outputHandle
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
            try outputHandle.close()

            guard process.terminationStatus == 0 else {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorText = String(data: errorData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown error"
                try? self.fileManager.removeItem(atPath: temporaryPath)
                throw NSError(
                    domain: "ClashBar.Core",
                    code: 500,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "failed to decompress bundled mihomo binary from \(compressedPath): \(errorText)",
                    ])
            }

            try self.fileManager.moveItem(atPath: temporaryPath, toPath: managedPath)
            self.onLog?("[mihomo binary] decompressed bundled core to \(managedPath)")
            try self.ensureExecutableIfNeeded(at: managedPath)
            return managedPath
        } catch {
            try? outputHandle.close()
            try? self.fileManager.removeItem(atPath: temporaryPath)
            if let error = error as NSError?, error.domain == "ClashBar.Core" {
                throw error
            }
            throw NSError(
                domain: "ClashBar.Core",
                code: 500,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "failed to migrate compressed mihomo binary to \(managedPath): \(error.localizedDescription)",
                ])
        }
    }

    private func ensureExecutableIfNeeded(at path: String) throws {
        guard self.fileManager.fileExists(atPath: path) else {
            throw NSError(
                domain: "ClashBar.Core",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "mihomo binary not found at \(path)"])
        }

        guard !self.fileManager.isExecutableFile(atPath: path) else { return }
        try self.fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
    }

    private func validateBinarySecurity(at path: String) throws {
        let url = URL(fileURLWithPath: path)
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])

        if values.isSymbolicLink == true {
            throw NSError(
                domain: "ClashBar.Core",
                code: 403,
                userInfo: [NSLocalizedDescriptionKey: "mihomo binary path must not be a symbolic link: \(path)"])
        }
        if values.isRegularFile != true {
            throw NSError(
                domain: "ClashBar.Core",
                code: 403,
                userInfo: [NSLocalizedDescriptionKey: "mihomo binary must be a regular file: \(path)"])
        }

        let attrs = try FileManager.default.attributesOfItem(atPath: path)
        let uid = Int(getuid())
        if let owner = attrs[.ownerAccountID] as? NSNumber {
            let ownerID = owner.intValue
            if ownerID != 0, ownerID != uid {
                throw NSError(
                    domain: "ClashBar.Core",
                    code: 403,
                    userInfo: [NSLocalizedDescriptionKey: "mihomo binary owner must be current user or root: \(path)"])
            }
        }

        if let perm = attrs[.posixPermissions] as? NSNumber {
            let mode = perm.intValue
            if (mode & 0o022) != 0 {
                throw NSError(
                    domain: "ClashBar.Core",
                    code: 403,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "mihomo binary permissions are too permissive " +
                            "(writable by group/others): \(path)",
                    ])
            }
        }
    }

    public static func resolveWorkingDirectoryURL(configPath: String) -> URL {
        let configDirectoryURL = URL(fileURLWithPath: configPath)
            .standardizedFileURL
            .deletingLastPathComponent()
            .resolvingSymlinksInPath()
        if configDirectoryURL.lastPathComponent == "config" {
            return configDirectoryURL.deletingLastPathComponent()
        }
        return configDirectoryURL
    }

    private func wireLogPipe(_ handle: FileHandle) {
        let accumulator = LineAccumulator()
        let gate = LogFloodGate()
        handle.readabilityHandler = { [weak self] readable in
            let data = readable.availableData
            if data.isEmpty {
                if let tail = accumulator.flushRemaining() {
                    self?.onLog?(tail)
                }
                return
            }
            for line in gate.accept(accumulator.append(data)) {
                self?.onLog?(line)
            }
        }
    }

    private func releasePipeHandlesLocked() {
        self.stdoutHandle?.readabilityHandler = nil
        self.stderrHandle?.readabilityHandler = nil
        self.stdoutHandle?.closeFile()
        self.stderrHandle?.closeFile()
        self.stdoutHandle = nil
        self.stderrHandle = nil
    }
}
