import Foundation

struct ConfigImportService {
    private let maxRemoteConfigBytes = 5 * 1024 * 1024

    func writeConfigData(_ data: Data, to targetURL: URL) throws {
        guard !data.isEmpty else {
            throw NSError(
                domain: "ClashBar.ConfigImport",
                code: 422,
                userInfo: [NSLocalizedDescriptionKey: "Remote config response is empty"])
        }
        try data.write(to: targetURL, options: .atomic)
    }

    func normalizedConfigFileName(_ fileName: String, fallback: String? = nil) -> String? {
        let trimmed = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = trimmed.isEmpty ? (fallback ?? "") : trimmed
        let candidate = URL(fileURLWithPath: baseName).lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty, candidate != ".", candidate != ".." else { return nil }

        let ext = (candidate as NSString).pathExtension.lowercased()
        if ext.isEmpty {
            return "\(candidate).yaml"
        }
        guard ext == "yaml" || ext == "yml" else { return nil }
        return candidate
    }

    func inferredRemoteConfigFileName(from remoteURL: URL) -> String {
        let rawName = remoteURL.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawName.isEmpty else { return "remote-config.yaml" }

        let ext = (rawName as NSString).pathExtension.lowercased()
        if ext == "yaml" || ext == "yml" {
            return rawName
        }

        if ext.isEmpty {
            return "\(rawName).yaml"
        }

        let stem = (rawName as NSString).deletingPathExtension
        let base = stem.trimmingCharacters(in: .whitespacesAndNewlines)
        return base.isEmpty ? "remote-config.yaml" : "\(base).yaml"
    }

    func isSupportedRemoteConfigURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    func downloadRemoteConfigData(from remoteURL: URL) async throws -> Data {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }

        let (bytes, response) = try await session.bytes(from: remoteURL)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard 200..<300 ~= http.statusCode else {
            throw APIError.statusCode(http.statusCode, HTTPURLResponse.localizedString(forStatusCode: http.statusCode))
        }

        if http.expectedContentLength > Int64(self.maxRemoteConfigBytes) {
            throw self.remoteConfigTooLargeError(limit: self.maxRemoteConfigBytes)
        }

        var data = Data()
        data.reserveCapacity(min(self.maxRemoteConfigBytes, 64 * 1024))
        for try await byte in bytes {
            if data.count >= self.maxRemoteConfigBytes {
                throw self.remoteConfigTooLargeError(limit: self.maxRemoteConfigBytes)
            }
            data.append(byte)
        }
        return data
    }

    private func remoteConfigTooLargeError(limit: Int) -> NSError {
        NSError(
            domain: "ClashBar.ConfigImport",
            code: 413,
            userInfo: [NSLocalizedDescriptionKey: "Remote config exceeds size limit (\(limit) bytes)"])
    }
}
