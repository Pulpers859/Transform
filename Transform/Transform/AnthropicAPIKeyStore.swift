import Foundation
import Security

enum AnthropicAPIKeyStore {
    private static let service = Bundle.main.bundleIdentifier ?? "Patrick-App.Transform"
    private static let account = "anthropic-api-key"

    static var storedKey: String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty else {
            return nil
        }
        return key
    }

    static func save(_ rawKey: String) throws {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw APIKeyStoreError.emptyKey
        }
        guard !placeholderValues.contains(key.lowercased()) else {
            throw APIKeyStoreError.placeholderKey
        }
        guard let data = key.data(using: .utf8) else {
            throw APIKeyStoreError.invalidEncoding
        }

        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(identity as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var newItem = identity
            attributes.forEach { newItem[$0.key] = $0.value }
            let addStatus = SecItemAdd(newItem as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw APIKeyStoreError.keychainStatus(addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw APIKeyStoreError.keychainStatus(updateStatus)
        }
    }

    static func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw APIKeyStoreError.keychainStatus(status)
        }
    }

    private static let placeholderValues: Set<String> = [
        "your_api_key_here",
        "your_real_key",
        "sk-ant-your-real-key-goes-here"
    ]
}

enum APIKeyStoreError: LocalizedError {
    case emptyKey
    case placeholderKey
    case invalidEncoding
    case keychainStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .emptyKey:
            return "Enter your Anthropic API key."
        case .placeholderKey:
            return "Replace the example text with your real Anthropic API key."
        case .invalidEncoding:
            return "The API key could not be encoded."
        case .keychainStatus(let status):
            return "The API key could not be stored in Keychain (error \(status))."
        }
    }
}
