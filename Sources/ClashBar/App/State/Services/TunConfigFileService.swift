import Foundation

enum TunConfigFileServiceError: LocalizedError {
    case configPathEmpty
    case configNotFound
    case unableToReadConfig(String)
    case unableToWriteConfig(String)

    var errorDescription: String? {
        switch self {
        case .configPathEmpty:
            "Config file path is empty."
        case .configNotFound:
            "Config file not found."
        case let .unableToReadConfig(message):
            "Failed to read config file: \(message)"
        case let .unableToWriteConfig(message):
            "Failed to write config file: \(message)"
        }
    }
}

struct TunConfigFileService: Sendable {
    private let tunDefaultLines: [String] = [
        "  enable: true",
        "  device: utun1500",
        "  stack: mixed",
        "  auto-route: true",
        "  auto-redirect: false",
        "  auto-detect-interface: true",
        "  dns-hijack:",
        "    - any:53",
        "  route-exclude-address: []",
        "  mtu: 1500",
    ]

    func patchConfig(
        at configPath: String,
        tunEnabled: Bool,
        ensureDNSEnabledWhenTunOn: Bool) throws
    {
        let trimmedPath = configPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            throw TunConfigFileServiceError.configPathEmpty
        }
        guard FileManager.default.fileExists(atPath: trimmedPath) else {
            throw TunConfigFileServiceError.configNotFound
        }

        let originalContent: String
        do {
            originalContent = try String(contentsOfFile: trimmedPath, encoding: .utf8)
        } catch {
            throw TunConfigFileServiceError.unableToReadConfig(error.localizedDescription)
        }

        let lineEnding = originalContent.contains("\r\n") ? "\r\n" : "\n"
        var lines = originalContent.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        self.ensureTunBlock(lines: &lines, enabled: tunEnabled)

        if tunEnabled, ensureDNSEnabledWhenTunOn {
            self.ensureDNSBlock(lines: &lines)
        }

        var patched = lines.joined(separator: "\n")
        if lineEnding == "\r\n" {
            patched = patched.replacingOccurrences(of: "\n", with: "\r\n")
        }

        guard patched != originalContent else { return }
        do {
            try patched.write(toFile: trimmedPath, atomically: true, encoding: .utf8)
        } catch {
            throw TunConfigFileServiceError.unableToWriteConfig(error.localizedDescription)
        }
    }

    private func ensureTunBlock(lines: inout [String], enabled: Bool) {
        if let range = topLevelBlockRange(for: "tun", lines: lines) {
            self.replaceTunEnableLine(lines: &lines, range: range, enabled: enabled)
            if enabled {
                self.ensureTunDefaults(lines: &lines, range: range)
            }
            return
        }

        guard enabled else { return }
        self.appendBlankLineIfNeeded(lines: &lines)
        lines.append("tun:")
        lines.append(contentsOf: self.tunDefaultLines)
    }

    private func ensureDNSBlock(lines: inout [String]) {
        if let range = topLevelBlockRange(for: "dns", lines: lines) {
            self.replaceChildLine(
                lines: &lines,
                range: range,
                key: "enable",
                value: "true")
            return
        }

        self.appendBlankLineIfNeeded(lines: &lines)
        lines.append("dns:")
        lines.append("  enable: true")
    }

    private func ensureTunDefaults(lines: inout [String], range: Range<Int>) {
        self.replaceChildLine(lines: &lines, range: range, key: "device", value: "utun1500")
        self.replaceChildLine(lines: &lines, range: range, key: "stack", value: "mixed")
        self.replaceChildLine(lines: &lines, range: range, key: "auto-route", value: "true")
        self.replaceChildLine(lines: &lines, range: range, key: "auto-redirect", value: "false")
        self.replaceChildLine(lines: &lines, range: range, key: "auto-detect-interface", value: "true")
        self.replaceChildLine(lines: &lines, range: range, key: "route-exclude-address", value: "[]")
        self.replaceChildLine(lines: &lines, range: range, key: "mtu", value: "1500")
        self.ensureDnsHijack(lines: &lines, range: range)
    }

    private func replaceTunEnableLine(lines: inout [String], range: Range<Int>, enabled: Bool) {
        self.replaceChildLine(lines: &lines, range: range, key: "enable", value: enabled ? "true" : "false")
    }

    private func ensureDnsHijack(lines: inout [String], range: Range<Int>) {
        if self.childLineIndex(for: "dns-hijack", lines: lines, range: range) != nil {
            return
        }
        let indent = self.childIndent(lines: lines, range: range)
        let insertAt = range.upperBound
        lines.insert("\(indent)dns-hijack:", at: insertAt)
        lines.insert("\(indent)  - any:53", at: insertAt + 1)
    }

    private func replaceChildLine(
        lines: inout [String],
        range: Range<Int>,
        key: String,
        value: String)
    {
        let indent = self.childIndent(lines: lines, range: range)
        if let lineIndex = childLineIndex(for: key, lines: lines, range: range) {
            lines[lineIndex] = "\(indent)\(key): \(value)"
            return
        }
        lines.insert("\(indent)\(key): \(value)", at: range.upperBound)
    }

    private func childIndent(lines: [String], range: Range<Int>) -> String {
        for index in (range.lowerBound + 1)..<range.upperBound {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let leadingSpaces = line.prefix { $0 == " " }.count
            if leadingSpaces > 0 {
                return String(repeating: " ", count: leadingSpaces)
            }
        }
        return "  "
    }

    private func childLineIndex(for key: String, lines: [String], range: Range<Int>) -> Int? {
        for index in (range.lowerBound + 1)..<range.upperBound {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

            let leadingSpaces = line.prefix { $0 == " " }.count
            guard leadingSpaces > 0 else { continue }
            let content = String(line.dropFirst(leadingSpaces)).trimmingCharacters(in: .whitespaces)
            if content == "\(key):" || content.hasPrefix("\(key): ") {
                return index
            }
        }
        return nil
    }

    private func topLevelBlockRange(for key: String, lines: [String]) -> Range<Int>? {
        guard let start = lines.firstIndex(where: { isTopLevelKeyLine($0, key: key) }) else {
            return nil
        }

        var end = lines.count
        if start + 1 < lines.count {
            for index in (start + 1)..<lines.count where self.isTopLevelMappingLine(lines[index]) {
                end = index
                break
            }
        }
        return start..<end
    }

    private func isTopLevelKeyLine(_ line: String, key: String) -> Bool {
        guard line.prefix(while: { $0 == " " || $0 == "\t" }).isEmpty else { return false }
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return false }
        return trimmed == "\(key):" || trimmed.hasPrefix("\(key): ")
    }

    private func isTopLevelMappingLine(_ line: String) -> Bool {
        guard line.prefix(while: { $0 == " " || $0 == "\t" }).isEmpty else { return false }
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return false }
        return trimmed.contains(":")
    }

    private func appendBlankLineIfNeeded(lines: inout [String]) {
        guard let last = lines.last else { return }
        if !last.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("")
        }
    }
}
