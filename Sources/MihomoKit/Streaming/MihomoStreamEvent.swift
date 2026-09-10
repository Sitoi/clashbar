import Foundation

/// Standardized streaming event type for all Mihomo real-time data channels.
///
/// Store consumers subscribe to a single `AsyncStream<MihomoStreamEvent>` instead of
/// managing individual WebSocket sessions, providing a unified event bus.
public enum MihomoStreamEvent: Sendable {
    case traffic(TrafficSnapshot)
    case log(LogLine)
    case connections(ConnectionsSnapshot)
    case memory(MemorySnapshot)
}
