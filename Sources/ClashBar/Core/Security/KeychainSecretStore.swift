import Foundation
import Security

final class KeychainSecretStore: SecretStore {
    private let service = "com.clashbar.controller"
    private let account = "default"

    func loadControllerSecret() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.service,
            kSecAttrAccount as String: self.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let secret = String(data: data, encoding: .utf8),
              !secret.isEmpty
        else {
            return nil
        }
        return secret
    }

    func saveControllerSecret(_ value: String?) throws {
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.service,
            kSecAttrAccount as String: self.account,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        guard let value, !value.isEmpty else { return }

        let data = Data(value.utf8)
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.service,
            kSecAttrAccount as String: self.account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data,
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(
                domain: "ClashBar.Keychain",
                code: Int(status),
                userInfo: [
                    NSLocalizedDescriptionKey: "Failed to save controller secret to Keychain (status=\(status))",
                ])
        }
    }
}
