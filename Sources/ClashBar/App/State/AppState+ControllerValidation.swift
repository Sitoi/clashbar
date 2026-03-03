import Foundation

@MainActor
extension AppState {
    private var defaultControllerAddress: String {
        "127.0.0.1:9090"
    }

    func applyExternalControllerFromConfig(_ rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        guard self.isValidExternalController(trimmed) else {
            self.appendExternalControllerWarningOnce(
                key: "invalid:\(trimmed)",
                message: "Ignored invalid external-controller value: \(trimmed)")
            return
        }

        if let host = controllerHost(from: trimmed), !isLoopbackHost(host) {
            self.appendExternalControllerWarningOnce(
                key: "risk:\(host.lowercased())",
                message: "[security] external-controller host is not loopback: \(host)")
        }

        let clientController = self.normalizedControllerForClientAccess(trimmed)
        let didChangeController = controller != clientController
        if didChangeController {
            controller = clientController
            controllerUIURL = makeControllerUIURL(clientController)
        }
        if didChangeController || apiClient == nil {
            ensureAPIClient()
        }
    }

    func isValidExternalController(_ value: String) -> Bool {
        guard let components = parsedControllerComponents(from: value),
              let scheme = components.scheme?.lowercased(),
              let host = components.host,
              !host.isEmpty
        else {
            return false
        }
        guard scheme == "http" || scheme == "https" else {
            return false
        }
        if let port = components.port {
            return (1...65535).contains(port)
        }
        return true
    }

    func controllerHost(from value: String) -> String? {
        self.parsedControllerComponents(from: value)?.host
    }

    func isLoopbackHost(_ host: String) -> Bool {
        let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "localhost" || normalized == "127.0.0.1" || normalized == "::1"
    }

    func appendExternalControllerWarningOnce(key: String, message: String) {
        if externalControllerWarningKeys.insert(key).inserted {
            appendLog(level: "warning", message: message)
        }
    }

    func normalizedControllerAddress(_ value: String) -> String {
        if value.hasPrefix("http://") || value.hasPrefix("https://") {
            return value
        }
        return "http://\(value)"
    }

    func parsedControllerComponents(from value: String) -> URLComponents? {
        URLComponents(string: self.normalizedControllerAddress(value))
    }

    @discardableResult
    func applyExternalControllerFromSelectedConfigFile(configPath: String) -> String {
        let launchController = self.resolvedControllerFromSelectedConfigFile(configPath: configPath)
        self.applyExternalControllerFromConfig(launchController)
        self.syncControllerSecretFromConfigFileIfReadable(configPath: configPath)
        return launchController
    }

    func parseExternalController(fromConfigAt configPath: String) -> String? {
        guard let raw = try? String(contentsOfFile: configPath, encoding: .utf8) else {
            return nil
        }
        return self.parseYAMLScalarValue(forKey: "external-controller", fromConfigContent: raw)
    }

    func parseControllerSecret(fromConfigAt configPath: String) -> String? {
        guard let raw = try? String(contentsOfFile: configPath, encoding: .utf8) else {
            return nil
        }
        return self.parseYAMLScalarValue(forKey: "secret", fromConfigContent: raw)
    }

    func applyControllerSecretFromConfig(_ rawValue: String?) {
        let normalizedSecret = self.normalizedControllerSecret(rawValue)
        let currentSecret = self.normalizedControllerSecret(controllerSecret)
        if normalizedSecret != currentSecret {
            controllerSecret = normalizedSecret
        }
        ensureAPIClient()
    }

    private func syncControllerSecretFromConfigFileIfReadable(configPath: String) {
        guard let raw = try? String(contentsOfFile: configPath, encoding: .utf8) else {
            return
        }
        let parsedSecret = self.parseYAMLScalarValue(forKey: "secret", fromConfigContent: raw)
        self.applyControllerSecretFromConfig(parsedSecret)
    }

    private func parseYAMLScalarValue(forKey key: String, fromConfigContent raw: String) -> String? {
        var topLevelIndent: Int?
        for line in raw.split(whereSeparator: \.isNewline) {
            let lineText = String(line)
            let indent = self.leadingWhitespaceCount(in: lineText)
            let content = String(lineText.dropFirst(indent))
            let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedContent.isEmpty || trimmedContent.hasPrefix("#") {
                continue
            }

            if topLevelIndent == nil {
                topLevelIndent = indent
            }
            guard indent == topLevelIndent else {
                continue
            }

            guard let value = extractYAMLScalarValue(key: key, fromYAMLLineContent: content) else {
                continue
            }
            return value
        }
        return nil
    }

    private func extractYAMLScalarValue(key: String, fromYAMLLineContent line: String) -> String? {
        let escapedKey = NSRegularExpression.escapedPattern(for: key)
        let linePattern = #"^\#(escapedKey)\s*:\s*(.*)$"#
        guard let range = line.range(
            of: linePattern,
            options: [.regularExpression])
        else {
            return nil
        }

        let prefixPattern = #"^\#(escapedKey)\s*:\s*"#
        var value = String(line[range]).replacingOccurrences(
            of: prefixPattern,
            with: "",
            options: [.regularExpression])

        value = self.stripYAMLInlineComment(value).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        if (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
            value.removeFirst()
            value.removeLast()
            value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard !value.isEmpty else { return nil }
        if value == "~" || value.lowercased() == "null" {
            return nil
        }
        return value
    }

    private func normalizedControllerSecret(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed == "~" || trimmed.lowercased() == "null" {
            return nil
        }
        return trimmed
    }

    private func leadingWhitespaceCount(in line: String) -> Int {
        line.prefix { $0 == " " || $0 == "\t" }.count
    }

    private func stripYAMLInlineComment(_ value: String) -> String {
        var inSingleQuote = false
        var inDoubleQuote = false
        var isEscaped = false
        var result = ""

        for char in value {
            if isEscaped {
                result.append(char)
                isEscaped = false
                continue
            }

            if char == "\\", inDoubleQuote {
                result.append(char)
                isEscaped = true
                continue
            }

            if char == "'", !inDoubleQuote {
                inSingleQuote.toggle()
                result.append(char)
                continue
            }

            if char == "\"", !inSingleQuote {
                inDoubleQuote.toggle()
                result.append(char)
                continue
            }

            if char == "#", !inSingleQuote, !inDoubleQuote {
                break
            }

            result.append(char)
        }

        return result
    }

    private func resolvedControllerFromSelectedConfigFile(configPath: String) -> String {
        if let parsed = parseExternalController(fromConfigAt: configPath) {
            guard self.isValidExternalController(parsed) else {
                self.appendExternalControllerWarningOnce(
                    key: "invalid:\(parsed)",
                    message: "Ignored invalid external-controller value: \(parsed)")
                return self.defaultControllerAddress
            }
            return parsed
        }
        return self.defaultControllerAddress
    }

    private func normalizedControllerForClientAccess(_ value: String) -> String {
        guard var components = parsedControllerComponents(from: value),
              let host = components.host
        else {
            return value
        }

        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let replacementHost: String
        switch normalizedHost {
        case "0.0.0.0":
            replacementHost = "127.0.0.1"
        case "::", "0:0:0:0:0:0:0:0":
            replacementHost = "::1"
        default:
            return value
        }

        components.host = replacementHost
        if value.hasPrefix("http://") || value.hasPrefix("https://") {
            return components.string ?? value
        }

        guard let hostPort = hostPortString(from: components) else {
            return value
        }
        return hostPort
    }

    private func hostPortString(from components: URLComponents) -> String? {
        guard let host = components.host, !host.isEmpty else {
            return nil
        }
        let hostSegment = host.contains(":") ? "[\(host)]" : host
        if let port = components.port {
            return "\(hostSegment):\(port)"
        }
        return hostSegment
    }
}
