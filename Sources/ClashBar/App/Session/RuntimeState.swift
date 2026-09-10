import Foundation
import MihomoKit

enum RuntimeVisualStatus {
    case stopped
    case starting
    case runningHealthy
    case runningDegraded
    case failed
}

enum StartTrigger {
    case manual
    case auto
    case networkRecovery
}

enum StopTrigger {
    case manual
    case networkLoss
}

enum CoreActionState {
    case idle
    case starting
    case stopping
    case restarting
}

enum CoreUpgradeState: Equatable {
    case idle
    case running
    case succeeded
    case alreadyLatest(version: String?)
    case failed(message: String)
}

enum GeoUpdateState: Equatable {
    case idle
    case updating
    case succeeded
    case failed(message: String)
}

struct CoreFeatureRecoveryState: Equatable {
    var systemProxyEnabled: Bool = false
    var tunEnabled: Bool = false

    var shouldRecoverAnyFeature: Bool {
        self.systemProxyEnabled || self.tunEnabled
    }

    mutating func merge(with other: CoreFeatureRecoveryState?) {
        guard let other else { return }
        self.systemProxyEnabled = self.systemProxyEnabled || other.systemProxyEnabled
        self.tunEnabled = self.tunEnabled || other.tunEnabled
    }
}
