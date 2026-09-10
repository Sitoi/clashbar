import Foundation

enum RootTab: String, CaseIterable, Hashable {
    case proxy
    case rules
    case connections
    case logs
    case system

    static let settings = RootTab.system

    var titleKey: String {
        "ui.tab.\(self.rawValue)"
    }
}
