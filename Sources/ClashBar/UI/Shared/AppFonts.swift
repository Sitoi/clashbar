import AppKit
import SwiftUI

private typealias FS = MenuBarLayoutTokens.FontSize

extension Font {
    static func app(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font(NSFont.monospacedSystemFont(ofSize: size, weight: weight.nsFontWeight))
    }

    static let appCaption = app(size: FS.caption, weight: .medium)
    static let appBody = app(size: FS.body, weight: .medium)
    static let appSubhead = app(size: FS.subhead, weight: .semibold)
    static let appTitle = app(size: FS.title, weight: .bold)
}

extension Font.Weight {
    fileprivate var nsFontWeight: NSFont.Weight {
        switch self {
        case .ultraLight:
            .ultraLight
        case .thin:
            .thin
        case .light:
            .light
        case .regular:
            .regular
        case .medium:
            .medium
        case .semibold:
            .semibold
        case .bold:
            .bold
        case .heavy:
            .heavy
        case .black:
            .black
        default:
            .regular
        }
    }
}
