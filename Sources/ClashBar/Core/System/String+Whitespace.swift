import Foundation

extension StringProtocol {
    var trimmed: String {
        self.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension String {
    var nonEmpty: String? {
        self.isEmpty ? nil : self
    }

    var trimmedNonEmpty: String? {
        self.trimmed.nonEmpty
    }
}

extension String? {
    var trimmedOrEmpty: String {
        self?.trimmed ?? ""
    }

    var trimmedNonEmpty: String? {
        self.flatMap(\.trimmedNonEmpty)
    }
}
