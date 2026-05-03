//
//  Credentials.swift
//  spacetimedb-swift-sdk
//
//  Keychain-backed token + identity persistence so apps don't
//  have to re-implement TokenStorage from scratch every time.
//
//  Apple-platform Keychain on the default path; falls back to a JSON
//  file at the supplied URL on Linux / for testing. Pass a custom
//  `service` to namespace credentials when the app talks to multiple
//  SpacetimeDB instances.
//

import Foundation
import BSATN
#if canImport(Security)
import Security
#endif

/// Persistable pair of (auth token, server-issued identity). Save it on
/// `IdentityToken` receipt; load it before reconnecting so the server
/// reuses your existing identity instead of issuing a fresh one.
public struct Credentials: Sendable, Codable, Equatable {
    public let token: String
    public let identity: Identity
    public let savedAt: Date

    public init(token: String, identity: Identity, savedAt: Date = Date()) {
        self.token = token
        self.identity = identity
        self.savedAt = savedAt
    }

    public var authenticationToken: AuthenticationToken {
        AuthenticationToken(rawValue: token)
    }
}

public extension Credentials {
    /// Default Keychain service identifier. Override via `service:` if
    /// your app maintains credentials for multiple SpacetimeDB modules.
    static let defaultService = "spacetimedb.swift-sdk.credentials"
    /// Default Keychain account label.
    static let defaultAccount = "default"
}

#if canImport(Security)
public extension Credentials {
    /// Save these credentials to the system Keychain. Replaces any
    /// previously-stored value for the same `(service, account)` pair.
    ///
    /// **Headless caveat**: on macOS, Keychain access from an unsigned
    /// or non-app-bundle binary (e.g. `swift run`, command-line tests,
    /// CI runners) may prompt for Touch ID / login password and *block
    /// indefinitely* if no UI is available to respond. For headless
    /// tooling, use the file-backed overloads below
    /// (`save(to:)` / `load(from:)`) instead.
    func save(service: String = defaultService, account: String = defaultAccount) throws {
        let data = try JSONEncoder().encode(self)
        let query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  account,
        ]
        // Delete any pre-existing entry; SecItemUpdate would partially
        // succeed if the existing item has different attributes.
        SecItemDelete(query as CFDictionary)
        var addAttrs = query
        addAttrs[kSecValueData as String] = data
        let status = SecItemAdd(addAttrs as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SpacetimeDBError.invalidDefinition("Keychain save failed: OSStatus \(status)")
        }
    }

    /// Load credentials from the system Keychain, or `nil` if no entry
    /// exists for the `(service, account)` pair.
    ///
    /// See the headless caveat on `save(service:account:)` — this call
    /// can block on a Keychain authorization prompt when run outside a
    /// signed app bundle. Headless tools should use `load(from:)`.
    static func load(service: String = defaultService, account: String = defaultAccount) throws -> Credentials? {
        let query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  account,
            kSecReturnData as String:   true,
            kSecMatchLimit as String:   kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw SpacetimeDBError.invalidDefinition("Keychain load failed: OSStatus \(status)")
        }
        return try JSONDecoder().decode(Credentials.self, from: data)
    }

    /// Delete the entry for this `(service, account)` pair, if any.
    static func delete(service: String = defaultService, account: String = defaultAccount) throws {
        let query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SpacetimeDBError.invalidDefinition("Keychain delete failed: OSStatus \(status)")
        }
    }
}
#endif

public extension Credentials {
    /// File-based fallback persistence. Writes JSON to `url` (atomic).
    /// Useful for tests, Linux, or when the user wants a file-backed
    /// store rather than the Keychain.
    func save(to url: URL) throws {
        let data = try JSONEncoder().encode(self)
        try data.write(to: url, options: .atomic)
    }

    /// Load credentials from a file written by `save(to:)`. Returns
    /// `nil` if the file doesn't exist; throws on decode failure.
    static func load(from url: URL) throws -> Credentials? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Credentials.self, from: data)
    }
}
