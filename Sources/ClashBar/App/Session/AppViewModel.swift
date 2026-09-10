import AppKit
import Combine
import Foundation
import MihomoKit
import OSLog
import SwiftUI

@MainActor
final class AppViewModel: ObservableObject {
    @Published var statusText: String = "Stopped" {
        didSet { self.refreshMenuBarDisplaySnapshotIfNeeded() }
    }

    @Published var version: String = "-"
    @Published var controller: String = "127.0.0.1:9090"
    @Published var externalControllerDisplay: String = "127.0.0.1:9090"
    var localExternalControllerDisplay: String = "127.0.0.1:9090"
    @Published var controllerUIURL: String =
        "https://metacubex.github.io/metacubexd/#/setup?http=true&hostname=127.0.0.1&port=9090&secret="
    @Published var controllerSecret: String?
    var hasConfiguredExternalUI = false
    var configuredExternalUIName: String?

    // Top-Level Feature Stores
    let trafficStore = TrafficStore()
    let connectionsStore = ConnectionsStore()
    let logsStore: LogsStore
    let proxyStore: ProxyStore
    let rulesStore = RulesStore()
    let configurationStore: ConfigurationStore
    let settingsStore: SettingsStore
    let remoteMachineStore: RemoteMachineStore

    @Published var logLevel: String = "info"
    @Published var port: Int?
    @Published var socksPort: Int?
    @Published var redirPort: Int?
    @Published var tproxyPort: Int?
    @Published var mixedPort: Int = 7890

    @Published var mihomoBinaryPath: String = "-"
    @Published var isPinned: Bool = false

    func togglePinned() {
        self.isPinned.toggle()
    }

    @Published var statusItemBanner: StatusItemBanner?

    @Published var apiStatus: APIHealth = .unknown {
        didSet { self.refreshMenuBarDisplaySnapshotIfNeeded() }
    }

    @Published var startupErrorMessage: String?
    @Published var coreActionState: CoreActionState = .idle
    @Published var coreUpgradeState: CoreUpgradeState = .idle
    @Published var geoUpdateState: GeoUpdateState = .idle
    @Published var uiLanguage: AppLanguage = .zhHans
    @Published var appearanceMode: AppAppearanceMode = .system
    @Published var isPanelPresented: Bool = false
    @Published var activeMenuTab: RootTab = .proxy
    @Published var launchAtLoginEnabled: Bool = false
    @Published var launchAtLoginErrorMessage: String?
    @Published var latestAppReleaseInfo: AppReleaseInfo?
    @Published private(set) var menuBarDisplaySnapshot = MenuBarDisplay(
        mode: .iconOnly,
        symbolName: "bolt.slash.circle",
        speedLines: nil,
        isRunning: false,
        isTunEnabled: false)

    var runtimeVisualStatus: RuntimeVisualStatus {
        MenuBarDisplayBuilder.resolveVisualStatus(
            statusText: self.statusText,
            isProcessRunning: self.processManager.isRunning,
            apiStatus: self.apiStatus)
    }

    var runtimeStatusText: String {
        switch self.runtimeVisualStatus {
        case .starting: self.tr("app.runtime.starting")
        case .runningHealthy, .runningDegraded: self.tr("app.runtime.running")
        case .failed: self.tr("app.runtime.failed")
        case .stopped: self.tr("app.runtime.stopped")
        }
    }

    var isExternalControllerWildcardIPv4: Bool {
        let host = self.controllerHost(from: self.externalControllerDisplay)
        return WebUIEndpointBuilder.isExternalControllerWildcardIPv4(host: host)
    }

    var isRuntimeRunning: Bool {
        self.processManager.isRunning || self.statusText.caseInsensitiveCompare("running") == .orderedSame
    }

    var menuBarSymbolName: String {
        MenuBarDisplayBuilder.symbolName(for: self.runtimeVisualStatus)
    }

    var statusBarDisplayMode: StatusBarDisplayMode {
        get { StatusBarDisplayMode(rawValue: self.statusBarDisplayModeRaw) ?? .iconOnly }
        set {
            guard self.statusBarDisplayModeRaw != newValue.rawValue else { return }
            self.statusBarDisplayModeRaw = newValue.rawValue
            self.refreshMenuBarDisplaySnapshotIfNeeded()
            self.updateDataAcquisitionPolicy()
            if newValue != .iconOnly {
                self.flushPendingTrafficSnapshotIfNeeded(immediately: true)
            }
        }
    }

    var menuBarSpeedLines: MenuBarSpeedLines {
        MenuBarDisplayBuilder.speedLines(
            up: self.trafficStore.traffic.up,
            down: self.trafficStore.traffic.down,
            isRunning: self.isRuntimeRunning)
    }

    func compactMenuBarRate(_ bytesPerSecond: Int64) -> String {
        MenuBarDisplayBuilder.compactMenuBarRate(bytesPerSecond)
    }

    func refreshMenuBarDisplaySnapshotIfNeeded() {
        let next = MenuBarDisplayBuilder.build(
            mode: self.statusBarDisplayMode,
            visualStatus: self.runtimeVisualStatus,
            isRunning: self.isRuntimeRunning,
            traffic: (up: self.trafficStore.traffic.up, down: self.trafficStore.traffic.down),
            isTunEnabled: self.settingsStore.editableSettings.tunEnabled)
        guard next != self.menuBarDisplaySnapshot else { return }
        self.menuBarDisplaySnapshot = next
    }

    var isRemoteTarget: Bool {
        !self.remoteMachineStore.activeTarget.isLocal
    }

    var isModeSwitchEnabled: Bool {
        (self.isRemoteTarget || self.processManager.isRunning) && self.apiStatus == .healthy
    }

    var isTunToggleEnabled: Bool {
        (self.isRemoteTarget || self.isRuntimeRunning) && !self.isCoreActionProcessing && !self.proxyStore.isTunSyncing
    }

    var isCoreActionProcessing: Bool {
        self.coreActionState != .idle
    }

    var primaryCoreActionLabel: String {
        if self.isCoreActionProcessing {
            return self.tr("app.primary.processing")
        }
        return self.isRuntimeRunning ? self.tr("app.primary.restart") : self.tr("app.primary.start")
    }

    var primaryCoreActionIconName: String {
        if self.isCoreActionProcessing {
            return "hourglass"
        }
        return self.isRuntimeRunning ? "arrow.clockwise" : "play.fill"
    }

    var isPrimaryCoreActionEnabled: Bool {
        !self.isCoreActionProcessing
    }

    var processManager: MihomoProcessManager {
        self.dependencies.processManager
    }

    var systemProxyService: SystemProxyService {
        self.dependencies.systemProxy
    }

    var tunPermissionService: TunPermissionService {
        self.dependencies.tunPermission
    }

    var launchAtLoginService: AppLaunchService {
        self.dependencies.launchAtLogin
    }

    var workingDirectoryManager: WorkingDirectoryManager {
        self.dependencies.workingDirectory
    }

    var networkReachabilityMonitor: NetworkReachabilityMonitor {
        self.dependencies.networkMonitor
    }

    var ssidMonitorService: SSIDMonitorService {
        self.dependencies.ssidMonitor
    }

    var clashbarLogStore: AppLogStore {
        self.dependencies.clashbarLogStore
    }

    var mihomoLogStore: AppLogStore {
        self.dependencies.mihomoLogStore
    }

    var apiClient: MihomoAPIService?

    let streams = StreamCoordinator()
    private var proxyStoreCancellable: AnyCancellable?

    var networkAutoStopTask: Task<Void, Never>?
    var networkAutoStartTask: Task<Void, Never>?
    var coreUpgradeFeedbackClearTask: Task<Void, Never>?
    var geoUpdateFeedbackClearTask: Task<Void, Never>?
    var trafficDecodeTask: Task<Void, Never>?
    var startupRefreshTask: Task<Void, Never>?
    var autoStartTask: Task<Void, Never>?
    var lastTrafficSampleAt: Date?
    var lastTrafficDecodeAt: Date = .distantPast
    var lastSavedSystemProxyExceptions: [String] = []
    var pendingTrafficPayload: Data?
    var modeSwitchInFlight = false

    var proxyProvidersAPIUnavailableLogged = false
    var lastAPIRefreshErrorFingerprint: String?
    var didStart = false
    var activatedTabRefreshGeneration: Int = 0
    var pendingConfigChangeRestart = false
    var isLatestAppReleaseCheckInFlight = false

    let defaults = UserDefaults.standard
    @AppStorage("clashbar.auto.start.core") var autoStartCore: Bool = false
    @AppStorage("clashbar.statusbar.display.mode") private var statusBarDisplayModeRaw: String = StatusBarDisplayMode
        .iconOnly.rawValue
    @AppStorage("clashbar.proxy.node.hide_unavailable") var hideUnavailableProxyNodes: Bool = false
    let editableSettingsSnapshotKey = "clashbar.settings.editable.snapshot.v1"
    let systemProxyEnabledOnQuitKey = "clashbar.system_proxy.enabled_on_quit"
    let systemProxyExceptionsKey = "clashbar.system_proxy.exceptions.v1"
    let uiLanguageKey = "clashbar.ui.language"
    let appearanceModeKey = "clashbar.ui.appearance.mode"

    let maxInMemoryLogEntries = 5000
    let hiddenPanelMaxInMemoryLogEntries = 20
    let historyMaxPoints = 60
    let trafficPublishIntervalNanoseconds: UInt64 = 500_000_000

    let defaultHealthcheckURL = "https://www.gstatic.com/generate_204"
    let defaultHealthcheckTimeoutMilliseconds = 5000
    var currentConnectionsStreamIntervalMilliseconds: Int?
    var currentLogsStreamLevel: String?
    var didAttemptAutoStart = false
    var lastCoreFailureAlertKey: String?
    var lastCoreFailureAlertAt: Date?
    let coreFailureAlertThrottleInterval: TimeInterval = 20
    var networkReachabilityStatus: NetworkReachabilityStatus = .unknown
    var shouldResumeCoreAfterNetworkRecovery = false
    var isNetworkReachabilityMonitoring = false
    var isSSIDStrategyMonitoring = false
    var pendingCoreFeatureRecoveryState: CoreFeatureRecoveryState?

    var externalControllerWarningKeys: Set<String> = []
    let streamJSONDecoder = JSONDecoder()
    let initialNoCoreSetupGuideShownKey = "clashbar.core.install.guide.shown.v1"
    let bundlesMihomoCore: Bool
    var didPresentInitialNoCoreSetupGuide = false

    let dependencies: AppDependencies

    convenience init() {
        self.init(dependencies: AppDependencies.production())
    }

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        let sharedSession = URLSessionFactory.makeEphemeralSession(maxConnectionsPerHost: 4)

        self.configurationStore = ConfigurationStore(workingDirectoryManager: dependencies.workingDirectory)
        self.logsStore = LogsStore(
            clashbarLogStore: dependencies.clashbarLogStore,
            mihomoLogStore: dependencies.mihomoLogStore)
        self.proxyStore = ProxyStore(
            systemProxyService: dependencies.systemProxy,
            tunPermissionService: dependencies.tunPermission)
        self.settingsStore = SettingsStore(defaults: dependencies.defaults)
        self.remoteMachineStore = RemoteMachineStore(session: sharedSession)
        self.bundlesMihomoCore = Self.resolveBundledMihomoCoreFlag()
        self.uiLanguage = loadPersistedUILanguage()
        self.appearanceMode = loadPersistedAppearanceMode()

        applyAppAppearance()
        configureStreamCoordinator()
        refreshLaunchAtLoginStatus()
        self.configureManagedProcessCallbacks()
        self.configureRemoteMachineCallbacks()
        self.bindStoreEvents()
    }

    private func configureRemoteMachineCallbacks() {
        self.remoteMachineStore.onSwitchTargetEndpoint = { [weak self] target in
            await self?.applyMachineTargetEndpoint(target)
        }
    }

    private func bindStoreEvents() {
        self.proxyStore.session = self
        self.proxyStoreCancellable = self.proxyStore.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.objectWillChange.send() }
        self.rulesStore
            .apiClientProvider = { [weak self] in try self?.clientOrThrow() ?? { throw APIError.clientUnavailable }() }
        self.connectionsStore
            .apiClientProvider = { [weak self] in try self?.clientOrThrow() ?? { throw APIError.clientUnavailable }() }
        self.settingsStore
            .apiClientProvider = { [weak self] in try self?.clientOrThrow() ?? { throw APIError.clientUnavailable }() }

        self.rulesStore.logHandler = { [weak self] level, message in self?.appendLog(level: level, message: message) }
        self.connectionsStore.logHandler = { [weak self] level, message in self?.appendLog(
            level: level,
            message: message) }
        self.settingsStore
            .logHandler = { [weak self] level, message in self?.appendLog(level: level, message: message) }
        self.configurationStore.logHandler = { [weak self] level, message in self?.appendLog(
            level: level,
            message: message) }

        self.configurationStore.onConfigSelected = { [weak self] _ in
            await self?.restartCore(trigger: .configSwitch)
        }
        self.configurationStore.onConfigRestartRequired = { [weak self] in
            await self?.restartCore(trigger: .configSwitch)
        }
        self.configurationStore.validateConfigBeforeSwitch = { [weak self] path in
            await self?.validateConfigBeforeCoreLaunch(configPath: path) ?? false
        }
        self.configurationStore.userAgentProvider = { [weak self] in
            await self?.remoteSubscriptionUserAgent() ?? "ClashBar"
        }

        self.ssidMonitorService.start { [weak self] snapshot in
            Task { @MainActor in
                self?.configurationStore.applySSIDStrategy(currentSSID: snapshot.currentSSID)
            }
        } errorHandler: { [weak self] error in
            Task { @MainActor in
                self?.appendLog(level: "error", message: "SSID monitor error: \(error.localizedDescription)")
            }
        }
    }

    isolated deinit {
        self.cancelOwnedTasks()
    }

    // MARK: - Core Coordination & Dispatching

    func clientOrThrow() throws -> MihomoAPIService {
        if self.apiClient == nil {
            self.ensureAPIClient()
        }
        guard let client = self.apiClient else {
            throw APIError.clientUnavailable
        }
        return client
    }

    func remoteSubscriptionUserAgent() async -> String {
        "clash.meta/\(self.version)"
    }

    func refreshSSIDStrategyState(requestAuthorizationIfNeeded: Bool = false) {
        if requestAuthorizationIfNeeded {
            self.ssidMonitorService.requestAuthorizationIfNeeded()
        } else {
            self.ssidMonitorService.refresh()
        }
    }

    func applySSIDStrategyForCurrentSSIDIfNeeded() async {
        guard self.configurationStore.ssidStrategyEnabled else { return }
        self.configurationStore.applySSIDStrategy(currentSSID: self.configurationStore.ssidStrategyCurrentSSID)
    }

    func refreshRemoteConfigMenuStates() {
        _ = self.configurationStore.reloadConfigs()
    }

    func startConfigDirectoryMonitoringIfNeeded() {
        self.configurationStore.startConfigMonitoring()
    }

    func stopConfigDirectoryMonitoring() {
        self.configurationStore.stopConfigMonitoring()
    }

    func showCoreDirectoryInFinder() {
        NSWorkspace.shared.open(self.workingDirectoryManager.coreDirectoryURL)
    }

    func handleSSIDStrategyAppDidBecomeActive() {
        if self.configurationStore.ssidStrategyEnabled {
            self.refreshSSIDStrategyState(requestAuthorizationIfNeeded: true)
        }
    }

    func scheduleSettingsFeedbackAutoClearIfNeeded(message: String) {
        self.settingsStore.scheduleSettingsFeedbackAutoClearIfNeeded(message: message)
    }

    func switchMode(to target: CoreMode) async {
        if !self.isModeSwitchEnabled || self.modeSwitchInFlight || target == self.settingsStore.editableSettings.mode {
            return
        }
        self.modeSwitchInFlight = true
        defer { self.modeSwitchInFlight = false }

        let previous = self.settingsStore.editableSettings.mode
        self.settingsStore.editableSettings.mode = target
        self.persistEditableSettingsSnapshot()

        do {
            try await self.clientOrThrow()
                .requestNoResponse(.patchConfigs(body: ["mode": .string(target.rawValue)]))
        } catch {
            self.settingsStore.editableSettings.mode = previous
            self.persistEditableSettingsSnapshot()
            self.appendLog(
                level: "error",
                message: self.tr(
                    "log.action.failed",
                    self.tr("log.action_name.switch_mode", target.rawValue),
                    error.localizedDescription))
        }
    }

    func appendLog(level: String, message: String) {
        self.logsStore.appendLog(level: level, message: message)
    }

    func appendMihomoLog(level: String, message: String) {
        self.logsStore.appendMihomoLog(level: level, message: message)
    }

    func appendLog(source: AppLogSource, level: String, message: String) {
        self.logsStore.appendLog(source: source, level: level, message: message)
    }

    func flushPendingMihomoLogsIfNeeded() {
        self.logsStore.flushPendingMihomoLogsIfNeeded()
    }

    func trimInMemoryLogsForCurrentVisibility() {
        self.logsStore.trimInMemoryLogsForCurrentVisibility(isPanelPresented: self.isPanelPresented)
    }

    func tr(_ key: String, _ args: CVarArg...) -> String {
        L10n.t(key, language: self.uiLanguage, args: args)
    }

    func tr(_ key: String) -> String {
        L10n.t(key, language: self.uiLanguage)
    }

    func copyTextToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func copyLocalProxyCommand() {
        self.copyProxyCommand(host: "127.0.0.1")
    }

    func copyManagedEndpointProxyCommand() {
        self.copyProxyCommand(host: self.managedEndpointProxyCommandHost())
    }

    func currentSystemProxyPortsFromState() -> SystemProxyPorts {
        SystemProxyPorts.resolve(
            mixedPort: self.mixedPort,
            httpPort: self.port,
            socksPort: self.socksPort)
    }

    func localProxyCommandTargetDisplay() -> String {
        let ports = self.currentSystemProxyPortsFromState()
        return self.buildSystemProxyDisplayString(host: "127.0.0.1", ports: ports) ?? "127.0.0.1"
    }

    func managedEndpointProxyCommandTargetDisplay() -> String {
        let ports = self.currentSystemProxyPortsFromState()
        let host = self.managedEndpointProxyCommandHost()
        return self.buildSystemProxyDisplayString(host: host, ports: ports) ?? host
    }

    func managedEndpointProxyCommandHostDisplay() -> String {
        self.managedEndpointProxyCommandHost()
    }

    private func copyProxyCommand(host: String) {
        let ports = self.currentSystemProxyPortsFromState()
        let httpPort = ports.httpPort ?? ports.socksPort ?? self.effectiveMixedPort()
        let socksPort = ports.socksPort ?? ports.httpPort ?? httpPort
        let script = TerminalProxyCommandBuilder.terminalProxyCommand(
            host: host,
            httpPort: httpPort,
            socksPort: socksPort)
        self.copyTextToPasteboard(script)
        self.appendLog(level: "info", message: self.tr("log.proxy_export.copied"))
        self.statusItemBanner = StatusItemBanner(
            symbolName: "doc.on.clipboard.fill",
            title: self.tr("ui.banner.copied.title"),
            primaryDetail: "\(host):\(httpPort)",
            secondaryDetail: nil)
    }

    func buildSystemProxyDisplayString(host: String, ports: SystemProxyPorts) -> String? {
        TerminalProxyCommandBuilder.buildSystemProxyDisplayString(host: host, ports: ports)
    }

    func controllerHost() -> String {
        guard let host = self.controllerHost(from: self.controller), !host.isEmpty else {
            return "127.0.0.1"
        }
        return host
    }

    private func managedEndpointProxyCommandHost() -> String {
        TerminalProxyCommandBuilder.managedEndpointProxyCommandHost(
            isRemoteTarget: self.isRemoteTarget,
            controllerHost: self.controllerHost(),
            configuredHost: self.controllerHost(from: self.localExternalControllerDisplay),
            allowLan: self.settingsStore.editableSettings.allowLan)
    }

    func effectiveMixedPort() -> Int {
        self.settingsStore.effectiveMixedPort()
    }

    func toggleSystemProxy(_ enabled: Bool) async {
        await self.proxyStore.toggleSystemProxy(enabled)
    }

    func openControllerWebUI() {
        guard let url = URL(string: self.controllerUIURL) else { return }
        _ = NSWorkspace.shared.open(url)
    }

    func makeControllerUIURL(
        _ controller: String,
        secret: String? = nil,
        hasConfiguredExternalUI: Bool? = nil,
        externalUIName: String? = nil) -> String
    {
        WebUIEndpointBuilder.makeControllerUIURL(
            controller: controller,
            secret: secret ?? self.controllerSecret,
            hasConfiguredExternalUI: hasConfiguredExternalUI ?? self.hasConfiguredExternalUI,
            externalUIName: externalUIName ?? self.configuredExternalUIName)
    }

    func refreshProvidersAndRules() async {
        await self.proxyStore.refreshProxyProviders()
        await self.rulesStore.reloadRulesAndProviders()
    }

    func resolvedMihomoBinaryPath() -> String? {
        if let detected = processManager.detectedBinaryPath,
           !detected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return detected
        }

        let current = self.mihomoBinaryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if current.isEmpty || current == "-" {
            return nil
        }
        return current
    }

    func handleApplicationDidBecomeActive() {
        self.refreshLaunchAtLoginStatus()
        self.handleSSIDStrategyAppDidBecomeActive()
        guard !self.isRemoteTarget, self.proxyStore.hasSystemProxyOpenIntent else { return }

        Task { [weak self] in
            guard let self else { return }

            let previousHealth = await self.systemProxyService.readHelperHealthSnapshot()
            await self.systemProxyService.warmUpHelperIfPossible()
            await self.proxyStore.refreshSystemProxyHelperStatus()

            let shouldRefreshProxyStatus = self.proxyStore.isSystemProxyEnabled
                || previousHealth.registrationState == .requiresApproval
                || previousHealth.failureReason == .backgroundActivityDisabled
                || previousHealth.failureReason == .helperNotRegistered

            if shouldRefreshProxyStatus {
                await self.proxyStore.refreshSystemProxyStatus()
            }
        }
    }
}
