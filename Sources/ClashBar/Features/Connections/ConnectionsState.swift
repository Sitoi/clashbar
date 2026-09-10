import Foundation
import MihomoKit

enum ConnectionsTransportFilter: String, CaseIterable, Identifiable, Sendable {
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

enum ConnectionsSortOption: String, CaseIterable, Identifiable, Sendable {
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
