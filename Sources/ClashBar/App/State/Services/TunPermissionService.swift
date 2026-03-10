import Foundation

enum TunPermissionServiceError: LocalizedError {
    case coreBinaryNotFound
    case coreBinaryNotExecutable
    case permissionMissing
    case authorizationCancelled
    case authorizationFailed(String)
    case permissionVerificationFailed

    var errorDescription: String? {
        switch self {
        case .coreBinaryNotFound:
            "mihomo binary not found."
        case .coreBinaryNotExecutable:
            "mihomo binary is not executable."
        case .permissionMissing:
            "mihomo binary does not have required TUN privileges."
        case .authorizationCancelled:
            "Administrator authorization was cancelled."
        case let .authorizationFailed(message):
            "Failed to authorize TUN privileges: \(message)"
        case .permissionVerificationFailed:
            "TUN privileges were not applied successfully."
        }
    }
}

struct TunPermissionService {
    func hasRequiredPermissions(binaryPath: String) -> Bool {
        let normalizedPath = binaryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPath.isEmpty else { return false }

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: normalizedPath) else { return false }

        do {
            let attributes = try fileManager.attributesOfItem(atPath: normalizedPath)
            let ownerID = (attributes[.ownerAccountID] as? NSNumber)?.intValue
            let mode = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0

            // TUN mode on macOS requires root owner + setuid bit on the core binary.
            let hasRootOwner = ownerID == 0
            let hasSetuid = (mode & 0o4000) != 0
            let ownerExecutable = (mode & 0o100) != 0
            return hasRootOwner && hasSetuid && ownerExecutable
        } catch {
            return false
        }
    }

    func grantPermissions(binaryPath: String) async throws {
        let resolvedBinaryPath = try validateBinaryPath(binaryPath)
        try await Task.detached(priority: .userInitiated) {
            try self.grantPermissionsSynchronously(binaryPath: resolvedBinaryPath)
        }.value
    }

    func validateCurrentPermissions(binaryPath: String) throws {
        let resolvedBinaryPath = try validateBinaryPath(binaryPath)
        guard self.hasRequiredPermissions(binaryPath: resolvedBinaryPath) else {
            throw TunPermissionServiceError.permissionMissing
        }
    }

    private func validateBinaryPath(_ binaryPath: String) throws -> String {
        let resolvedBinaryPath = binaryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolvedBinaryPath.isEmpty else {
            throw TunPermissionServiceError.coreBinaryNotFound
        }

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: resolvedBinaryPath) else {
            throw TunPermissionServiceError.coreBinaryNotFound
        }
        guard fileManager.isExecutableFile(atPath: resolvedBinaryPath) else {
            throw TunPermissionServiceError.coreBinaryNotExecutable
        }
        return resolvedBinaryPath
    }

    private func grantPermissionsSynchronously(binaryPath: String) throws {
        let escapedPath = self.shellQuoted(binaryPath)
        let shellCommand = "/usr/sbin/chown root:admin \(escapedPath) && /bin/chmod u+s \(escapedPath)"
        let appleScript = "do shell script \"\(appleScriptEscaped(shellCommand))\" with administrator privileges"
        try runAppleScriptSynchronously(appleScript)

        guard self.hasRequiredPermissions(binaryPath: binaryPath) else {
            throw TunPermissionServiceError.permissionVerificationFailed
        }
    }

    private func runAppleScriptSynchronously(_ script: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw TunPermissionServiceError.authorizationFailed(error.localizedDescription)
        }

        guard process.terminationStatus == 0 else {
            let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let message = [stderr, stdout]
                .first(where: { !$0.isEmpty }) ?? "Unknown authorization error."
            if message.lowercased().contains("user canceled") {
                throw TunPermissionServiceError.authorizationCancelled
            }
            throw TunPermissionServiceError.authorizationFailed(message)
        }
    }

    private func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }

    private func appleScriptEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
