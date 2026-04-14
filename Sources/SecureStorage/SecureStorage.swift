import Foundation
import Security
import SharedModels

// MARK: - Secure Storage Error

public enum SecureStorageError: Error, LocalizedError {
    case storeFailed(OSStatus)
    case retrieveFailed(OSStatus)
    case deleteFailed(OSStatus)
    case encodingFailed

    public var errorDescription: String? {
        switch self {
        case .storeFailed(let status):
            "Failed to store secret: \(SecCopyErrorMessageString(status, nil) as String? ?? "code \(status)")"
        case .retrieveFailed(let status):
            "Failed to retrieve secret: \(SecCopyErrorMessageString(status, nil) as String? ?? "code \(status)")"
        case .deleteFailed(let status):
            "Failed to delete secret: \(SecCopyErrorMessageString(status, nil) as String? ?? "code \(status)")"
        case .encodingFailed:
            "Failed to encode value as UTF-8"
        }
    }
}

// MARK: - Secure Storage

public struct SecureStorage: Sendable {
    private let service: String

    public init(service: String = "com.terminus.app") {
        self.service = service
    }

    // MARK: - Store

    public func store(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw SecureStorageError.encodingFailed
        }

        // Try to update first
        let updateQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]

        let updateAttributes: [String: Any] = [
            kSecValueData as String: data,
        ]

        var status = SecItemUpdate(updateQuery as CFDictionary, updateAttributes as CFDictionary)

        if status == errSecItemNotFound {
            // Item doesn't exist, add it
            var addQuery = updateQuery
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

            status = SecItemAdd(addQuery as CFDictionary, nil)
        }

        guard status == errSecSuccess else {
            throw SecureStorageError.storeFailed(status)
        }
    }

    // MARK: - Retrieve

    public func retrieve(key: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess, let data = result as? Data else {
            throw SecureStorageError.retrieveFailed(status)
        }

        return String(data: data, encoding: .utf8)
    }

    // MARK: - Delete

    public func delete(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecureStorageError.deleteFailed(status)
        }
    }

    // MARK: - Exists

    public func exists(key: String) throws -> Bool {
        let value = try retrieve(key: key)
        return value != nil
    }
}

// MARK: - Well-known Keys

extension SecureStorage {
    public static let openRouterAPIKey = "openrouter_api_key"
}
