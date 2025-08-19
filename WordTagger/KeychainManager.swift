import Foundation
import Security

// MARK: - Keychain Manager
class KeychainManager {
    static let shared = KeychainManager()
    
    private let service: String
    
    init(service: String = "com.wordtagger.git") {
        self.service = service
    }
    
    // MARK: - Generic Keychain Operations
    func save<T: Codable>(_ item: T, for key: String) throws {
        let data = try JSONEncoder().encode(item)
        try saveData(data, for: key)
    }
    
    func load<T: Codable>(_ type: T.Type, for key: String) throws -> T? {
        guard let data = try loadData(for: key) else {
            return nil
        }
        return try JSONDecoder().decode(type, from: data)
    }
    
    func delete(for key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deletionFailed(status)
        }
    }
    
    // MARK: - Raw Data Operations
    private func saveData(_ data: Data, for key: String) throws {
        // Delete existing item first
        try? delete(for: key)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }
    
    private func loadData(for key: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.loadFailed(status)
        }
    }
    
    // MARK: - Git-Specific Operations
    func saveGitCredentials(_ credentials: GitCredentials, for repositoryURL: String) throws {
        let key = gitCredentialsKey(for: repositoryURL, username: credentials.username)
        try save(credentials, for: key)
    }
    
    func loadGitCredentials(for repositoryURL: String, username: String) throws -> GitCredentials? {
        let key = gitCredentialsKey(for: repositoryURL, username: username)
        return try load(GitCredentials.self, for: key)
    }
    
    func loadAllGitCredentials(for repositoryURL: String) throws -> [GitCredentials] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let items = result as? [[String: Any]] else {
            if status == errSecItemNotFound {
                return []
            }
            throw KeychainError.loadFailed(status)
        }
        
        var credentials: [GitCredentials] = []
        let prefix = "git:\(repositoryURL):"
        
        for item in items {
            if let account = item[kSecAttrAccount as String] as? String,
               account.hasPrefix(prefix),
               let data = item[kSecValueData as String] as? Data {
                
                do {
                    let credential = try JSONDecoder().decode(GitCredentials.self, from: data)
                    credentials.append(credential)
                } catch {
                    // Skip invalid entries
                    continue
                }
            }
        }
        
        return credentials
    }
    
    func deleteGitCredentials(for repositoryURL: String, username: String) throws {
        let key = gitCredentialsKey(for: repositoryURL, username: username)
        try delete(for: key)
    }
    
    func deleteAllGitCredentials(for repositoryURL: String) throws {
        let credentials = try loadAllGitCredentials(for: repositoryURL)
        for credential in credentials {
            try deleteGitCredentials(for: repositoryURL, username: credential.username)
        }
    }
    
    private func gitCredentialsKey(for repositoryURL: String, username: String) -> String {
        return "git:\(repositoryURL):\(username)"
    }
}

// MARK: - Keychain Errors
enum KeychainError: Error, LocalizedError {
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)
    case deletionFailed(OSStatus)
    case invalidData
    
    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Failed to save to keychain (status: \(status))"
        case .loadFailed(let status):
            return "Failed to load from keychain (status: \(status))"
        case .deletionFailed(let status):
            return "Failed to delete from keychain (status: \(status))"
        case .invalidData:
            return "Invalid data format in keychain"
        }
    }
}

// MARK: - GitCredentials Codable Extension
extension GitCredentials: Codable {
    enum CodingKeys: String, CodingKey {
        case username
        case token
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        username = try container.decode(String.self, forKey: .username)
        token = try container.decode(String.self, forKey: .token)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(username, forKey: .username)
        try container.encode(token, forKey: .token)
    }
}