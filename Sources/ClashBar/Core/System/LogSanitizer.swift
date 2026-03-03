import Foundation

enum LogSanitizer {
    static func redact(_ input: String) -> String {
        var text = input
        text = self.redactBearer(text)
        text = self.redactSecretArg(text)
        text = self.redactURLUserInfo(text)
        text = self.redactSensitiveQuery(text)
        text = self.redactSensitiveJSONPairs(text)
        text = self.redactSensitiveAssignments(text)
        return text
    }

    private static func redactBearer(_ input: String) -> String {
        self.replacing(input, pattern: "(?i)(Authorization\\s*:\\s*Bearer\\s+)[^\\s]+", with: "$1***")
    }

    private static func redactSecretArg(_ input: String) -> String {
        self.replacing(input, pattern: "(?i)(-secret\\s+)[^\\s]+", with: "$1***")
    }

    private static func redactURLUserInfo(_ input: String) -> String {
        self.replacing(input, pattern: "([a-zA-Z][a-zA-Z0-9+.-]*://)([^/@:]+):([^/@]+)@", with: "$1***:***@")
    }

    private static func redactSensitiveQuery(_ input: String) -> String {
        self.replacing(input, pattern: "(?i)([?&](?:token|secret|password)=)[^&\\s]+", with: "$1***")
    }

    private static func redactSensitiveJSONPairs(_ input: String) -> String {
        self.replacing(
            input,
            pattern: "(?i)(\"(?:token|secret|password|passwd|api[_-]?key)\"\\s*:\\s*\")[^\"]*(\")",
            with: "$1***$2")
    }

    private static func redactSensitiveAssignments(_ input: String) -> String {
        self.replacing(
            input,
            pattern: "(?i)((?:token|secret|password|passwd|api[_-]?key)\\s*[=:]\\s*)[^\\s,;]+",
            with: "$1***")
    }

    private static func replacing(_ input: String, pattern: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return input
        }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        return regex.stringByReplacingMatches(in: input, options: [], range: range, withTemplate: template)
    }
}
