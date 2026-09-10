import Foundation
import Network

enum NetworkReachabilityStatus: Equatable {
    case unknown
    case online
    case offline

    init(pathStatus: NWPath.Status) {
        if pathStatus == .satisfied {
            self = .online
        } else {
            self = .offline
        }
    }
}

final class NetworkReachabilityMonitor {
    typealias StatusHandler = @Sendable (NetworkReachabilityStatus) -> Void

    private let queue: DispatchQueue
    private var monitor: NWPathMonitor?

    init(queue: DispatchQueue = DispatchQueue(label: "com.clashbar.network-reachability", qos: .utility)) {
        self.queue = queue
    }

    deinit {
        self.stop()
    }

    func start(handler: @escaping StatusHandler) {
        self.stop()

        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in
            handler(NetworkReachabilityStatus(pathStatus: path.status))
        }
        monitor.start(queue: self.queue)
        self.monitor = monitor
    }

    func stop() {
        self.monitor?.cancel()
        self.monitor = nil
    }
}
