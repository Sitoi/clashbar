import SwiftUI

extension MenuBarRoot {
    var topHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: MenuBarLayoutTokens.iconCornerRadius, style: .continuous)
                        .fill(nativeControlFill.opacity(0.94))
                        .overlay {
                            RoundedRectangle(cornerRadius: MenuBarLayoutTokens.iconCornerRadius, style: .continuous)
                                .stroke(nativeControlBorder.opacity(0.92), lineWidth: 0.7)
                        }

                    if let brandImage = BrandIcon.image {
                        Image(nsImage: brandImage)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(width: 32, height: 32)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .renderingMode(.template)
                            .symbolRenderingMode(.monochrome)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 32, height: 32)
                            .foregroundStyle(nativeAccent)
                    }
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text("ClashBar")
                            .font(.appSystem(size: 16, weight: .semibold))
                            .foregroundStyle(nativePrimaryLabel)

                        HStack(spacing: MenuBarLayoutTokens.hMicro) {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 5, height: 5)
                            Text(runtimeBadgeText)
                                .font(.appSystem(size: 11, weight: .medium))
                                .foregroundStyle(nativeSecondaryLabel)
                        }
                        .padding(.horizontal, MenuBarLayoutTokens.hDense)
                        .padding(.vertical, 3)
                        .background(nativeControlFill.opacity(0.92), in: Capsule())
                        .overlay {
                            Capsule().stroke(nativeControlBorder.opacity(0.82), lineWidth: 0.7)
                        }
                    }

                    HStack(spacing: 6) {
                        self.headerControllerLink(
                            symbol: "network",
                            text: appState.externalControllerDisplay)
                        if appState.isExternalControllerWildcardIPv4 {
                            self.headerControllerWarningIcon
                        }
                    }
                }
            }

            Spacer(minLength: 6)

            HStack(spacing: 6) {
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
        .padding(.vertical, 8)
    }

    func headerMetaLabel(symbol: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.appSystem(size: 10, weight: .medium))
                .foregroundStyle(nativeTertiaryLabel)
            Text(text)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.appSystem(size: 11, weight: .medium))
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
            .font(.appSystem(size: 10, weight: .semibold))
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
            tint: tone.opacity(0.94),
            role: role,
            isLoading: isLoading,
            action: action)
    }
}
