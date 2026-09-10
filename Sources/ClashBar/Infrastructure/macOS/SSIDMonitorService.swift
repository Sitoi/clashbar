import CoreLocation
import CoreWLAN
import Foundation

enum SSIDMonitorAuthorizationStatus: Equatable {
    case notDetermined
    case denied
    case restricted
    case authorized
    case servicesDisabled
}

struct SSIDMonitorSnapshot: Equatable {
    let currentSSID: String?
    let authorizationStatus: SSIDMonitorAuthorizationStatus
}

enum SSIDMonitorServiceError: LocalizedError {
    case missingLocationUsageDescription

    var errorDescription: String? {
        switch self {
        case .missingLocationUsageDescription:
            "Missing NSLocationWhenInUseUsageDescription in the app bundle."
        }
    }
}

final class SSIDMonitorService: NSObject {
    typealias SnapshotHandler = @Sendable (SSIDMonitorSnapshot) -> Void
    typealias ErrorHandler = @Sendable (Error) -> Void

    private static let monitoredEventTypes: [CWEventType] = [.ssidDidChange, .linkDidChange]
    private static let locationUsageDescriptionKey = "NSLocationWhenInUseUsageDescription"

    private var wifiClient: CWWiFiClient
    private let locationManager: CLLocationManager

    private var snapshotHandler: SnapshotHandler?
    private var errorHandler: ErrorHandler?
    private var isStarted = false
    private var monitoredEventTypesStarted: Set<CWEventType> = []

    init(
        wifiClient: CWWiFiClient = CWWiFiClient(),
        locationManager: CLLocationManager = CLLocationManager())
    {
        self.wifiClient = wifiClient
        self.locationManager = locationManager
        super.init()
    }

    deinit {
        self.stop()
    }

    func start(snapshotHandler: @escaping SnapshotHandler, errorHandler: @escaping ErrorHandler) {
        self.snapshotHandler = snapshotHandler
        self.errorHandler = errorHandler
        guard !self.isStarted else {
            self.emitCurrentSnapshot()
            return
        }

        self.isStarted = true
        self.locationManager.delegate = self
        self.wifiClient.delegate = self
        self.startMonitoringEventsIfNeeded()
        self.emitCurrentSnapshot()
    }

    func stop() {
        guard self.isStarted else { return }
        self.isStarted = false
        self.monitoredEventTypesStarted.removeAll()

        try? self.wifiClient.stopMonitoringAllEvents()
        self.wifiClient.delegate = nil
        self.locationManager.delegate = nil
        self.snapshotHandler = nil
        self.errorHandler = nil
    }

    func refresh() {
        self.startMonitoringEventsIfNeeded()
        self.emitCurrentSnapshot()
    }

    func requestAuthorizationIfNeeded() {
        self.startMonitoringEventsIfNeeded()

        guard CLLocationManager.locationServicesEnabled() else {
            self.emitCurrentSnapshot()
            return
        }

        if self.locationManager.authorizationStatus == .notDetermined {
            guard self.hasLocationUsageDescription() else {
                self.errorHandler?(SSIDMonitorServiceError.missingLocationUsageDescription)
                self.emitCurrentSnapshot()
                return
            }
            self.locationManager.requestWhenInUseAuthorization()
            return
        }

        self.emitCurrentSnapshot()
    }

    private func startMonitoringEventsIfNeeded() {
        for eventType in Self.monitoredEventTypes where !self.monitoredEventTypesStarted.contains(eventType) {
            do {
                try self.wifiClient.startMonitoringEvent(with: eventType)
                self.monitoredEventTypesStarted.insert(eventType)
            } catch {
                self.errorHandler?(error)
            }
        }
    }

    private func emitCurrentSnapshot() {
        self.snapshotHandler?(self.makeSnapshot())
    }

    private func makeSnapshot() -> SSIDMonitorSnapshot {
        let authorizationStatus = self.currentAuthorizationStatus()
        let currentSSID: String? = if authorizationStatus == .authorized {
            self.currentSSID()
        } else {
            nil
        }

        return SSIDMonitorSnapshot(
            currentSSID: currentSSID?.trimmedNonEmpty,
            authorizationStatus: authorizationStatus)
    }

    private func currentAuthorizationStatus() -> SSIDMonitorAuthorizationStatus {
        guard CLLocationManager.locationServicesEnabled() else {
            return .servicesDisabled
        }

        return switch self.locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            .authorized
        case .denied:
            .denied
        case .restricted:
            .restricted
        case .notDetermined:
            .notDetermined
        @unknown default:
            .denied
        }
    }

    private func currentSSID() -> String? {
        if let ssid = self.wifiClient.interface()?.ssid()?.trimmedNonEmpty {
            return ssid
        }

        for name in self.wifiClient.interfaceNames() ?? [] {
            if let ssid = self.wifiClient.interface(withName: name)?.ssid()?.trimmedNonEmpty {
                return ssid
            }
        }

        return nil
    }

    private func hasLocationUsageDescription() -> Bool {
        guard let value = Bundle.main.object(forInfoDictionaryKey: Self.locationUsageDescriptionKey) as? String else {
            return false
        }

        return value.trimmedNonEmpty != nil
    }
}

extension SSIDMonitorService: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        self.emitCurrentSnapshot()
    }
}

extension SSIDMonitorService: CWEventDelegate {
    func clientConnectionInterrupted() {
        self.emitCurrentSnapshot()
    }

    func clientConnectionInvalidated() {
        self.wifiClient.delegate = nil
        self.monitoredEventTypesStarted.removeAll()
        self.wifiClient = CWWiFiClient()
        self.wifiClient.delegate = self
        self.startMonitoringEventsIfNeeded()
        self.emitCurrentSnapshot()
    }

    func ssidDidChangeForWiFiInterface(withName interfaceName: String) {
        self.emitCurrentSnapshot()
    }

    func linkDidChangeForWiFiInterface(withName interfaceName: String) {
        self.emitCurrentSnapshot()
    }
}
