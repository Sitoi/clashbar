import Foundation

@MainActor
public final class StreamCoordinator {
    public var streamReceiveTasks: [String: Task<Void, Never>] = [:]
    public var streamWebSocketTasks: [String: URLSessionWebSocketTask] = [:]
    public var streamReconnectAttempts: [String: Int] = [:]
    public var streamLastDisconnectLogAt: [String: Date] = [:]
    public var streamLastDisconnectLogMessage: [String: String] = [:]

    public let baseDelayNanoseconds: UInt64
    public let maxDelayNanoseconds: UInt64
    public let disconnectLogThrottleInterval: TimeInterval

    public var shouldReconnect: () -> Bool = { false }
    public var onDisconnect: (String, String) -> Void = { _, _ in }
    public var onStartError: (String, Error) -> Void = { _, _ in }

    public private(set) var mediumFrequencyTask: Task<Void, Never>?
    public private(set) var lowFrequencyTask: Task<Void, Never>?

    public var onMediumFrequencyPoll: (() async -> Void)?
    public var onLowFrequencyPoll: (() async -> Void)?

    public init(
        baseDelayNanoseconds: UInt64 = 1_000_000_000,
        maxDelayNanoseconds: UInt64 = 8_000_000_000,
        disconnectLogThrottleInterval: TimeInterval = 2)
    {
        self.baseDelayNanoseconds = baseDelayNanoseconds
        self.maxDelayNanoseconds = maxDelayNanoseconds
        self.disconnectLogThrottleInterval = disconnectLogThrottleInterval
    }

    public func start(
        key: String,
        makeWebSocket: @escaping () throws -> URLSessionWebSocketTask,
        onPayload: @escaping (Data) -> Void,
        normalizePayload: @escaping (URLSessionWebSocketTask.Message) -> Data?)
    {
        self.cancel(key: key, resetReconnectState: false)

        do {
            let ws = try makeWebSocket()
            self.streamWebSocketTasks[key] = ws
            ws.resume()

            let task = Task { @MainActor [weak self] in
                guard let self else { return }
                await self.receiveLoop(
                    key: key,
                    onPayload: onPayload,
                    normalizePayload: normalizePayload,
                    restart: { [weak self] in
                        self?.start(
                            key: key,
                            makeWebSocket: makeWebSocket,
                            onPayload: onPayload,
                            normalizePayload: normalizePayload)
                    })
            }
            self.streamReceiveTasks[key] = task
        } catch {
            if !(error is CancellationError) {
                self.onStartError(key, error)
            }
        }
    }

    public func payloadStream(
        key: String,
        makeWebSocket: @escaping () throws -> URLSessionWebSocketTask,
        normalizePayload: @escaping (URLSessionWebSocketTask.Message) -> Data?) -> AsyncStream<Data>
    {
        AsyncStream { continuation in
            self.start(
                key: key,
                makeWebSocket: makeWebSocket,
                onPayload: { data in
                    continuation.yield(data)
                },
                normalizePayload: normalizePayload)

            continuation.onTermination = { @Sendable [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.cancel(key: key)
                }
            }
        }
    }

    public func cancel(key: String, resetReconnectState: Bool = true) {
        self.streamReceiveTasks[key]?.cancel()
        self.streamWebSocketTasks[key]?.cancel(with: .goingAway, reason: nil)
        self.streamReceiveTasks[key] = nil
        self.streamWebSocketTasks[key] = nil
        if resetReconnectState {
            self.clearReconnectState(for: key)
        }
    }

    public func cancelAll() {
        self.cancelPolling()
        for key in self.streamReceiveTasks.keys {
            self.cancel(key: key)
        }
    }

    public func cancelPolling() {
        self.mediumFrequencyTask?.cancel()
        self.lowFrequencyTask?.cancel()
        self.mediumFrequencyTask = nil
        self.lowFrequencyTask = nil
    }

    public func pauseHighFrequencyStreams() {
        self.cancel(key: "connections")
        self.cancel(key: "logs")
        self.cancel(key: "memory")
        self.cancelPolling()
    }

    public func updatePollingSchedule(
        isRunning: Bool,
        isPanelPresented: Bool,
        isHighFrequencyTabActive: Bool = false)
    {
        guard isRunning else {
            self.cancelPolling()
            return
        }

        if !isPanelPresented {
            self.cancelPolling()
        } else {
            if self.mediumFrequencyTask == nil {
                self.mediumFrequencyTask = Task { @MainActor [weak self] in
                    while !Task.isCancelled {
                        await self?.onMediumFrequencyPoll?()
                        guard !Task.isCancelled else { return }
                        let interval: UInt64 = 4_000_000_000
                        try? await Task.sleep(nanoseconds: interval)
                    }
                }
            }
            if self.lowFrequencyTask == nil {
                self.lowFrequencyTask = Task { @MainActor [weak self] in
                    while !Task.isCancelled {
                        await self?.onLowFrequencyPoll?()
                        guard !Task.isCancelled else { return }
                        let interval: UInt64 = isHighFrequencyTabActive
                            ? 20_000_000_000 : 45_000_000_000
                        try? await Task.sleep(nanoseconds: interval)
                    }
                }
            }
        }
    }

    public func isActive(key: String) -> Bool {
        self.streamWebSocketTasks[key] != nil
    }

    public func webSocketTask(for key: String) -> URLSessionWebSocketTask? {
        self.streamWebSocketTasks[key]
    }

    private func receiveLoop(
        key: String,
        onPayload: @escaping (Data) -> Void,
        normalizePayload: @escaping (URLSessionWebSocketTask.Message) -> Data?,
        restart: @escaping () -> Void) async
    {
        while !Task.isCancelled {
            guard let ws = streamWebSocketTasks[key] else { return }

            let message: URLSessionWebSocketTask.Message
            do {
                message = try await ws.receive()
            } catch {
                if Task.isCancelled {
                    return
                }

                let errorMessage = error.localizedDescription
                if self.shouldLogDisconnect(key: key, message: errorMessage) {
                    self.onDisconnect(key, errorMessage)
                }
                self.streamWebSocketTasks[key]?.cancel(with: .goingAway, reason: nil)
                self.streamWebSocketTasks[key] = nil

                guard self.shouldReconnect() else { return }
                do {
                    try await Task.sleep(nanoseconds: self.nextReconnectDelayNanoseconds(for: key))
                } catch {
                    return
                }
                if Task.isCancelled {
                    return
                }
                guard self.shouldReconnect() else { return }
                restart()
                return
            }

            guard let payload = normalizePayload(message) else { continue }
            self.markPayloadReceived(for: key)
            onPayload(payload)
        }
    }

    package nonisolated static func computeReconnectDelayNanoseconds(
        attempt: Int,
        baseDelayNanoseconds: UInt64 = 1_000_000_000,
        maxDelayNanoseconds: UInt64 = 8_000_000_000,
        jitter: Double? = nil) -> UInt64
    {
        let normalizedAttempt = max(0, attempt)
        let seconds = min(8, 1 << min(normalizedAttempt, 3))
        let base = UInt64(seconds) * baseDelayNanoseconds
        let multiplier = jitter ?? Double.random(in: 0.85...1.15)
        let jittered = UInt64(Double(base) * multiplier)
        return min(maxDelayNanoseconds, max(baseDelayNanoseconds, jittered))
    }

    private func nextReconnectDelayNanoseconds(for key: String) -> UInt64 {
        let attempt = max(0, self.streamReconnectAttempts[key] ?? 0)
        self.streamReconnectAttempts[key] = min(attempt + 1, 8)
        return Self.computeReconnectDelayNanoseconds(
            attempt: attempt,
            baseDelayNanoseconds: self.baseDelayNanoseconds,
            maxDelayNanoseconds: self.maxDelayNanoseconds)
    }

    package func reconnectAttempt(for key: String) -> Int {
        self.streamReconnectAttempts[key] ?? 0
    }

    private func markPayloadReceived(for key: String) {
        self.streamReconnectAttempts[key] = 0
    }

    private func shouldLogDisconnect(key: String, message: String) -> Bool {
        let now = Date()
        if let lastAt = self.streamLastDisconnectLogAt[key],
           let lastMessage = self.streamLastDisconnectLogMessage[key]
        {
            let withinThrottle = now.timeIntervalSince(lastAt) < self.disconnectLogThrottleInterval
            if withinThrottle, lastMessage == message {
                return false
            }
        }

        self.streamLastDisconnectLogAt[key] = now
        self.streamLastDisconnectLogMessage[key] = message
        return true
    }

    public func clearReconnectState(for key: String) {
        self.streamReconnectAttempts.removeValue(forKey: key)
        self.streamLastDisconnectLogAt.removeValue(forKey: key)
        self.streamLastDisconnectLogMessage.removeValue(forKey: key)
    }
}
