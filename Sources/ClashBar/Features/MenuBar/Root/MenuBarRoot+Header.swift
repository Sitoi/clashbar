import Foundation
import SwiftUI

extension MenuBarRoot {
    var topHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(nativeControlFill.opacity(0.94))
                        .overlay {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
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
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(nativePrimaryLabel)

                        HStack(spacing: MenuBarLayoutTokens.hMicro) {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 5, height: 5)
                            Text(runtimeBadgeText)
                                .font(.system(size: 11, weight: .medium))
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
                            text: appState.controller)
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

                self.compactTopIcon("stop.circle", label: tr("ui.action.stop")) {
                    await appState.stopCore()
                }
                .disabled(appState.isCoreActionProcessing)
                .opacity(appState.isCoreActionProcessing ? 0.6 : 1)

                self.compactTopIcon("rectangle.portrait.and.arrow.right", label: tr("ui.action.quit"), warning: true) {
                    await appState.quitApp()
                }
            }
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Rectangle().fill(nativeSeparator).frame(height: MenuBarLayoutTokens.hairline)
        }
    }

    func headerMetaLabel(symbol: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(nativeTertiaryLabel)
            Text(text)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.system(size: 11, weight: .medium))
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

    func makeMetaCubeXDSetupURL(controller: String, secret: String?) -> URL? {
        guard let endpoint = parseControllerEndpoint(controller) else { return nil }

        var query = URLComponents()
        var items: [URLQueryItem] = [
            URLQueryItem(name: "hostname", value: endpoint.host),
            URLQueryItem(name: "port", value: "\(endpoint.port)"),
            URLQueryItem(name: "http", value: endpoint.useHTTP ? "true" : "false"),
        ]
        let trimmedSecret = secret?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedSecret.isEmpty {
            items.append(URLQueryItem(name: "secret", value: trimmedSecret))
        }
        query.queryItems = items

        guard let encodedQuery = query.percentEncodedQuery else { return nil }
        return URL(string: "https://metacubexd.pages.dev/#/setup?\(encodedQuery)")
    }

    func parseControllerEndpoint(_ raw: String) -> (host: String, port: Int, useHTTP: Bool)? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
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
        warning: Bool = false,
        action: @escaping () async -> Void) -> some View
    {
        let tone: Color = if warning {
            nativeCritical
        } else if symbol.contains("arrow.clockwise") {
            nativeInfo
        } else if symbol.contains("stop") {
            nativeWarning
        } else {
            nativeSecondaryLabel
        }

        return TopHeaderIconActionButton(
            symbol: symbol,
            tone: tone.opacity(0.94),
            action: action)
            .accessibilityLabel(label)
    }
}

private struct TopHeaderIconActionButton: View {
    let symbol: String
    let tone: Color
    let action: () async -> Void

    @State private var hovered = false

    var body: some View {
        Button {
            Task { await self.action() }
        } label: {
            Image(systemName: self.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(self.hovered ? self.tone : Color(nsColor: .secondaryLabelColor))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.borderless)
        .onHover { self.hovered = $0 }
    }
}
