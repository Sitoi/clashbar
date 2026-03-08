import SwiftUI

enum RootTab: String, CaseIterable, Hashable {
    case proxy
    case rules
    case activity
    case logs
    case system

    var titleKey: String {
        switch self {
        case .proxy: "ui.tab.proxy"
        case .rules: "ui.tab.rules"
        case .activity: "ui.tab.activity"
        case .logs: "ui.tab.logs"
        case .system: "ui.tab.system"
        }
    }
}

enum LogLevelFilter: Hashable, CaseIterable {
    case info
    case warning
    case error

    var titleKey: String {
        switch self {
        case .info: "ui.log_filter.info"
        case .warning: "ui.log_filter.warning"
        case .error: "ui.log_filter.error"
        }
    }
}

enum NetworkTransportFilter: String, CaseIterable, Identifiable {
    case all
    case tcp
    case udp
    case other

    var id: String {
        rawValue
    }

    var titleKey: String {
        switch self {
        case .all:
            "ui.network.filter.transport.all"
        case .tcp:
            "ui.network.filter.transport.tcp"
        case .udp:
            "ui.network.filter.transport.udp"
        case .other:
            "ui.network.filter.transport.other"
        }
    }

    func matches(_ network: String?) -> Bool {
        let normalized = network.trimmedOrEmpty.lowercased()

        switch self {
        case .all:
            return true
        case .tcp:
            return normalized == "tcp"
        case .udp:
            return normalized == "udp"
        case .other:
            return !normalized.isEmpty && normalized != "tcp" && normalized != "udp"
        }
    }
}

enum NetworkSortOption: String, CaseIterable, Identifiable {
    case `default`
    case newest
    case oldest
    case uploadDesc
    case downloadDesc
    case totalDesc

    var id: String {
        rawValue
    }

    var titleKey: String {
        switch self {
        case .default:
            "ui.network.sort.default"
        case .newest:
            "ui.network.sort.newest"
        case .oldest:
            "ui.network.sort.oldest"
        case .uploadDesc:
            "ui.network.sort.upload_desc"
        case .downloadDesc:
            "ui.network.sort.download_desc"
        case .totalDesc:
            "ui.network.sort.total_desc"
        }
    }
}

private struct ActivityRefreshToken: Equatable {
    let connections: [ConnectionSummary]
    let keyword: String
    let transport: NetworkTransportFilter
    let sort: NetworkSortOption
}

private struct LogsRefreshToken: Equatable {
    let logs: [AppErrorLogEntry]
    let sources: Set<AppLogSource>
    let levels: Set<LogLevelFilter>
    let keyword: String
}

private struct RulesRefreshToken: Equatable {
    let items: [RuleItem]
    let providers: [String: ProviderDetail]
}

struct MenuBarRoot: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var popoverLayoutModel: PopoverLayoutModel
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.panelMeasurementMode) var panelMeasurementMode

    @State var currentTab: RootTab = .proxy
    @State var switchingMode: CoreMode?
    @State var hoveringCopyRow = false
    @State var hoveredRuleIndex: Int?
    @State var networkFilterText: String = ""
    @State var networkTransportFilter: NetworkTransportFilter = .all
    @State var networkSortOption: NetworkSortOption = .default
    @State var hoveredConnectionID: String?
    @State var hoveredProxyGroupName: String?
    @State var hoveredProxyProviderName: String?
    @State var hoveredMode: CoreMode?
    @State var selectedLogSources: Set<AppLogSource> = Set(AppLogSource.allCases)
    @State var selectedLogLevels: Set<LogLevelFilter> = [.info, .warning, .error]
    @State var logSearchText: String = ""
    @State var topHeaderHeight: CGFloat = 0
    @State var modeAndTabSectionHeight: CGFloat = 0
    @State var footerBarHeight: CGFloat = 0
    @State var currentTabContentHeight: CGFloat = 0
    @State var visibleConnections: [ConnectionSummary] = []
    @State var visibleLogs: [AppErrorLogEntry] = []
    @State var visibleRules: [RuleItem] = []
    @State var ruleProviderLookup: [String: ProviderDetail] = [:]
    @AppStorage("clashbar.proxy.group.hide_hidden") var hideHiddenProxyGroups: Bool = true

    var contentWidth: CGFloat {
        MenuBarLayoutTokens.panelWidth - (MenuBarLayoutTokens.hPage * 2)
    }

    var language: AppLanguage {
        self.appState.uiLanguage
    }

    func tr(_ key: String) -> String {
        L10n.t(key, language: self.language)
    }

    func tr(_ key: String, _ args: CVarArg...) -> String {
        L10n.t(key, language: self.language, args: args)
    }

    func setCurrentTabWithoutAnimation(_ tab: RootTab) {
        guard self.currentTab != tab else { return }

        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            self.currentTab = tab
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            self.panelContent
            Spacer(minLength: 0)
        }
        .frame(width: MenuBarLayoutTokens.panelWidth, alignment: .topLeading)
        .overlay(alignment: .topLeading) {
            if !self.panelMeasurementMode {
                self.currentTabMeasurementLayer
            }
        }
    }

    var panelContent: some View {
        VStack(spacing: 0) {
            topHeader
                .frame(maxWidth: .infinity, alignment: .leading)
                .reportHeight { updateSectionHeight($0, target: .header) }

            modeAndTabSection
                .frame(maxWidth: .infinity, alignment: .leading)
                .reportHeight { updateSectionHeight($0, target: .modeAndTab) }

            ScrollView(.vertical) {
                self.tabContent(for: self.currentTab)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: tabScrollAreaHeight, alignment: .top)

            footerBar
                .padding(.top, MenuBarLayoutTokens.sectionGap)
                .frame(maxWidth: .infinity, alignment: .leading)
                .reportHeight { updateSectionHeight($0, target: .footer) }
        }
        .frame(width: self.contentWidth, alignment: .topLeading)
        .padding(.horizontal, MenuBarLayoutTokens.hPage)
        .frame(width: MenuBarLayoutTokens.panelWidth, height: resolvedPanelHeight, alignment: .topLeading)
        .background(self.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: MenuBarLayoutTokens.panelCornerRadius, style: .continuous))
        .onAppear {
            self.setCurrentTabWithoutAnimation(self.appState.activeMenuTab)
            self.appState.setActiveMenuTab(self.currentTab)
            self.refreshDerivedData(for: self.currentTab)
            publishPreferredPanelHeight()
        }
        .onChange(of: self.currentTab) { tab in
            self.currentTabContentHeight = 0
            self.appState.setActiveMenuTab(tab)
            self.refreshDerivedData(for: tab)
        }
        .onChange(of: self.appState.activeMenuTab) { tab in
            guard self.currentTab != tab else { return }
            self.setCurrentTabWithoutAnimation(tab)
            self.currentTabContentHeight = 0
            self.refreshDerivedData(for: tab)
        }
        .onChange(of: resolvedPanelHeight) { _ in
            publishPreferredPanelHeight()
        }
        .onChange(of: self.popoverLayoutModel.maxPanelHeight) { _ in
            publishPreferredPanelHeight()
        }
        .onChange(of: ActivityRefreshToken(
            connections: self.appState.connections,
            keyword: self.networkFilterText,
            transport: self.networkTransportFilter,
            sort: self.networkSortOption)) { _ in
            self.refreshActivityDerivedDataIfVisible()
        }
        .onChange(of: LogsRefreshToken(
            logs: self.appState.errorLogs,
            sources: self.selectedLogSources,
            levels: self.selectedLogLevels,
            keyword: self.logSearchText)) { _ in
            self.refreshLogsDerivedDataIfVisible()
        }
        .onChange(of: RulesRefreshToken(
            items: self.appState.ruleItems,
            providers: self.appState.ruleProviders)) { _ in
            self.refreshRulesDerivedDataIfVisible()
        }
    }

    @ViewBuilder
    func tabBody(for tab: RootTab) -> some View {
        switch tab {
        case .proxy:
            proxyTabBody
        case .rules:
            rulesTabBody
        case .activity:
            activityTabBody
        case .logs:
            logsTabBody
        case .system:
            systemTabBody
        }
    }

    func tabContent(for tab: RootTab) -> some View {
        self.tabBody(for: tab)
            .padding(.top, MenuBarLayoutTokens.vDense)
            .fixedSize(horizontal: false, vertical: true)
    }

    var currentTabMeasurementLayer: some View {
        let measuredTab = self.currentTab

        return self.tabContent(for: measuredTab)
            .frame(width: self.contentWidth, alignment: .topLeading)
            .reportHeight { updateCurrentTabContentHeight($0, for: measuredTab) }
            .hidden()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .environment(\.panelMeasurementMode, true)
            .id(measuredTab)
    }

    var panelBackground: some View {
        RoundedRectangle(cornerRadius: MenuBarLayoutTokens.panelCornerRadius, style: .continuous)
            .fill(.regularMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: MenuBarLayoutTokens.panelCornerRadius, style: .continuous)
                    .stroke(nativeSeparator, lineWidth: 0.8)
            }
            .shadow(color: Color(nsColor: .shadowColor).opacity(0.28), radius: 18, x: 0, y: 10)
    }

    func refreshDerivedData(for tab: RootTab) {
        switch tab {
        case .proxy, .system:
            return
        case .rules:
            self.refreshVisibleRules()
        case .activity:
            self.refreshVisibleConnections()
        case .logs:
            self.refreshVisibleLogs()
        }
    }

    func refreshActivityDerivedDataIfVisible() {
        guard self.currentTab == .activity else { return }
        self.refreshVisibleConnections()
    }

    func refreshLogsDerivedDataIfVisible() {
        guard self.currentTab == .logs else { return }
        self.refreshVisibleLogs()
    }

    func refreshRulesDerivedDataIfVisible() {
        guard self.currentTab == .rules else { return }
        self.refreshVisibleRules()
    }
}
