import Foundation
import Security

/// Wrapper minimal autour du Keychain macOS. Utilisé un temps pour les champs
/// sensibles (mots de passe, secrets) des identifiants d'intégration (SMTP,
/// pCloud, Chorus Pro, SUPER PDP), avant un retour arrière volontaire
/// (2026-09-18) : l'app étant distribuée signée « ad hoc » (pas de compte
/// Apple Developer, voir scripts/package-mac.sh), une entrée Keychain créée
/// par une build devient inaccessible à la build suivante (signature ad hoc
/// différente à chaque reconstruction) — le mot de passe semblait "effacé"
/// à chaque mise à jour de l'app. Les identifiants sensibles sont donc
/// revenus en clair dans UserDefaults (`*Settings.save()`), comme le reste
/// des champs de configuration.
///
/// Ce wrapper est conservé (inutilisé pour l'instant) pour une éventuelle
/// réactivation si l'app passe en mode SaaS (signature stable / autre
/// mécanisme de secret côté serveur) : `*Settings.init()` migre encore, une
/// seule fois, un secret resté dans le Keychain d'une build précédente.
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
