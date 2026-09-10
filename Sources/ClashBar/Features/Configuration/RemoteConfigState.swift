import Foundation

enum RemoteConfigRefreshPhase: Equatable {
    case idle
    case refreshing
    case failed
}

struct RemoteConfigMenuState: Equatable {
    let updatedAt: Date?
    let phase: RemoteConfigRefreshPhase
    let autoUpdateEnabled: Bool
    let nextUpdateAt: Date?

    static let idle = RemoteConfigMenuState(
        updatedAt: nil,
        phase: .idle,
        autoUpdateEnabled: false,
        nextUpdateAt: nil)
}

struct RemoteConfigImportInput {
    let urlString: String
    let fileName: String
    let autoUpdateEnabled: Bool
    let autoUpdateIntervalHours: Int
}
