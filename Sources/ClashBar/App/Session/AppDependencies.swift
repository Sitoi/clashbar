import Foundation
import MihomoKit
import OSLog

/// Lightweight dependency container for the ClashBar application.
///
/// Replaces the ad-hoc closure-based wiring in `AppViewModel.bindStoreEvents()` with
/// a structured, testable dependency graph. All core services are created once at
/// app launch and injected through this container.
///
/// ## Production Usage
/// ```swift
/// let deps = AppDependencies.production()
/// let viewModel = AppViewModel(dependencies: deps)
/// ```
///
/// ## Testing / Preview Usage
/// ```swift
/// let deps = AppDependencies(
///     systemProxy: MockSystemProxyService(),
///     tunPermission: MockTunPermissionService(),
///     ...
/// )
/// ```
@MainActor
final class AppDependencies {
    /// System proxy management (enable/disable, exception list).
    let systemProxy: SystemProxyService

    /// TUN permission and helper tool management.
    let tunPermission: TunPermissionService

    /// Launch-at-login registration service.
    let launchAtLogin: AppLaunchService

    /// Network connectivity monitoring.
    let networkMonitor: NetworkReachabilityMonitor

    /// SSID-based strategy monitoring.
    let ssidMonitor: SSIDMonitorService

    /// Working directory and file system layout.
    let workingDirectory: WorkingDirectoryManager

    /// Core process lifecycle management.
    let processManager: MihomoProcessManager

    /// Application-level log store for ClashBar logs.
    let clashbarLogStore: AppLogStore

    /// Application-level log store for Mihomo core logs.
    let mihomoLogStore: AppLogStore

    /// User preferences storage.
    let defaults: UserDefaults

    init(
        systemProxy: SystemProxyService,
        tunPermission: TunPermissionService,
        launchAtLogin: AppLaunchService,
        networkMonitor: NetworkReachabilityMonitor,
        ssidMonitor: SSIDMonitorService,
        workingDirectory: WorkingDirectoryManager,
        processManager: MihomoProcessManager,
        clashbarLogStore: AppLogStore,
        mihomoLogStore: AppLogStore,
        defaults: UserDefaults = .standard)
    {
        self.systemProxy = systemProxy
        self.tunPermission = tunPermission
        self.launchAtLogin = launchAtLogin
        self.networkMonitor = networkMonitor
        self.ssidMonitor = ssidMonitor
        self.workingDirectory = workingDirectory
        self.processManager = processManager
        self.clashbarLogStore = clashbarLogStore
        self.mihomoLogStore = mihomoLogStore
        self.defaults = defaults
    }

    /// Creates a production dependency container with default implementations.
    static func production() -> AppDependencies {
        let workingDirectory = WorkingDirectoryManager()
        let clashbarLogStore = AppLogStore(
            logFileURL: workingDirectory.logsDirectoryURL.appendingPathComponent(
                "clashbar.log",
                isDirectory: false),
            logger: Logger.app)
        let mihomoLogStore = AppLogStore(
            logFileURL: workingDirectory.logsDirectoryURL.appendingPathComponent(
                "mihomo.log",
                isDirectory: false),
            logger: Logger.core)
        let processManager = MihomoProcessManager(
            configuration: MihomoProcessConfiguration(
                coreDirectoryURL: workingDirectory.coreDirectoryURL,
                managedBinaryURL: workingDirectory.managedMihomoBinaryURL,
                candidateBinaryRoots: AppResourceBundleLocator.candidateBinaryRoots(),
                bootstrapDirectories: { fm in
                    try workingDirectory.bootstrapDirectories(fileManager: fm)
                }))

        return AppDependencies(
            systemProxy: SystemProxyService(),
            tunPermission: TunPermissionService(),
            launchAtLogin: AppLaunchService(),
            networkMonitor: NetworkReachabilityMonitor(),
            ssidMonitor: SSIDMonitorService(),
            workingDirectory: workingDirectory,
            processManager: processManager,
            clashbarLogStore: clashbarLogStore,
            mihomoLogStore: mihomoLogStore)
    }

    /// Creates a mock dependency container suitable for testing and previews.
    static func mock(
        systemProxy: SystemProxyService = SystemProxyService(),
        tunPermission: TunPermissionService = TunPermissionService(),
        launchAtLogin: AppLaunchService = AppLaunchService(),
        networkMonitor: NetworkReachabilityMonitor = NetworkReachabilityMonitor(),
        ssidMonitor: SSIDMonitorService = SSIDMonitorService(),
        workingDirectory: WorkingDirectoryManager = WorkingDirectoryManager(),
        processManager: MihomoProcessManager? = nil,
        clashbarLogStore: AppLogStore? = nil,
        mihomoLogStore: AppLogStore? = nil,
        defaults: UserDefaults = .standard) -> AppDependencies
    {
        let workingDir = workingDirectory
        let cbLog = clashbarLogStore ?? AppLogStore(
            logFileURL: workingDir.logsDirectoryURL.appendingPathComponent("clashbar-mock.log", isDirectory: false),
            logger: Logger.app)
        let miLog = mihomoLogStore ?? AppLogStore(
            logFileURL: workingDir.logsDirectoryURL.appendingPathComponent("mihomo-mock.log", isDirectory: false),
            logger: Logger.core)
        let pm = processManager ?? MihomoProcessManager(
            configuration: MihomoProcessConfiguration(
                coreDirectoryURL: workingDir.coreDirectoryURL,
                managedBinaryURL: workingDir.managedMihomoBinaryURL,
                candidateBinaryRoots: [],
                bootstrapDirectories: { _ in }))

        return AppDependencies(
            systemProxy: systemProxy,
            tunPermission: tunPermission,
            launchAtLogin: launchAtLogin,
            networkMonitor: networkMonitor,
            ssidMonitor: ssidMonitor,
            workingDirectory: workingDir,
            processManager: pm,
            clashbarLogStore: cbLog,
            mihomoLogStore: miLog,
            defaults: defaults)
    }
}
