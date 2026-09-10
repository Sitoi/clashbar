import Foundation
import MihomoKit

@MainActor
extension AppViewModel {
    func enforceNetworkManagedCorePolicyIfNeeded() {
        if self.networkReachabilityStatus == .offline {
            self.scheduleAutoStopForNetworkLossIfNeeded()
        }
    }

    func updateNetworkReachabilityMonitoringState() {
        self.startNetworkReachabilityMonitoringIfNeeded()
        self.enforceNetworkManagedCorePolicyIfNeeded()
    }

    private func startNetworkReachabilityMonitoringIfNeeded() {
        guard !self.isNetworkReachabilityMonitoring else { return }
        self.isNetworkReachabilityMonitoring = true

        self.networkReachabilityMonitor.start { [weak self] status in
            Task { @MainActor in
                self?.handleNetworkReachabilityStatus(status)
            }
        }
    }

    func stopNetworkReachabilityMonitoring() {
        self.networkAutoStopTask?.cancel()
        self.networkAutoStopTask = nil
        self.networkAutoStartTask?.cancel()
        self.networkAutoStartTask = nil

        if self.isNetworkReachabilityMonitoring {
            self.networkReachabilityMonitor.stop()
            self.isNetworkReachabilityMonitoring = false
        }

        self.networkReachabilityStatus = .unknown
        self.shouldResumeCoreAfterNetworkRecovery = false
    }

    private func handleNetworkReachabilityStatus(_ status: NetworkReachabilityStatus) {
        let previous = self.networkReachabilityStatus
        self.networkReachabilityStatus = status

        guard previous != status else { return }

        switch status {
        case .unknown:
            break
        case .offline:
            self.scheduleAutoStopForNetworkLossIfNeeded()
        case .online:
            self.scheduleAutoStartForNetworkRecoveryIfNeeded()
        }
    }

    private func scheduleAutoStopForNetworkLossIfNeeded() {
        guard !self.isRemoteTarget else { return }
        self.networkAutoStartTask?.cancel()
        self.networkAutoStartTask = nil

        self.networkAutoStopTask?.cancel()
        self.networkAutoStopTask = Task { [weak self] in
            guard let self else { return }
            var didLog = false

            self.cancelPolling()

            for _ in 0..<120 {
                if Task.isCancelled {
                    return
                }
                guard self.networkReachabilityStatus == .offline else { return }
                guard self.isRuntimeRunning else { return }

                self.shouldResumeCoreAfterNetworkRecovery = true
                if self.isCoreActionProcessing {
                    do {
                        try await Task.sleep(nanoseconds: 250_000_000)
                    } catch {
                        return
                    }
                    continue
                }

                if !didLog {
                    didLog = true
                    self.appendLog(
                        level: "warning", message: self.tr("log.network.offline_auto_stop"))
                }
                await self.stopCore(trigger: .networkLoss)

                do {
                    try await Task.sleep(nanoseconds: 250_000_000)
                } catch {
                    return
                }
            }
        }
    }

    private func scheduleAutoStartForNetworkRecoveryIfNeeded() {
        guard !self.isRemoteTarget else { return }
        self.networkAutoStopTask?.cancel()
        self.networkAutoStopTask = nil

        self.networkAutoStartTask?.cancel()
        self.networkAutoStartTask = Task { [weak self] in
            guard let self else { return }
            var didLog = false

            for _ in 0..<120 {
                if Task.isCancelled {
                    return
                }
                guard self.networkReachabilityStatus == .online else { return }
                guard self.shouldResumeCoreAfterNetworkRecovery else { return }

                if self.isCoreActionProcessing {
                    do {
                        try await Task.sleep(nanoseconds: 250_000_000)
                    } catch {
                        return
                    }
                    continue
                }

                if self.isRuntimeRunning {
                    if self.pendingCoreFeatureRecoveryState?.shouldRecoverAnyFeature == true {
                        await self.restoreCoreFeaturesAfterStartupIfNeeded()
                    }
                    self.shouldResumeCoreAfterNetworkRecovery = false
                    return
                }

                self.shouldResumeCoreAfterNetworkRecovery = false
                if !didLog {
                    didLog = true
                    self.appendLog(level: "info", message: self.tr("log.network.online_auto_start"))
                }
                await self.startCore(trigger: .networkRecovery)
                if self.isRuntimeRunning {
                    return
                }

                self.shouldResumeCoreAfterNetworkRecovery = true
                do {
                    try await Task.sleep(nanoseconds: 500_000_000)
                } catch {
                    return
                }
            }
        }
    }
}
