import SwiftUI

enum RootTab: String, CaseIterable, Hashable {
    case proxy
    case rules
    case connections
    case logs
    case system

    var titleKey: String {
        switch self {
        case .proxy: "ui.tab.proxy"
        case .rules: "ui.tab.rules"
        case .connections: "ui.tab.connections"
        case .logs: "ui.tab.logs"
        case .system: "ui.tab.system"
        }
    }

    var symbolName: String {
        switch self {
        case .proxy: "square.grid.2x2.fill"
        case .rules: "arrow.left.arrow.right"
        case .connections: "link"
        case .logs: "doc.fill"
        case .system: "gearshape.fill"
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

private struct ConnectionsRefreshToken: Equatable {
    let connections: [ConnectionSummary]
    let keyword: String
    let transport: ConnectionsTransportFilter
    let sort: ConnectionsSortOption
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

struct MenuBarRootView: View {
    @EnvironmentObject var appSession: AppSession
    @EnvironmentObject var connectionsStore: ConnectionsStore
    @EnvironmentObject var popoverLayoutModel: PopoverLayoutModel
    @Environment(\.colorScheme) var colorScheme

    @StateObject var rootViewModel = MenuBarRootViewModel()
    @StateObject var connectionsViewModel = ConnectionsTabViewModel()
    @StateObject var logsViewModel = LogsTabViewModel()
    @StateObject var rulesViewModel = RulesTabViewModel()
    @Namespace var segmentedSelectionNamespace

    @State var switchingMode: CoreMode?
    @State var hoveringCopyRow = false
    @State var hoveredProviderName: String?
    @State var hoveredRuleIndex: Int?
    @State var hoveredMode: CoreMode?
    @State var hoveredTab: RootTab?
    @State var topHeaderHeight: CGFloat = 0
    @State var modeAndTabSectionHeight: CGFloat = 0
    @State var footerBarHeight: CGFloat = 0
    @State var currentTabContentHeight: CGFloat = 0
    @AppStorage("clashbar.proxy.group.hide_hidden") var hideHiddenProxyGroups: Bool = true
    @AppStorage("clashbar.proxy.group.sort_nodes_by_latency") var sortGroupNodesByLatency: Bool = false

    var contentWidth: CGFloat {
        MenuBarLayoutTokens.panelWidth - (MenuBarLayoutTokens.space8 * 2)
    }

    var language: AppLanguage {
        self.appSession.uiLanguage
    }

    func tr(_ key: String) -> String {
        L10n.t(key, language: self.language)
    }

    func tr(_ key: String, _ args: CVarArg...) -> String {
        L10n.t(key, language: self.language, args: args)
    }

    func setCurrentTabWithoutAnimation(_ tab: RootTab) {
        guard self.rootViewModel.currentTab != tab else { return }

        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            self.rootViewModel.syncCurrentTab(tab)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            self.panelContent
            Spacer(minLength: 0)
        }
        .frame(width: MenuBarLayoutTokens.panelWidth, alignment: .topLeading)
    }

    private var panelSections: some View {
        VStack(spacing: 0) {
            topHeader
                .frame(maxWidth: .infinity, alignment: .leading)
                .reportHeight { updateSectionHeight($0, target: .header) }

            modeAndTabSection
                .frame(maxWidth: .infinity, alignment: .leading)
                .reportHeight { updateSectionHeight($0, target: .modeAndTab) }

            ScrollView(.vertical) {
                self.measuredTabContent(for: self.rootViewModel.currentTab)
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: tabScrollAreaHeight, alignment: .top)

            footerBar
                .frame(maxWidth: .infinity, alignment: .leading)
                .reportHeight { updateSectionHeight($0, target: .footer) }
        }
    }

    private var styledPanelContent: some View {
        self.panelSections
            .frame(width: self.contentWidth, alignment: .topLeading)
            .padding(.horizontal, MenuBarLayoutTokens.space8)
            .frame(width: MenuBarLayoutTokens.panelWidth, height: resolvedPanelHeight, alignment: .topLeading)
            .background(self.panelBackground)
            .clipShape(RoundedRectangle(cornerRadius: MenuBarLayoutTokens.panelCornerRadius, style: .continuous))
    }

    var panelContent: some View {
        self.styledPanelContent
            .onAppear {
                self.setCurrentTabWithoutAnimation(self.appSession.activeMenuTab)
                self.appSession.setActiveMenuTab(self.rootViewModel.currentTab)
                self.refreshDerivedData(for: self.rootViewModel.currentTab)
                self.rootViewModel.updateFilteredProxyGroups(
                    from: self.appSession.proxyGroups,
                    hideHiddenGroups: self.hideHiddenProxyGroups)
                publishPreferredPanelHeight()
            }
            .onChange(of: self.rootViewModel.currentTab) { tab in
                self.currentTabContentHeight = 0
                self.appSession.setActiveMenuTab(tab)
                self.refreshDerivedData(for: tab)
            }
            .onChange(of: self.appSession.activeMenuTab) { tab in
                guard self.rootViewModel.currentTab != tab else { return }
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
            .onChange(of: ConnectionsRefreshToken(
                connections: self.connectionsStore.connections,
                keyword: self.connectionsViewModel.filterText,
                transport: self.connectionsViewModel.transportFilter,
                sort: self.connectionsViewModel.sortOption))
            { _ in
                self.refreshConnectionsDerivedDataIfVisible()
            }
            .onChange(of: LogsRefreshToken(
                    logs: self.appSession.errorLogs,
                    sources: self.logsViewModel.selectedSources,
                    levels: self.logsViewModel.selectedLevels,
                    keyword: self.logsViewModel.searchText))
            { _ in
                self.refreshLogsDerivedDataIfVisible()
                }
                .onChange(of: RulesRefreshToken(
                        items: self.appSession.ruleItems,
                        providers: self.appSession.ruleProviders))
                { _ in
                    self.refreshRulesDerivedDataIfVisible()
                    }
                    .onChange(of: self.appSession.proxyGroups) { newGroups in
                            self.rootViewModel.updateFilteredProxyGroups(
                                from: newGroups,
                                hideHiddenGroups: self.hideHiddenProxyGroups)
                        }
                        .onChange(of: self.hideHiddenProxyGroups) { _ in
                            self.rootViewModel.updateFilteredProxyGroups(
                                from: self.appSession.proxyGroups,
                                hideHiddenGroups: self.hideHiddenProxyGroups)
                        }
    }

    @ViewBuilder
    func tabBody(for tab: RootTab) -> some View {
        switch tab {
        case .proxy:
            proxyTabBody
        case .rules:
            rulesTabBody
        case .connections:
            connectionsTabBody
        case .logs:
            logsTabBody
        case .system:
            systemTabBody
        }
    }

    func tabUsesDynamicHeight(_ tab: RootTab) -> Bool {
        switch tab {
        case .proxy, .system:
            true
        case .rules, .connections, .logs:
            false
        }
    }

    @ViewBuilder
    func measuredTabContent(for tab: RootTab) -> some View {
        let content = self.tabContent(for: tab)
            .frame(maxWidth: .infinity, alignment: .leading)

        if self.tabUsesDynamicHeight(tab) {
            content.reportHeight { updateCurrentTabContentHeight($0, for: tab) }
        } else {
            content
        }
    }

    @ViewBuilder
    func tabContent(for tab: RootTab) -> some View {
        let content = self.tabBody(for: tab)
            .padding(.top, MenuBarLayoutTokens.space2)

        if self.tabUsesDynamicHeight(tab) {
            content.fixedSize(horizontal: false, vertical: true)
        } else {
            content
        }
    }

    var panelBackground: some View {
        AppMaterialSurface(
            cornerRadius: MenuBarLayoutTokens.panelCornerRadius,
            fallbackStyle: .material(.regularMaterial),
            stroke: nativeSeparator)
            .shadow(
                color: Color(nsColor: .shadowColor).opacity(MenuBarLayoutTokens.Shadow.standard.opacity),
                radius: MenuBarLayoutTokens.Shadow.standard.radius,
                x: MenuBarLayoutTokens.Shadow.standard.x,
                y: MenuBarLayoutTokens.Shadow.standard.y)
    }

    func refreshDerivedData(for tab: RootTab) {
        switch tab {
        case .proxy, .system:
            return
        case .rules:
            self.refreshVisibleRules()
        case .connections:
            self.refreshVisibleConnections()
        case .logs:
            self.refreshVisibleLogs()
        }
    }

    func refreshConnectionsDerivedDataIfVisible() {
        guard self.rootViewModel.currentTab == .connections else { return }
        self.refreshVisibleConnections()
    }

    func refreshLogsDerivedDataIfVisible() {
        guard self.rootViewModel.currentTab == .logs else { return }
        self.refreshVisibleLogs()
    }

    func refreshRulesDerivedDataIfVisible() {
        guard self.rootViewModel.currentTab == .rules else { return }
        self.refreshVisibleRules()
    }
}
