import Foundation
import MihomoKit

enum MachineConnectionStatus: Equatable {
    case unknown
    case checking
    case connected(version: String)
    case failed(reason: String)

    var isConnected: Bool {
        if case .connected = self {
            return true
        }
        return false
    }

    var shortLabel: String {
        switch self {
        case .unknown:
            "?"
        case .checking:
            "…"
        case let .connected(version):
            "✓ \(version)"
        case let .failed(reason):
            "✗ \(reason)"
        }
    }
}

@MainActor
final class RemoteMachineStore: ObservableObject {
    private static let storageKey = "clashbar.remote.machines"
    private static let activeTargetKey = "clashbar.remote.active_target_id"

    private let defaults: UserDefaults
    private let session: URLSession

    @Published var machines: [RemoteMachine] = []
    @Published var activeTargetID: UUID?
    @Published var machineStatuses: [UUID: MachineConnectionStatus] = [:]
    @Published var isSwitchingTarget: Bool = false

    /// Closure invoked when switching targets to reconfigure the session/runtime endpoint.
    var onSwitchTargetEndpoint: ((MachineTarget) async -> Void)?

    private struct Probe {
        let generation: Int
        let task: Task<MachineConnectionStatus, Never>
    }

    private var connectivityTimer: Task<Void, Never>?
    private var probes: [UUID: Probe] = [:]
    private var nextProbeGeneration = 0

    var activeTarget: MachineTarget {
        guard let id = self.activeTargetID,
              let machine = self.machines.first(where: { $0.id == id })
        else {
            return .local
        }
        return .remote(machine)
    }

    init(session: URLSession, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.session = session
        self.machines = Self.loadMachines(from: defaults)
        self.activeTargetID = Self.loadActiveTargetID(from: defaults)
    }

    deinit {
        connectivityTimer?.cancel()
        for probe in probes.values {
            probe.task.cancel()
        }
    }

    func addMachine(_ machine: RemoteMachine) {
        self.machines.append(machine)
        self.persist()
    }

    func updateMachine(_ machine: RemoteMachine) {
        guard let index = self.machines.firstIndex(where: { $0.id == machine.id }) else { return }
        self.cancelProbe(for: machine.id)
        self.machines[index] = machine
        self.machineStatuses[machine.id] = .unknown
        self.persist()
    }

    func removeMachine(id: UUID) {
        self.cancelProbe(for: id)
        self.machineStatuses.removeValue(forKey: id)
        self.machines.removeAll { $0.id == id }
        if self.activeTargetID == id {
            self.activeTargetID = nil
            self.persistActiveTarget()
        }
        self.persist()
    }

    func selectTarget(_ target: MachineTarget) {
        switch target {
        case .local:
            self.activeTargetID = nil
        case let .remote(machine):
            self.activeTargetID = machine.id
        }
        self.persistActiveTarget()
    }

    @discardableResult
    func switchToTarget(_ target: MachineTarget) async -> Bool {
        guard !self.isSwitchingTarget else { return false }
        self.isSwitchingTarget = true
        defer { self.isSwitchingTarget = false }

        if case let .remote(machine) = target {
            let status = await self.refreshConnectivity(for: machine)
            guard status.isConnected else { return false }
        }

        self.selectTarget(target)

        if let onSwitchTargetEndpoint {
            await onSwitchTargetEndpoint(target)
        }
        return true
    }

    func resetActiveTarget() {
        self.activeTargetID = nil
        self.persistActiveTarget()
    }

    func statusFor(_ id: UUID) -> MachineConnectionStatus {
        self.machineStatuses[id] ?? .unknown
    }

    func checkAllConnectivity() {
        for machine in self.machines {
            self.checkConnectivity(for: machine)
        }
    }

    func checkConnectivity(for machine: RemoteMachine) {
        _ = self.startProbe(for: machine)
    }

    @discardableResult
    func refreshConnectivity(for machine: RemoteMachine) async -> MachineConnectionStatus {
        await self.startProbe(for: machine).value
    }

    func startPeriodicConnectivityChecks() {
        self.stopPeriodicConnectivityChecks()
        self.checkAllConnectivity()
        self.connectivityTimer = Task { [weak self] in
            while !Task.isCancelled {
                guard await (try? Task.sleep(nanoseconds: 5_000_000_000)) != nil else { return }
                self?.checkAllConnectivity()
            }
        }
    }

    func stopPeriodicConnectivityChecks() {
        self.connectivityTimer?.cancel()
        self.connectivityTimer = nil
        for probe in self.probes.values {
            probe.task.cancel()
        }
        self.probes.removeAll()
    }

    private func startProbe(for machine: RemoteMachine) -> Task<MachineConnectionStatus, Never> {
        guard self.machines.contains(machine) else { return Task { .unknown } }

        self.cancelProbe(for: machine.id)
        self.nextProbeGeneration += 1
        let generation = self.nextProbeGeneration
        self.machineStatuses[machine.id] = .checking

        let session = self.session
        let task = Task { [weak self] in
            let status = await Self.probe(machine: machine, session: session)
            guard let self, !Task.isCancelled,
                  self.probes[machine.id]?.generation == generation,
                  self.machines.contains(machine)
            else { return status }

            if self.machineStatuses[machine.id] != status {
                self.machineStatuses[machine.id] = status
            }
            self.probes[machine.id] = nil
            return status
        }
        self.probes[machine.id] = Probe(generation: generation, task: task)
        return task
    }

    private func cancelProbe(for id: UUID) {
        self.probes.removeValue(forKey: id)?.task.cancel()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(self.machines) else { return }
        self.defaults.set(data, forKey: Self.storageKey)
    }

    private func persistActiveTarget() {
        if let id = self.activeTargetID {
            self.defaults.set(id.uuidString, forKey: Self.activeTargetKey)
        } else {
            self.defaults.removeObject(forKey: Self.activeTargetKey)
        }
    }

    private static func loadMachines(from defaults: UserDefaults) -> [RemoteMachine] {
        guard let data = defaults.data(forKey: storageKey),
              let machines = try? JSONDecoder().decode([RemoteMachine].self, from: data)
        else {
            return []
        }
        return machines
    }

    private static func loadActiveTargetID(from defaults: UserDefaults) -> UUID? {
        guard let string = defaults.string(forKey: activeTargetKey) else { return nil }
        return UUID(uuidString: string)
    }

    private static func probe(machine: RemoteMachine, session: URLSession) async -> MachineConnectionStatus {
        let api = MihomoAPIService(
            controller: machine.controllerAddress,
            secret: machine.secret,
            session: session)

        do {
            let versionInfo: VersionInfo = try await api.request(.version)
            return .connected(version: versionInfo.version.isEmpty ? "OK" : versionInfo.version)
        } catch is CancellationError {
            return .unknown
        } catch let APIError.statusCode(code, _) {
            if code == 401 {
                return .failed(reason: "Auth failed (401)")
            }
            return .failed(reason: "HTTP \(code)")
        } catch let error as URLError {
            switch error.code {
            case .cancelled:
                return .unknown
            case .timedOut:
                return .failed(reason: "Timeout")
            case .cannotConnectToHost:
                return .failed(reason: "Connection refused")
            case .networkConnectionLost:
                return .failed(reason: "Connection lost")
            default:
                return .failed(reason: error.localizedDescription)
            }
        } catch {
            return .failed(reason: error.localizedDescription)
        }
    }
}
