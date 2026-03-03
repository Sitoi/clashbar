import Foundation

@MainActor
extension AppState {
    func normalizedWebSocketPayload(from message: URLSessionWebSocketTask.Message) -> Data? {
        switch message {
        case let .data(data):
            guard !data.isEmpty else { return nil }
            return data
        case let .string(text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            if trimmed == "null" || trimmed == "{}" {
                return nil
            }
            return Data(trimmed.utf8)
        @unknown default:
            return nil
        }
    }

    func startDecodableStream<Payload: Decodable>(
        kind: StreamKind,
        makeWebSocket: @escaping (MihomoAPIClient) throws -> URLSessionWebSocketTask,
        onDecoded: @escaping (Payload) -> Void)
    {
        startStream(
            kind: kind,
            makeWebSocket: makeWebSocket,
            onPayload: { [weak self] payload in
                guard let self else { return }
                guard let decoded = try? self.streamJSONDecoder.decode(Payload.self, from: payload) else {
                    // Ignore malformed/empty payloads without reconnecting to avoid log storms.
                    return
                }
                onDecoded(decoded)
            })
    }

    func decodeLogLinePayload(_ payload: Data) -> (level: String, message: String)? {
        if let log = try? self.streamJSONDecoder.decode(LogLine.self, from: payload) {
            let level = (log.type?.isEmpty == false) ? (log.type ?? "info") : "info"
            let message = log.payload?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !message.isEmpty {
                return (level: level, message: message)
            }
        }

        if let response = try? self.streamJSONDecoder.decode(LogsResponse.self, from: payload),
           let first = response.logs?.first
        {
            let level = (first.type?.isEmpty == false) ? (first.type ?? "info") : "info"
            let message = first.payload?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !message.isEmpty {
                return (level: level, message: message)
            }
        }

        if let text = String(data: payload, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty
        {
            return (level: "info", message: text)
        }
        return nil
    }
}
