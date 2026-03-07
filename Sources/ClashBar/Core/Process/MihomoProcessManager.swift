import Darwin
import Foundation

enum MihomoConfigValidationError: LocalizedError {
    case launchFailed(String)
    case timedOut(seconds: Int, details: String)
    case failed(exitCode: Int32, details: String)

    var errorDescription: String? {
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

private final class ProcessOutputBox: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func store(_ data: Data) {
        self.lock.withLock {
            self.data = data
        }
    }

    func load() -> Data {
        self.lock.withLock {
            self.data
        }
    }
}

/// Process callbacks run on system-managed threads. Shared mutable state is guarded by `lock`.
final class MihomoProcessManager: MihomoControlling, @unchecked Sendable {
    private(set) var status: CoreLifecycleStatus = .stopped
    private var process: Process?
    private var stdoutHandle: FileHandle?
    private var stderrHandle: FileHandle?
    private var intentionalStop = false
    private let lock = NSLock()
    private let stateActor = ProcessStateActor()
    private let fileManager: FileManager
    private let workingDirectoryManager: WorkingDirectoryManager
    private let lifecycleQueue: DispatchQueue
    private let validationQueue: DispatchQueue
    private let configValidationTimeout: TimeInterval

    var onLog: ((String) -> Void)?
    var onTermination: ((Int32) -> Void)?

    var detectedBinaryPath: String? {
        try? self.resolveMihomoBinary()
    }

    var isRunning: Bool {
        self.lock.withLock {
            self.process?.isRunning == true
        }
    }

    init(
        workingDirectoryManager: WorkingDirectoryManager = WorkingDirectoryManager(),
        fileManager: FileManager = .default,
        configValidationTimeout: TimeInterval = 10,
        lifecycleQueue: DispatchQueue? = nil,
        validationQueue: DispatchQueue? = nil)
    {
        self.workingDirectoryManager = workingDirectoryManager
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

    func validateConfig(configPath: String) throws {
        let binary = try resolveMihomoBinary()

        let configFileURL = URL(fileURLWithPath: configPath).standardizedFileURL.resolvingSymlinksInPath()
        let configDirectoryURL = configFileURL.deletingLastPathComponent()
        let workingDirectoryURL: URL = if configDirectoryURL.lastPathComponent == "config" {
            configDirectoryURL.deletingLastPathComponent()
        } else {
            configDirectoryURL
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binary)
        proc.currentDirectoryURL = workingDirectoryURL
        proc.arguments = ["-d", workingDirectoryURL.path, "-f", configPath, "-t"]

        let outputPipe = Pipe()
        proc.standardOutput = outputPipe
        proc.standardError = outputPipe
        let outputBox = ProcessOutputBox()
        let outputDrainGroup = DispatchGroup()
        outputDrainGroup.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            outputBox.store(outputData)
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
        let outputData = outputBox.load()
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

    func validateConfigAsync(configPath: String) async throws {
        try await self.runBlockingOperation(on: self.validationQueue) {
            try self.validateConfig(configPath: configPath)
        }
    }

    @discardableResult
    func start(configPath: String, controller: String) throws -> CoreLifecycleStatus {
        if let runningPid = lock.withLock({ process?.isRunning == true ? process?.processIdentifier : nil }) {
            return .running(pid: runningPid)
        }

        self.lock.withLock {
            self.intentionalStop = false
            self.status = .starting
        }
        Task {
            await self.stateActor.setIntentionalStop(false)
            await self.stateActor.setStatus(.starting)
        }

        let binary = try resolveMihomoBinary()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binary)

        let configFileURL = URL(fileURLWithPath: configPath).standardizedFileURL.resolvingSymlinksInPath()
        let configDirectoryURL = configFileURL.deletingLastPathComponent()
        let workingDirectoryURL: URL = if configDirectoryURL.lastPathComponent == "config" {
            configDirectoryURL.deletingLastPathComponent()
        } else {
            configDirectoryURL
        }
        proc.currentDirectoryURL = workingDirectoryURL

        // `-d` pins mihomo runtime home directory to ClashBar working root.
        // This prevents fallback to ~/.config/mihomo for provider/cache updates.
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
            Task {
                await self.stateActor.setStatus(.running(pid: proc.processIdentifier))
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
            Task {
                await self.stateActor.setIntentionalStop(false)
                await self.stateActor.setStatus(.failed(reason: reason))
            }
            self.onLog?("[mihomo error] \(reason)")
            throw error
        }
    }

    @discardableResult
    func startAsync(configPath: String, controller: String) async throws -> CoreLifecycleStatus {
        try await self.runBlockingOperation(on: self.lifecycleQueue) {
            try self.start(configPath: configPath, controller: controller)
        }
    }

    func stop() {
        let running: Process? = self.lock.withLock {
            self.intentionalStop = true
            return self.process
        }
        Task {
            await self.stateActor.setIntentionalStop(true)
        }

        guard let running else {
            self.lock.withLock {
                self.status = .stopped
                self.intentionalStop = false
                self.releasePipeHandlesLocked()
            }
            Task {
                await self.stateActor.setIntentionalStop(false)
                await self.stateActor.setStatus(.stopped)
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

    func stopAsync() async {
        await self.runBlockingOperation(on: self.lifecycleQueue) {
            self.stop()
        }
    }

    @discardableResult
    func restart(configPath: String, controller: String) throws -> CoreLifecycleStatus {
        self.stop()
        return try self.start(configPath: configPath, controller: controller)
    }

    @discardableResult
    func restartAsync(configPath: String, controller: String) async throws -> CoreLifecycleStatus {
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
        Task {
            await self.stateActor.setIntentionalStop(false)
            await self.stateActor.setStatus(.stopped)
        }

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
        await withCheckedContinuation { continuation in
            queue.async {
                operation()
                continuation.resume()
            }
        }
    }

    private func normalizedValidationTimeoutSeconds() -> Int {
        max(1, Int(self.configValidationTimeout.rounded(.awayFromZero)))
    }

    private func resolveMihomoBinary() throws -> String {
        try self.workingDirectoryManager.bootstrapDirectories(fileManager: self.fileManager)

        let managedBinaryPath = self.workingDirectoryManager.coreDirectoryURL
            .appendingPathComponent("mihomo", isDirectory: false)
            .path

        if self.fileManager.fileExists(atPath: managedBinaryPath) {
            try self.ensureExecutableIfNeeded(at: managedBinaryPath)
            if self.fileManager.isExecutableFile(atPath: managedBinaryPath) {
                try self.validateBinarySecurity(at: managedBinaryPath)
                return managedBinaryPath
            }
        }

        guard let bundledBinaryPath = self.firstBundledExecutableBinaryPath() else {
            throw NSError(
                domain: "ClashBar.Core",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "mihomo binary not found in app resources"])
        }

        try self.validateBinarySecurity(at: bundledBinaryPath)
        let migratedBinaryPath = try self.copyBundledBinaryToManagedCore(
            bundledPath: bundledBinaryPath,
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

    private func bundledBinaryCandidates() -> [String] {
        let resourceRoots = AppResourceBundleLocator.candidateResourceRoots()
        var candidates: [String] = []

        for root in resourceRoots {
            candidates.append(root.appendingPathComponent("bin/mihomo").path)
            candidates.append(root.appendingPathComponent("Resources/bin/mihomo").path)
            candidates.append(root.appendingPathComponent("mihomo").path)
        }

        var deduplicated: [String] = []
        var seen = Set<String>()
        for path in candidates {
            let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
            if seen.insert(normalized).inserted {
                deduplicated.append(normalized)
            }
        }
        return deduplicated
    }

    private func copyBundledBinaryToManagedCore(bundledPath: String, managedPath: String) throws -> String {
        if self.fileManager.fileExists(atPath: managedPath) {
            try self.fileManager.removeItem(atPath: managedPath)
        }

        // Keep signed app bundle immutable: only copy core out to user-managed directory.
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
            // Refuse group-writable or world-writable executables.
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

    private func wireLogPipe(_ handle: FileHandle) {
        handle.readabilityHandler = { [weak self] readable in
            let data = readable.availableData
            if data.isEmpty { return }
            guard let line = String(data: data, encoding: .utf8) else { return }
            self?.onLog?(line.trimmingCharacters(in: .whitespacesAndNewlines))
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
