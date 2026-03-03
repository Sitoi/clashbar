import Foundation

actor ProcessStateActor {
    private(set) var status: CoreLifecycleStatus = .stopped
    private(set) var intentionalStop: Bool = false

    func setStatus(_ newStatus: CoreLifecycleStatus) {
        self.status = newStatus
    }

    func setIntentionalStop(_ value: Bool) {
        self.intentionalStop = value
    }
}
