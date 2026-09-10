import AppKit
import Combine
import Foundation
import MihomoKit
import SwiftUI

@MainActor
final class ConnectionsStore: ObservableObject {
    @Published var connections: [ConnectionSummary] = []
    @Published var connectionsCount: Int = 0

    @Published var filterText: String = "" {
        didSet { self.updateVisibleConnections() }
    }

    @Published var transportFilter: ConnectionsTransportFilter = .all {
        didSet { self.updateVisibleConnections() }
    }

    @Published var sortOption: ConnectionsSortOption = .default {
        didSet { self.updateVisibleConnections() }
    }

    @Published var hoveredConnectionID: String?
    @Published private(set) var visibleConnections: [ConnectionSummary] = []

    var apiClientProvider: (() throws -> MihomoAPIService)?
    var logHandler: ((_ level: String, _ message: String) -> Void)?

    func applySnapshot(_ snapshot: ConnectionsSnapshot) {
        if self.connectionsCount != snapshot.totalCount {
            self.connectionsCount = snapshot.totalCount
        }
        if self.connections != snapshot.connections {
            self.connections = snapshot.connections
            self.updateVisibleConnections()
        }
    }

    func handleStreamEvent(_ event: MihomoStreamEvent) {
        if case let .connections(snapshot) = event {
            self.applySnapshot(snapshot)
        }
    }

    func reset() {
        self.connectionsCount = 0
        self.connections.removeAll(keepingCapacity: false)
        self.visibleConnections = []
        self.hoveredConnectionID = nil
    }

    func updateVisibleConnections() {
        let keyword = self.filterText.trimmed
        let hasFilter = !keyword.isEmpty || self.transportFilter != .all

        let filtered: [ConnectionSummary] = if !hasFilter {
            self.connections
        } else {
            self.connections.filter { connection in
                guard self.transportFilter.matches(connection.metadata?.network) else { return false }
                guard keyword.isEmpty || connection.matches(keyword: keyword) else { return false }
                return true
            }
        }

        let sorted = self.sortedConnections(filtered, sortOption: self.sortOption)
        let nextConnections = Array(sorted.prefix(120))
        guard nextConnections != self.visibleConnections else { return }
        self.visibleConnections = nextConnections
    }

    func closeAllConnections() async {
        do {
            let client = try self.resolveClient()
            try await client.requestNoResponse(.closeAllConnections)
            self.logHandler?("info", "All connections closed")
            await self.refreshConnections()
        } catch {
            self.logHandler?("error", "Close all connections failed: \(error.localizedDescription)")
        }
    }

    func closeConnection(id: String) async {
        do {
            let client = try self.resolveClient()
            try await client.requestNoResponse(.closeConnection(id: id))
            self.logHandler?("info", "Connection \(id) closed")
            await self.refreshConnections()
        } catch {
            self.logHandler?("error", "Close connection \(id) failed: \(error.localizedDescription)")
        }
    }

    func refreshConnections() async {
        do {
            let client = try self.resolveClient()
            let snapshot: ConnectionsSnapshot = try await client.request(.connections(interval: nil))
            self.applySnapshot(snapshot)
        } catch {
            // Background refresh error ignored
        }
    }

    func resolvedConnectionHost(for connection: ConnectionSummary) -> String? {
        let host = connection.metadata?.host?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !host.isEmpty {
            return host
        }

        let destinationIP = connection.metadata?.destinationIP?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !destinationIP.isEmpty {
            return destinationIP
        }
        return nil
    }

    func copyConnectionHost(_ host: String) {
        self.copyAndLog(host, message: "Copied connection host: \(host)")
    }

    func copyConnectionID(_ id: String) {
        self.copyAndLog(id, message: "Copied connection ID: \(id)")
    }

    private func copyAndLog(_ text: String, message: String) {
        self.copyTextToPasteboard(text)
        self.logHandler?("info", message)
    }

    func copyTextToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func resolveClient() throws -> MihomoAPIService {
        guard let provider = self.apiClientProvider else {
            throw APIError.clientUnavailable
        }
        return try provider()
    }

    private func sortedConnections(
        _ source: [ConnectionSummary],
        sortOption: ConnectionsSortOption) -> [ConnectionSummary]
    {
        switch sortOption {
        case .default:
            source
        case .newest:
            self.connectionsSortedByTimestamp(source, descending: true)
        case .oldest:
            self.connectionsSortedByTimestamp(source, descending: false)
        case .uploadDesc:
            self.connectionsSortedByTraffic(source) { $0.upload ?? 0 }
        case .downloadDesc:
            self.connectionsSortedByTraffic(source) { $0.download ?? 0 }
        case .totalDesc:
            self.connectionsSortedByTraffic(source) { ($0.upload ?? 0) + ($0.download ?? 0) }
        }
    }

    private func connectionsSortedByTimestamp(
        _ source: [ConnectionSummary],
        descending: Bool) -> [ConnectionSummary]
    {
        let fallback: TimeInterval = descending ? -1 : .greatestFiniteMagnitude
        return source.sorted { lhs, rhs in
            let left = lhs.startTimestamp ?? fallback
            let right = rhs.startTimestamp ?? fallback
            if left != right {
                return descending ? (left > right) : (left < right)
            }
            return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
        }
    }

    private func connectionsSortedByTraffic(
        _ source: [ConnectionSummary],
        _ metric: (ConnectionSummary) -> Int64) -> [ConnectionSummary]
    {
        source.sorted { lhs, rhs in
            let left = metric(lhs)
            let right = metric(rhs)
            if left != right {
                return left > right
            }
            return (lhs.startTimestamp ?? -1) > (rhs.startTimestamp ?? -1)
        }
    }
}
