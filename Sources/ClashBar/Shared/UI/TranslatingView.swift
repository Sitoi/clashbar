import SwiftUI

// swiftlint:disable:next type_name
private typealias T = MenuBarLayoutTokens

protocol TranslatingView: View {
    var appViewModel: AppViewModel { get }
}

extension TranslatingView {
    var language: AppLanguage {
        appViewModel.uiLanguage
    }

    func tr(_ key: String) -> String {
        L10n.t(key, language: self.language)
    }

    func tr(_ key: String, _ args: CVarArg...) -> String {
        L10n.t(key, language: self.language, args: args)
    }

    var statusColor: Color {
        switch appViewModel.runtimeVisualStatus {
        case .runningHealthy: self.nativePositive.opacity(T.Opacity.solid)
        case .runningDegraded: self.nativeWarning.opacity(T.Opacity.solid)
        case .starting: self.nativeInfo.opacity(T.Opacity.solid)
        case .failed: self.nativeCritical.opacity(T.Opacity.solid)
        case .stopped: self.nativeSecondaryLabel
        }
    }
}
