import MihomoKit
import SwiftUI

// swiftlint:disable:next type_name
private typealias T = MenuBarLayoutTokens

struct MenuBarRootView: TranslatingView {
    @EnvironmentObject var appViewModel: AppViewModel
    @EnvironmentObject var proxyStore: ProxyStore
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var popoverLayoutModel: PopoverLayoutModel

    @Namespace var segmentedSelectionNamespace

    @State var currentTab: RootTab = .proxy
    @State var switchingMode: CoreMode?
    @State var showRemoteMachineManager = false
    @State var hoveredMode: CoreMode?
    @State var hoveredTab: RootTab?
    @State var topHeaderHeight: CGFloat = 0
    @State var modeAndTabSectionHeight: CGFloat = 0
    @State var footerBarHeight: CGFloat = 0
    @State var currentTabContentHeight: CGFloat = 0

    var contentWidth: CGFloat {
        T.panelWidth - (T.space8 * 2)
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
        .frame(width: T.panelWidth, alignment: .topLeading)
    }

    private var panelSections: some View {
        VStack(spacing: 0) {
            MenuBarHeaderView(
                showRemoteMachineManager: self.$showRemoteMachineManager)
                .frame(maxWidth: .infinity, alignment: .leading)
                .reportHeight { updateSectionHeight($0, target: .header) }

            modeAndTabSection
                .frame(maxWidth: .infinity, alignment: .leading)
                .reportHeight { updateSectionHeight($0, target: .modeAndTab) }

            ScrollView(.vertical) {
                self.measuredTabContent(for: self.currentTab)
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
            .padding(.horizontal, T.space8)
            .frame(
                width: T.panelWidth,
                height: resolvedPanelHeight,
                alignment: .topLeading)
            .background(self.panelBackground)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: T.panelCornerRadius, style: .continuous))
    }

    var panelContent: some View {
        self.styledPanelContent
            .onAppear {
                self.appViewModel.resumeHighFrequencyStreams()
                self.setCurrentTabWithoutAnimation(self.appViewModel.activeMenuTab)
                self.appViewModel.setActiveMenuTab(self.currentTab)
                self.refreshDerivedData(for: self.currentTab)
                publishPreferredPanelHeight()
            }
            .onDisappear {
                self.appViewModel.pauseHighFrequencyStreams()
            }
            .onChange(of: self.currentTab) { tab in
                self.currentTabContentHeight = 0
                self.appViewModel.setActiveMenuTab(tab)
                self.refreshDerivedData(for: tab)
            }
            .onChange(of: self.appViewModel.activeMenuTab) { tab in
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
    }

    @ViewBuilder
    func tabBody(for tab: RootTab) -> some View {
        switch tab {
        case .proxy:
            ProxyTabView()
        case .rules:
            RulesTabView()
        case .connections:
            ConnectionsTabView()
        case .logs:
            LogsTabView()
        case .system:
            SettingsTabView()
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
            .padding(.top, T.space2)

        if self.tabUsesDynamicHeight(tab) {
            content.fixedSize(horizontal: false, vertical: true)
        } else {
            content
        }
    }

    var panelBackground: some View {
        AppMaterialSurface(
            cornerRadius: T.panelCornerRadius,
            stroke: nativeSeparator)
            .shadow(
                color: self.nativeShadow.opacity(
                    T.Shadow.standard.opacity),
                radius: T.Shadow.standard.radius,
                x: T.Shadow.standard.x,
                y: T.Shadow.standard.y)
    }

    func refreshDerivedData(for tab: RootTab) {
        switch tab {
        case .proxy:
            Task { await self.proxyStore.refreshSystemProxyHelperRuntimeSnapshot() }
        case .system, .rules, .connections, .logs:
            break
        }
    }
}
