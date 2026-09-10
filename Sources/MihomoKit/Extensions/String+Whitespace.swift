import Foundation

extension StringProtocol {
    public var trimmed: String {
        self.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension String {
    public var nonEmpty: String? {
        self.isEmpty ? nil : self
    }

    public var trimmedNonEmpty: String? {
        self.trimmed.nonEmpty
    }
}

extension String? {
    public var trimmedOrEmpty: String {
        self?.trimmed ?? ""
    }

    public var trimmedNonEmpty: String? {
        self.flatMap(\.trimmedNonEmpty)
    }
}
