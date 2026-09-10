import Foundation

enum ConfigLogLevel: String, CaseIterable {
    case silent
    case error
    case warning
    case info
    case debug
}

enum EditableBooleanSetting: String, CaseIterable, Identifiable {
    case allowLan = "allow-lan"
    case ipv6
    case tcpConcurrent = "tcp-concurrent"

    var id: String {
        self.rawValue
    }

    var keyPath: KeyPath<EditableSettingsSnapshot, Bool> {
        switch self {
        case .allowLan: \.allowLan
        case .ipv6: \.ipv6
        case .tcpConcurrent: \.tcpConcurrent
        }
    }
}

enum AppAppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String {
        rawValue
    }
}

struct EditableSystemProxyException: Identifiable, Equatable {
    let id: UUID
    var value: String

    init(id: UUID = UUID(), value: String) {
        self.id = id
        self.value = value
    }
}

struct SettingsPortField: Equatable {
    let key: String
    let value: String
}
