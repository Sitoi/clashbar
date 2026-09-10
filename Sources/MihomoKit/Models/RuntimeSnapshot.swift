import Foundation

/// Low-level factual snapshot of the running Mihomo core instance.
///
/// Distinct from `ClashBar.RuntimeState`, which represents UI session and user intent.
public struct RuntimeSnapshot: Equatable, Sendable {
    public let processPID: Int32?
    public let version: String?
    public let config: ConfigSnapshot?
    public let memory: MemorySnapshot?
    public let traffic: TrafficSnapshot?
    public let totalConnections: Int?

    public init(
        processPID: Int32? = nil,
        version: String? = nil,
        config: ConfigSnapshot? = nil,
        memory: MemorySnapshot? = nil,
        traffic: TrafficSnapshot? = nil,
        totalConnections: Int? = nil)
    {
        self.processPID = processPID
        self.version = version
        self.config = config
        self.memory = memory
        self.traffic = traffic
        self.totalConnections = totalConnections
    }
}
