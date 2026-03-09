import SwiftUI

extension MenuBarRoot {
    var topHeader: some View {
        HStack(alignment: .center, spacing: MenuBarLayoutTokens.space8) {
            HStack(alignment: .center, spacing: MenuBarLayoutTokens.space8) {
                ZStack {
                    RoundedRectangle(cornerRadius: MenuBarLayoutTokens.cornerRadius, style: .continuous)
                        .fill(nativeControlFill.opacity(MenuBarLayoutTokens.Opacity.solid))
                        .overlay {
                            RoundedRectangle(cornerRadius: MenuBarLayoutTokens.cornerRadius, style: .continuous)
                                .stroke(nativeControlBorder.opacity(MenuBarLayoutTokens.Opacity.solid), lineWidth: MenuBarLayoutTokens.stroke)
                        }

                    if let brandImage = BrandIcon.image {
                        Image(nsImage: brandImage)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(width: MenuBarLayoutTokens.rowHeight, height: MenuBarLayoutTokens.rowHeight)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .renderingMode(.template)
                            .symbolRenderingMode(.monochrome)
                            .resizable()
                            .scaledToFit()
                            .frame(width: MenuBarLayoutTokens.rowHeight, height: MenuBarLayoutTokens.rowHeight)
                            .foregroundStyle(nativeAccent)
                    }
                }
                .frame(width: MenuBarLayoutTokens.rowHeight, height: MenuBarLayoutTokens.rowHeight)

                VStack(alignment: .leading, spacing: MenuBarLayoutTokens.space4) {
                    HStack(spacing: MenuBarLayoutTokens.space6) {
                        Text("ClashBar")
                            .font(.app(size: MenuBarLayoutTokens.FontSize.title, weight: .semibold))
                            .foregroundStyle(nativePrimaryLabel)

                        HStack(spacing: MenuBarLayoutTokens.space1) {
                            Circle()
                                .fill(statusColor)
                                .frame(width: MenuBarLayoutTokens.space4, height: MenuBarLayoutTokens.space4)
                            Text(runtimeBadgeText)
                                .font(.app(size: MenuBarLayoutTokens.FontSize.caption, weight: .medium))
                                .foregroundStyle(nativeSecondaryLabel)
                        }
                        .padding(.horizontal, MenuBarLayoutTokens.space6)
                        .padding(.vertical, MenuBarLayoutTokens.space2)
                        .background(nativeControlFill.opacity(MenuBarLayoutTokens.Opacity.solid), in: Capsule())
                        .overlay {
                            Capsule().stroke(nativeControlBorder.opacity(MenuBarLayoutTokens.Theme.Dark.borderEmphasis), lineWidth: MenuBarLayoutTokens.stroke)
                        }
                    }

                    HStack(spacing: MenuBarLayoutTokens.space6) {
                        self.headerControllerLink(
                            symbol: "network",
                            text: appState.externalControllerDisplay)
                        if appState.isExternalControllerWildcardIPv4 {
                            self.headerControllerWarningIcon
                        }
                    }
                }
            }

            Spacer(minLength: MenuBarLayoutTokens.space6)

            HStack(spacing: MenuBarLayoutTokens.space6) {
                self.compactTopIcon("arrow.clockwise", label: appState.primaryCoreActionLabel) {
                    await appState.performPrimaryCoreAction()
                }
                .disabled(!appState.isPrimaryCoreActionEnabled)
                .opacity(appState.isPrimaryCoreActionEnabled ? 1 : 0.6)

                self.compactTopIcon(
                    appState.isRuntimeRunning ? "stop.circle" : "play.circle",
                    label: appState.isRuntimeRunning ? tr("ui.action.stop") : tr("app.primary.start"))
                {
                    if appState.isRuntimeRunning {
                        await appState.stopCore()
                    } else {
                        await appState.startCore(trigger: .manual)
                    }
                }
                .disabled(appState.isCoreActionProcessing)
                .opacity(appState.isCoreActionProcessing ? 0.6 : 1)

                self.compactTopIcon("rectangle.portrait.and.arrow.right", label: tr("ui.action.quit"), warning: true) {
                    await appState.quitApp()
                }
            }
        }
        .padding(.vertical, MenuBarLayoutTokens.space8)
    }

    func headerMetaLabel(symbol: String, text: String) -> some View {
        HStack(spacing: MenuBarLayoutTokens.space4) {
            Image(systemName: symbol)
                .font(.app(size: MenuBarLayoutTokens.FontSize.caption, weight: .medium))
                .foregroundStyle(nativeTertiaryLabel)
            Text(text)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.app(size: MenuBarLayoutTokens.FontSize.caption, weight: .medium))
        .foregroundStyle(nativeSecondaryLabel)
    }

    @ViewBuilder
    func headerControllerLink(symbol: String, text: String) -> some View {
        if let url = makeMetaCubeXDSetupURL(
            controller: appState.controller,
            secret: appState.controllerSecret)
        {
            Link(destination: url) {
                self.headerMetaLabel(symbol: symbol, text: text)
            }
            .buttonStyle(.plain)
            .help(url.absoluteString)
        } else {
            self.headerMetaLabel(symbol: symbol, text: text)
        }
    }

    var headerControllerWarningIcon: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.app(size: MenuBarLayoutTokens.FontSize.caption, weight: .semibold))
            .foregroundStyle(nativeWarning)
            .help("external-controller is 0.0.0.0 and can be accessed from your LAN.")
            .accessibilityLabel("Warning: external-controller is bound to 0.0.0.0")
    }

    func makeMetaCubeXDSetupURL(controller: String, secret: String?) -> URL? {
        guard let endpoint = parseControllerEndpoint(controller) else { return nil }

        var query = URLComponents()
        var items: [URLQueryItem] = [
            URLQueryItem(name: "hostname", value: endpoint.host),
            URLQueryItem(name: "port", value: "\(endpoint.port)"),
            URLQueryItem(name: "http", value: endpoint.useHTTP ? "true" : "false"),
        ]
        if let trimmedSecret = secret.trimmedNonEmpty {
            items.append(URLQueryItem(name: "secret", value: trimmedSecret))
        }
        query.queryItems = items

        guard let encodedQuery = query.percentEncodedQuery else { return nil }
        return URL(string: "https://metacubexd.pages.dev/#/setup?\(encodedQuery)")
    }

    func parseControllerEndpoint(_ raw: String) -> (host: String, port: Int, useHTTP: Bool)? {
        let trimmed = raw.trimmed
        guard !trimmed.isEmpty else { return nil }

        let normalized = trimmed.contains("://") ? trimmed : "http://\(trimmed)"
        guard let components = URLComponents(string: normalized),
              let host = components.host,
              !host.isEmpty
        else {
            return nil
        }

        let scheme = components.scheme?.lowercased() ?? "http"
        let useHTTP = scheme != "https"
        let fallbackPort = useHTTP ? 80 : 443
        return (host: host, port: components.port ?? fallbackPort, useHTTP: useHTTP)
    }

    func compactTopIcon(
        _ symbol: String,
        label: String,
        role: ButtonRole? = nil,
        warning: Bool = false,
        toneOverride: Color? = nil,
        isLoading: Bool = false,
        action: @escaping () async -> Void) -> some View
    {
        let tone: Color = if let toneOverride {
            toneOverride
        } else if warning {
            nativeCritical
        } else if symbol.contains("arrow.clockwise") {
            nativeInfo
        } else if symbol.contains("stop") {
            nativeWarning
        } else {
            nativeSecondaryLabel
        }

        return self.compactAsyncIconButton(
            symbol: symbol,
            label: label,
            tint: tone.opacity(MenuBarLayoutTokens.Opacity.solid),
            role: role,
            isLoading: isLoading,
            action: action)
    }
}
