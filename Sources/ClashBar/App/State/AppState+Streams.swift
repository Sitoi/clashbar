import Foundation

@MainActor
extension AppState {
    enum StreamKind: CaseIterable, Hashable {
        case traffic
        case memory
        case connections
        case logs

        var key: String {
            switch self {
            case .traffic: "traffic"
            case .memory: "memory"
            case .connections: "connections"
            case .logs: "logs"
            }
        }

        var label: String {
            switch self {
            case .traffic: "app.stream.label.traffic"
            case .memory: "app.stream.label.memory"
            case .connections: "app.stream.label.connections"
            case .logs: "app.stream.label.logs"
            }
        }
    }

    func startStream(
        kind: StreamKind,
        preserveReconnectState: Bool = false,
        makeWebSocket: @escaping (MihomoAPIClient) throws -> URLSessionWebSocketTask,
        onPayload: @escaping (Data) -> Void)
    {
        self.cancelStream(kind, resetReconnectState: !preserveReconnectState)

        do {
            guard let client = try? clientOrThrow() else { return }
            let ws = try makeWebSocket(client)
            self.setWebSocketTask(ws, for: kind)
            ws.resume()

            let task = Task { @MainActor [weak self] in
                guard let self else { return }
                await self.receiveLoop(
                    kind: kind,
                    onPayload: onPayload,
                    restart: { [weak self] in
                        self?.startStream(
                            kind: kind,
                            preserveReconnectState: true,
                            makeWebSocket: makeWebSocket,
                            onPayload: onPayload)
                    })
            }
            self.setReceiveTask(task, for: kind)
        } catch {
            appendLog(
                level: "error",
                message: tr("log.stream.start_failed", tr(kind.label), error.localizedDescription))
        }
    }

    func cancelStream(_ kind: StreamKind, resetReconnectState: Bool = true) {
        self.receiveTask(for: kind)?.cancel()
        self.webSocketTask(for: kind)?.cancel(with: .goingAway, reason: nil)
        self.setReceiveTask(nil, for: kind)
        self.setWebSocketTask(nil, for: kind)
        if kind == .connections {
            currentConnectionsStreamIntervalMilliseconds = nil
        }
        if resetReconnectState {
            self.resetStreamReconnectState(for: kind)
        }
    }

    private func receiveLoop(
        kind: StreamKind,
        onPayload: @escaping (Data) -> Void,
        restart: @escaping () -> Void) async
    {
        while !Task.isCancelled {
            guard let ws = webSocketTask(for: kind) else { return }

            let message: URLSessionWebSocketTask.Message
            do {
                message = try await ws.receive()
            } catch {
                if Task.isCancelled { return }
                let disconnectMessage = error.localizedDescription
                if self.shouldLogStreamDisconnect(kind: kind, message: disconnectMessage) {
                    appendLog(level: "error", message: tr("log.stream.disconnected", tr(kind.label), disconnectMessage))
                }
                self.webSocketTask(for: kind)?.cancel(with: .goingAway, reason: nil)
                self.setWebSocketTask(nil, for: kind)

                guard processManager.isRunning else { return }
                do {
                    try await Task.sleep(nanoseconds: self.nextReconnectDelayNanoseconds(for: kind))
                } catch {
                    return
                }
                if Task.isCancelled { return }
                guard processManager.isRunning else { return }
                restart()
                return
            }

            guard let payload = normalizedWebSocketPayload(from: message) else { continue }
            self.markStreamPayloadReceived(for: kind)
            onPayload(payload)
        }
    }

    func receiveTask(for kind: StreamKind) -> Task<Void, Never>? {
        streamReceiveTasks[kind]
    }

    func setReceiveTask(_ task: Task<Void, Never>?, for kind: StreamKind) {
        if let task {
            streamReceiveTasks[kind] = task
        } else {
            streamReceiveTasks.removeValue(forKey: kind)
        }
    }

    func webSocketTask(for kind: StreamKind) -> URLSessionWebSocketTask? {
        streamWebSocketTasks[kind]
    }

    func setWebSocketTask(_ task: URLSessionWebSocketTask?, for kind: StreamKind) {
        if let task {
            streamWebSocketTasks[kind] = task
        } else {
            streamWebSocketTasks.removeValue(forKey: kind)
        }
    }

    func startTrafficStream() {
        startDecodableStream(
            kind: .traffic,
            makeWebSocket: { try $0.makeTrafficWebSocketTask() },
            onDecoded: { [weak self] (snapshot: TrafficSnapshot) in
                guard let self else { return }
                traffic = snapshot
                guard isPanelPresented else {
                    if !trafficHistoryUp.isEmpty || !trafficHistoryDown
                        .isEmpty || displayUpTotal != 0 || displayDownTotal != 0 || lastTrafficSampleAt != nil
                    {
                        clearTrafficPresentationHistory()
                    }
                    return
                }
                appendTrafficHistory(up: snapshot.up, down: snapshot.down)
                updateTrafficTotals(from: snapshot)
            })
    }

    func startMemoryStream() {
        startDecodableStream(
            kind: .memory,
            makeWebSocket: { try $0.makeMemoryWebSocketTask() },
            onDecoded: { [weak self] (snapshot: MemorySnapshot) in
                guard let self else { return }
                memory = snapshot
            })
    }

    func startConnectionsStream(intervalMilliseconds: Int? = nil) {
        startDecodableStream(
            kind: .connections,
            makeWebSocket: { try $0.makeConnectionsWebSocketTask(interval: intervalMilliseconds) },
            onDecoded: { [weak self] (snapshot: ConnectionsSnapshot) in
                guard let self else { return }
                self.applyConnectionsSnapshot(snapshot)
            })
        currentConnectionsStreamIntervalMilliseconds = intervalMilliseconds
    }

    func startLogsStream() {
        self.startStream(
            kind: .logs,
            makeWebSocket: { try $0.makeLogsWebSocketTask(level: nil) },
            onPayload: { [weak self] payload in
                guard let self else { return }
                if let line = decodeLogLinePayload(payload) {
                    appendMihomoLog(level: line.level, message: line.message)
                }
            })
    }

    private func applyConnectionsSnapshot(_ snapshot: ConnectionsSnapshot) {
        let totalCount = snapshot.connections.count
        if connectionsCount != totalCount {
            connectionsCount = totalCount
        }

        let latestConnections = Array(snapshot.connections.prefix(maxRetainedConnections))
        if connections != latestConnections {
            connections = latestConnections
        }
    }

    private func resetStreamReconnectState(for kind: StreamKind) {
        streamReconnectAttempts.removeValue(forKey: kind.key)
        streamLastDisconnectLogAt.removeValue(forKey: kind.key)
        streamLastDisconnectLogMessage.removeValue(forKey: kind.key)
    }

    private func markStreamPayloadReceived(for kind: StreamKind) {
        streamReconnectAttempts[kind.key] = 0
    }

    private func nextReconnectDelayNanoseconds(for kind: StreamKind) -> UInt64 {
        let key = kind.key
        let attempt = max(0, streamReconnectAttempts[key] ?? 0)
        let cappedShift = min(attempt, 3)
        let seconds = min(8, 1 << cappedShift)
        streamReconnectAttempts[key] = min(attempt + 1, 8)

        let jitter = Double.random(in: 0.85...1.15)
        let base = UInt64(seconds) * streamReconnectBaseDelayNanoseconds
        let jittered = UInt64(Double(base) * jitter)
        return min(streamReconnectMaxDelayNanoseconds, max(streamReconnectBaseDelayNanoseconds, jittered))
    }

    private func shouldLogStreamDisconnect(kind: StreamKind, message: String) -> Bool {
        let key = kind.key
        let now = Date()
        let lastAt = streamLastDisconnectLogAt[key]
        let lastMessage = streamLastDisconnectLogMessage[key]

        let shouldEmit: Bool
        if let lastAt, let lastMessage {
            let withinThrottle = now.timeIntervalSince(lastAt) < streamDisconnectLogThrottleInterval
            shouldEmit = !(withinThrottle && lastMessage == message)
        } else {
            shouldEmit = true
        }

        if shouldEmit {
            streamLastDisconnectLogAt[key] = now
            streamLastDisconnectLogMessage[key] = message
        }
        return shouldEmit
    }
}
