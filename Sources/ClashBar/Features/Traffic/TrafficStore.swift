import Combine
import Foundation
import MihomoKit

@MainActor
final class TrafficStore: ObservableObject {
    @Published var traffic: TrafficSnapshot = .init(up: 0, down: 0)
    @Published var memory: MemorySnapshot = .init(inuse: 0)
    @Published var displayUpTotal: Int64 = 0
    @Published var displayDownTotal: Int64 = 0
    @Published var trafficHistoryUp: [Int64] = []
    @Published var trafficHistoryDown: [Int64] = []

    private var lastTrafficSampleAt: Date?
    let historyMaxPoints: Int

    init(historyMaxPoints: Int = 60) {
        self.historyMaxPoints = historyMaxPoints
    }

    func resetPresentation() {
        self.traffic = TrafficSnapshot(up: 0, down: 0)
        self.lastTrafficSampleAt = nil
        self.resetHistory()
    }

    func resetHistory(maxPoints: Int? = nil) {
        let limit = maxPoints ?? self.historyMaxPoints
        self.displayUpTotal = 0
        self.displayDownTotal = 0
        self.trafficHistoryUp = []
        self.trafficHistoryDown = []
        self.trafficHistoryUp.reserveCapacity(limit)
        self.trafficHistoryDown.reserveCapacity(limit)
    }

    func applyTrafficSnapshot(_ snapshot: TrafficSnapshot, isPanelPresented: Bool) {
        self.traffic = snapshot
        guard isPanelPresented else {
            if !self.trafficHistoryUp.isEmpty
                || !self.trafficHistoryDown.isEmpty
                || self.displayUpTotal != 0
                || self.displayDownTotal != 0
                || self.lastTrafficSampleAt != nil
            {
                self.resetPresentation()
            }
            return
        }
        self.appendTrafficHistory(up: snapshot.up, down: snapshot.down)
        self.updateTrafficTotals(from: snapshot)
    }

    func applyMemorySnapshot(_ snapshot: MemorySnapshot) {
        self.memory = snapshot
    }

    func appendTrafficHistory(up: Int64, down: Int64) {
        self.trafficHistoryUp.append(max(0, up))
        self.trafficHistoryDown.append(max(0, down))

        if self.trafficHistoryUp.count > self.historyMaxPoints {
            self.trafficHistoryUp.removeFirst(self.trafficHistoryUp.count - self.historyMaxPoints)
        }
        if self.trafficHistoryDown.count > self.historyMaxPoints {
            self.trafficHistoryDown.removeFirst(self.trafficHistoryDown.count - self.historyMaxPoints)
        }
    }

    func updateTrafficTotals(from snapshot: TrafficSnapshot) {
        if let upTotal = snapshot.upTotal, let downTotal = snapshot.downTotal {
            self.displayUpTotal = max(0, upTotal)
            self.displayDownTotal = max(0, downTotal)
            self.lastTrafficSampleAt = Date()
            return
        }

        let now = Date()
        if let last = self.lastTrafficSampleAt {
            let delta = max(0, now.timeIntervalSince(last))
            self.displayUpTotal += Int64(Double(max(0, snapshot.up)) * delta)
            self.displayDownTotal += Int64(Double(max(0, snapshot.down)) * delta)
        }
        self.lastTrafficSampleAt = now
    }

    /// Handles a standardized stream event directly
    func handleStreamEvent(_ event: MihomoStreamEvent, isPanelPresented: Bool) {
        switch event {
        case let .traffic(snapshot):
            self.applyTrafficSnapshot(snapshot, isPanelPresented: isPanelPresented)
        case let .memory(snapshot):
            self.applyMemorySnapshot(snapshot)
        default:
            break
        }
    }
}
