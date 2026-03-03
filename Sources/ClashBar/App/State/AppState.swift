import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var statusText: String = "Stopped" {
        didSet { self.refreshMenuBarDisplaySnapshotIfNeeded() }
    }

    @Published var version: String = "-"
    @Published var controller: String = "127.0.0.1:9090"
    @Published var controllerUIURL: String = "http://127.0.0.1:9090/ui"
    @Published var controllerSecret: String?

    @Published var traffic = TrafficSnapshot(up: 0, down: 0) {
        didSet { self.refreshMenuBarDisplaySnapshotIfNeeded() }
    }

    @Published var memory = MemorySnapshot(inuse: 0)
    @Published var displayUpTotal: Int64 = 0
    @Published var displayDownTotal: Int64 = 0
    @Published var trafficHistoryUp: [Int64] = []
    @Published var trafficHistoryDown: [Int64] = []

    @Published var connectionsCount: Int = 0
    @Published var connections: [ConnectionSummary] = []

    @Published var currentMode: CoreMode = .rule
    @Published var logLevel: String = "info"
    @Published var port: Int?
    @Published var socksPort: Int?
    @Published var redirPort: Int?
    @Published var tproxyPort: Int?
    @Published var mixedPort: Int = 7890

    @Published var mihomoBinaryPath: String = "-"
    @Published var selectedConfigName: String = "-"
    @Published var configDirectoryPath: String = "-"
    @Published var availableConfigFileNames: [String] = []

    @Published var proxyGroups: [ProxyGroup] = []
    @Published var groupLatencyLoading: Set<String> = []
    @Published var groupLatencies: [String: [String: Int]] = [:]
    @Published var proxyHistoryLatestDelay: [String: Int] = [:]

    @Published var providerProxyCount: Int = 0
    @Published var providerRuleCount: Int = 0
    @Published var rulesCount: Int = 0
    @Published var proxyProvidersDetail: [String: ProviderDetail] = [:]
    @Published var expandedProxyProviders: Set<String> = []
    @Published var providerNodeLatencies: [String: [String: Int]] = [:]
    @Published var providerNodeTesting: Set<ProviderNodeKey> = []
    @Published var providerBatchTesting: Set<String> = []
    @Published var providerUpdating: Set<String> = []
    @Published var ruleProviders: [String: ProviderDetail] = [:]
    @Published var ruleItems: [RuleItem] = []
    @Published var isRuleProvidersRefreshing: Bool = false

    @Published var isSystemProxyEnabled: Bool = false
    @Published var isProxySyncing: Bool = false
    @Published var isTunEnabled: Bool = false
    @Published var isTunSyncing: Bool = false

    @Published var apiStatus: APIHealth = .unknown {
        didSet { self.refreshMenuBarDisplaySnapshotIfNeeded() }
    }

    @Published var errorLogs: [AppErrorLogEntry] = []
    @Published var startupErrorMessage: String?
    @Published var coreActionState: CoreActionState = .idle
    @Published var providerRefreshStatus: ProviderRefreshStatus = .idle
    @Published var uiLanguage: AppLanguage = .zhHans
    @Published var appearanceMode: AppAppearanceMode = .system
    @Published var isPanelPresented: Bool = false
    @Published var activeMenuTab: MenuPanelTabHint = .proxy
    @Published var launchAtLoginEnabled: Bool = false
    @Published var launchAtLoginErrorMessage: String?
    @Published private(set) var menuBarDisplaySnapshot = MenuBarDisplay(
        mode: .iconOnly,
        symbolName: "bolt.slash.circle",
        speedLines: nil)

    @Published var settingsAllowLan: Bool = false {
        didSet { persistEditableSettingsSnapshot() }
    }

    @Published var settingsIPv6: Bool = false {
        didSet { persistEditableSettingsSnapshot() }
    }

    @Published var settingsUnifiedDelay: Bool = false {
        didSet { persistEditableSettingsSnapshot() }
    }

    @Published var settingsLogLevel: String = ConfigLogLevel.info
        .rawValue
    {
        didSet { persistEditableSettingsSnapshot() }
    }

    @Published var settingsPort: String = "0" {
        didSet { persistEditableSettingsSnapshot() }
    }

    @Published var settingsSocksPort: String = "0" {
        didSet { persistEditableSettingsSnapshot() }
    }

    @Published var settingsMixedPort: String = "7890" {
        didSet { persistEditableSettingsSnapshot() }
    }

    @Published var settingsRedirPort: String = "0" {
        didSet { persistEditableSettingsSnapshot() }
    }

    @Published var settingsTProxyPort: String = "0" {
        didSet { persistEditableSettingsSnapshot() }
    }

    @Published var settingsSyncingKey: String?
    @Published var settingsErrorMessage: String?
    @Published var settingsSavedMessage: String?
    var lastSyncedEditableSettings: EditableSettingsSnapshot?
    var preserveLocalSettingsOnNextSync = false
    var pendingConfigSwitchOverlaySettings: EditableSettingsSnapshot?
    var pendingAppLaunchOverlaySettings: EditableSettingsSnapshot?
    var suppressSettingsPersistence = false

    var runtimeVisualStatus: RuntimeVisualStatus {
        let normalized = self.statusText.lowercased()
        if normalized == "starting" { return .starting }
        if normalized == "failed" { return .failed }

        let running = self.processManager.isRunning || normalized == "running"
        if running {
            switch self.apiStatus {
            case .healthy:
                return .runningHealthy
            case .failed:
                return .failed
            case .degraded, .unknown:
                return .runningDegraded
            }
        }
        return .stopped
    }

    var runtimeStatusText: String {
        switch self.runtimeVisualStatus {
        case .starting: tr("app.runtime.starting")
        case .runningHealthy, .runningDegraded: tr("app.runtime.running")
        case .failed: tr("app.runtime.failed")
        case .stopped: tr("app.runtime.stopped")
        }
    }

    // DRY: unify "running" checks across AppState and extensions.
    var isRuntimeRunning: Bool {
        self.processManager.isRunning || self.statusText.caseInsensitiveCompare("running") == .orderedSame
    }

    var menuBarSymbolName: String {
        switch self.runtimeVisualStatus {
        case .runningHealthy:
            "bolt.horizontal.circle.fill"
        case .runningDegraded:
            "bolt.horizontal.circle"
        case .starting:
            "clock.arrow.circlepath"
        case .failed:
            "exclamationmark.triangle.fill"
        case .stopped:
            "bolt.slash.circle"
        }
    }

    var statusBarDisplayMode: StatusBarDisplayMode {
        get { StatusBarDisplayMode(rawValue: self.statusBarDisplayModeRaw) ?? .iconOnly }
        set {
            guard self.statusBarDisplayModeRaw != newValue.rawValue else { return }
            self.statusBarDisplayModeRaw = newValue.rawValue
            self.refreshMenuBarDisplaySnapshotIfNeeded()
        }
    }

    var menuBarSpeedLines: MenuBarSpeedLines {
        guard self.isRuntimeRunning else { return .zero }

        let up = self.compactMenuBarRate(max(0, self.traffic.up))
        let down = self.compactMenuBarRate(max(0, self.traffic.down))
        return MenuBarSpeedLines(up: "↑\(up)", down: "↓\(down)")
    }

    var menuBarDisplay: MenuBarDisplay {
        self.menuBarDisplaySnapshot
    }

    private var computedMenuBarDisplay: MenuBarDisplay {
        switch self.statusBarDisplayMode {
        case .iconOnly:
            MenuBarDisplay(mode: .iconOnly, symbolName: self.menuBarSymbolName, speedLines: nil)
        case .iconAndSpeed:
            MenuBarDisplay(mode: .iconAndSpeed, symbolName: self.menuBarSymbolName, speedLines: self.menuBarSpeedLines)
        case .speedOnly:
            MenuBarDisplay(mode: .speedOnly, symbolName: nil, speedLines: self.menuBarSpeedLines)
        }
    }

    func compactMenuBarRate(_ bytesPerSecond: Int64) -> String {
        var value = Double(max(0, bytesPerSecond))
        let units = ["B", "K", "M", "G", "T"]
        var unitIndex = 0

        while value >= 1000, unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }

        let integer = min(999, Int(value))
        return "\(integer)\(units[unitIndex])"
    }

    func refreshMenuBarDisplaySnapshotIfNeeded() {
        let next = self.computedMenuBarDisplay
        guard next != self.menuBarDisplaySnapshot else { return }
        self.menuBarDisplaySnapshot = next
    }

    var isModeSwitchEnabled: Bool {
        self.processManager.isRunning && self.apiStatus == .healthy
    }

    var isTunToggleEnabled: Bool {
        self.isRuntimeRunning && !self.isCoreActionProcessing && !self.isTunSyncing
    }

    var autoStartCoreEnabled: Bool {
        get { self.autoStartCore }
        set { self.autoStartCore = newValue }
    }

    var isCoreActionProcessing: Bool {
        self.coreActionState != .idle
    }

    var primaryCoreActionLabel: String {
        if self.isCoreActionProcessing { return tr("app.primary.processing") }
        return self.isRuntimeRunning ? tr("app.primary.restart") : tr("app.primary.start")
    }

    var primaryCoreActionIconName: String {
        if self.isCoreActionProcessing { return "hourglass" }
        return self.isRuntimeRunning ? "arrow.clockwise" : "play.fill"
    }

    var isPrimaryCoreActionEnabled: Bool {
        !self.isCoreActionProcessing
    }

    let processManager: any MihomoControlling
    let configManager: ConfigDirectoryManager
    let workingDirectoryManager: WorkingDirectoryManager
    let systemProxyService: SystemProxyService
    let tunPermissionService: TunPermissionService
    let tunConfigFileService: TunConfigFileService
    let configImportService: ConfigImportService
    let appLaunchService: AppLaunchService
    var apiClient: MihomoAPIClient?
    var modeSwitchTransportOverride: MihomoAPITransporting?
    var settingsPatchTransportOverride: MihomoAPITransporting?

    var mediumFrequencyTask: Task<Void, Never>?
    var lowFrequencyTask: Task<Void, Never>?
    var streamReceiveTasks: [StreamKind: Task<Void, Never>] = [:]
    var streamWebSocketTasks: [StreamKind: URLSessionWebSocketTask] = [:]
    var streamReconnectAttempts: [String: Int] = [:]
    var streamLastDisconnectLogAt: [String: Date] = [:]
    var streamLastDisconnectLogMessage: [String: String] = [:]
    var proxyPortsAutoSaveTask: Task<Void, Never>?
    var settingsFeedbackClearTask: Task<Void, Never>?
    var providerRefreshTask: Task<Void, Never>?
    var providerRefreshGeneration: Int = 0
    var lastTrafficSampleAt: Date?
    var modeSwitchInFlight = false

    let defaults = UserDefaults.standard
    @AppStorage("clashbar.auto.start.core") private var autoStartCore: Bool = false
    @AppStorage("clashbar.statusbar.display.mode") private var statusBarDisplayModeRaw: String = StatusBarDisplayMode
        .iconOnly.rawValue
    let selectedConfigKey = "clashbar.config.selected.filename"
    let legacySelectedConfigKey = "clashbar.config.selected"
    let remoteConfigSourcesKey = "clashbar.config.remote.sources.v1"
    let lastSuccessfulConfigPathKey = "clashbar.last.success.config.path"
    let editableSettingsSnapshotKey = "clashbar.settings.editable.snapshot.v1"
    let uiLanguageKey = "clashbar.ui.language"
    let appearanceModeKey = "clashbar.ui.appearance.mode"
    let maxLogEntries = 200
    let hiddenPanelMaxInMemoryLogEntries = 20
    let maxRetainedConnections = 300
    let historyMaxPoints = 60
    let foregroundMediumFrequencyIntervalNanoseconds: UInt64 = 4_000_000_000
    let backgroundMediumFrequencyIntervalNanoseconds: UInt64 = 12_000_000_000
    let foregroundLowFrequencyPrimaryTabsIntervalNanoseconds: UInt64 = 20_000_000_000
    let foregroundLowFrequencyOtherTabsIntervalNanoseconds: UInt64 = 45_000_000_000
    let backgroundLowFrequencyIntervalNanoseconds: UInt64 = 120_000_000_000
    let streamDisconnectLogThrottleInterval: TimeInterval = 2
    let streamReconnectBaseDelayNanoseconds: UInt64 = 1_000_000_000
    let streamReconnectMaxDelayNanoseconds: UInt64 = 8_000_000_000
    // DRY: shared defaults for latency/provider healthcheck endpoints.
    let defaultHealthcheckURL = "https://www.gstatic.com/generate_204"
    let defaultHealthcheckTimeoutMilliseconds = 5000
    var mediumFrequencyIntervalNanoseconds: UInt64 = 4_000_000_000
    var lowFrequencyIntervalNanoseconds: UInt64 = 20_000_000_000
    var currentConnectionsStreamIntervalMilliseconds: Int?
    var clashbarLogFileURL: URL?
    var mihomoLogFileURL: URL?
    var clashbarLogStore: AppLogStore?
    var mihomoLogStore: AppLogStore?
    var didAttemptAutoStart = false
    var didCheckSystemProxyConsistencyOnLaunch = false
    var remoteConfigSources: [String: String] = [:]
    var externalControllerWarningKeys: Set<String> = []
    let streamJSONDecoder = JSONDecoder()

    init(
        processManager: (any MihomoControlling)? = nil,
        configManager: ConfigDirectoryManager? = nil,
        workingDirectoryManager: WorkingDirectoryManager = WorkingDirectoryManager(),
        systemProxyService: SystemProxyService = SystemProxyService(),
        tunPermissionService: TunPermissionService = TunPermissionService(),
        tunConfigFileService: TunConfigFileService = TunConfigFileService(),
        configImportService: ConfigImportService = ConfigImportService(),
        appLaunchService: AppLaunchService = AppLaunchService(),
        clashbarLogStore: AppLogStore? = nil,
        mihomoLogStore: AppLogStore? = nil,
        startBackgroundRefresh: Bool = true)
    {
        self.processManager = processManager ?? MihomoProcessManager()
        self.workingDirectoryManager = workingDirectoryManager
        self.systemProxyService = systemProxyService
        self.tunPermissionService = tunPermissionService
        self.tunConfigFileService = tunConfigFileService
        self.configImportService = configImportService
        self.appLaunchService = appLaunchService
        self.clashbarLogStore = clashbarLogStore
        self.mihomoLogStore = mihomoLogStore
        self.configManager = configManager ?? ConfigDirectoryManager(workingDirectoryManager: workingDirectoryManager)
        self.uiLanguage = loadPersistedUILanguage()
        self.appearanceMode = loadPersistedAppearanceMode()
        applyAppAppearance()
        refreshLaunchAtLoginStatus()

        self.mihomoBinaryPath = self.processManager.detectedBinaryPath ?? "-"
        if let managedProcess = self.processManager as? MihomoProcessManager {
            managedProcess.onLog = { [weak self] line in
                Task { @MainActor in
                    self?.appendMihomoLog(level: "info", message: line)
                }
            }
            managedProcess.onTermination = { [weak self] code in
                Task { @MainActor in
                    self?.statusText = "Failed"
                    self?.apiStatus = .failed
                    self?.resetTrafficPresentation()
                    self?.appendLog(level: "error", message: self?.tr("log.process.terminated", code) ?? "")
                    self?.cancelPolling()
                }
            }
        }
        do {
            try self.workingDirectoryManager.bootstrapDirectories()
            clashbarLogFileURL = self.workingDirectoryManager.logsDirectoryURL.appendingPathComponent(
                "clashbar.log",
                isDirectory: false)
            mihomoLogFileURL = self.workingDirectoryManager.logsDirectoryURL.appendingPathComponent(
                "mihomo.log",
                isDirectory: false)

            if let clashbarLogFileURL, self.clashbarLogStore == nil {
                self.clashbarLogStore = AppLogStore(logFileURL: clashbarLogFileURL)
            }
            if let mihomoLogFileURL, self.mihomoLogStore == nil {
                self.mihomoLogStore = AppLogStore(logFileURL: mihomoLogFileURL)
            }
            ensureLogFileExists()
            seedBundledConfigIfNeeded()
        } catch {
            appendLog(level: "error", message: tr("log.working_dir_init_failed", error.localizedDescription))
        }
        restoreSavedConfigDirectory()
        restoreLastSuccessfulConfigIfAvailable()
        self.remoteConfigSources = loadPersistedRemoteConfigSources()
        pruneRemoteConfigSourcesIfNeeded()
        self.controllerUIURL = makeControllerUIURL(self.controller)
        if let persisted = loadPersistedEditableSettingsSnapshot() {
            applyEditableSettingsSnapshotToUI(persisted)
            self.preserveLocalSettingsOnNextSync = true
            self.pendingAppLaunchOverlaySettings = persisted
        }

        if startBackgroundRefresh {
            Task {
                await refreshFromAPI(includeSlowCalls: true)
                await applyPendingAppLaunchSettingsOverlayIfNeeded()
                await refreshSystemProxyStatus()
                await ensureSystemProxyConsistencyOnFirstLaunchIfNeeded()
            }
        }
        if startBackgroundRefresh, self.autoStartCore {
            Task { [weak self] in
                await self?.attemptAutoStartIfNeeded()
            }
        }

        self.refreshMenuBarDisplaySnapshotIfNeeded()
    }

    deinit {
        mediumFrequencyTask?.cancel()
        lowFrequencyTask?.cancel()
        for task in streamReceiveTasks.values {
            task.cancel()
        }
        for webSocketTask in streamWebSocketTasks.values {
            webSocketTask.cancel(with: .goingAway, reason: nil)
        }
        providerRefreshTask?.cancel()
    }
}
