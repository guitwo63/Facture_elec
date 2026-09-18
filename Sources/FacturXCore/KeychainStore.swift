import Foundation
import Security

/// Wrapper minimal autour du Keychain macOS, pour les seuls champs sensibles
/// (mots de passe, secrets) des identifiants d'intégration (SMTP, pCloud,
/// Chorus Pro, SUPER PDP). Avant cette version, ces valeurs étaient stockées
/// en clair dans UserDefaults (~/Library/Preferences/*.plist), lisibles par
/// tout process tournant sous le même compte utilisateur. Le reste des
/// identifiants (host, port, région, identifiants publics non sensibles)
/// continue de vivre dans UserDefaults, inchangé.
///
/// L'app étant distribuée signée « ad hoc » (pas de compte Apple Developer,
/// voir scripts/package-mac.sh), macOS peut redemander l'autorisation d'accès
/// au Keychain après chaque reconstruction du binaire (l'identité de
/// signature change) — attendu tant que l'app n'est pas signée Developer ID.
public enum KeychainStore {
    private static let service = "fr.arverneo.facturxmacapp"

    public static func set(_ value: String, forKey key: String) {
        guard !value.isEmpty else {
            delete(forKey: key)
            return
        }
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var newItem = query
            newItem[kSecValueData as String] = data
            SecItemAdd(newItem as CFDictionary, nil)
        }
    }

    public static func get(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func delete(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
