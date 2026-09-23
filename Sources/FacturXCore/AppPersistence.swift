import Foundation
import Security

/// Où l'app persiste son état : le domaine UserDefaults de tous les stores (factures,
/// annuaire, réglages, journal d'audit…) et le service du Trousseau de `KeychainStore`.
///
/// Dans l'app, rien ne change : `UserDefaults.standard` et le service
/// "fr.arverneo.facturxmacapp".
///
/// Dans un processus de tests (XCTest chargé : `swift test`, `xcrun xctest`), une suite
/// UserDefaults et un service du Trousseau propres au processus, suffixés d'un UUID et
/// vidés à sa sortie. Avant, les tests écrivaient avec des clés fixes dans le domaine
/// UserDefaults du processus `xctest`, commun à toutes ses exécutions, et dans le service
/// réel de l'app. Deux `swift test` simultanés (sessions en parallèle, un worktree chacune)
/// se marchaient dessus et des tests échouaient au hasard. Chaque exécution effaçait aussi
/// les anciennes entrées Trousseau de l'app (`facturx.smtp.password.v1`…).
///
/// Le choix se fait ici plutôt que par injection depuis les tests : XCTest instancie tous
/// les cas de test avant le premier `setUp`, et leurs propriétés touchent déjà des
/// singletons (`AppEnvironment.shared`…) qui lisent UserDefaults dès leur création.
public enum AppPersistence {
    /// Domaine UserDefaults de tous les stores.
    public static let defaults: UserDefaults = unitTestRun?.defaults ?? .standard

    /// Service du Trousseau de `KeychainStore`.
    public static let keychainService: String = unitTestRun?.name ?? appKeychainService

    static let appKeychainService = "fr.arverneo.facturxmacapp"

    /// Non nil seulement dans un processus de tests : l'app ne lie pas XCTest.
    static let unitTestRun: UnitTestRun? = {
        guard NSClassFromString("XCTestCase") != nil else { return nil }
        UnitTestRun.removePlists(olderThan: 2 * 60)
        // `xctest` se termine par exit(), qui déclenche le nettoyage. Un crash laisse la
        // suite et le service derrière lui, sans gêner les exécutions suivantes.
        atexit { AppPersistence.unitTestRun?.erase() }
        return UnitTestRun()
    }()

    /// Suite UserDefaults et service du Trousseau d'un processus de tests, sous le même nom
    /// "fr.arverneo.facturxmacapp.tests.<UUID>".
    struct UnitTestRun {
        static let namePrefix = "\(AppPersistence.appKeychainService).tests."

        let name: String
        let defaults: UserDefaults

        init() {
            name = Self.namePrefix + UUID().uuidString
            guard let suite = UserDefaults(suiteName: name) else {
                preconditionFailure("UserDefaults(suiteName:) a refusé \(name)")
            }
            defaults = suite
        }

        /// Vide la suite et supprime toutes les entrées du service. Dans le Trousseau de
        /// session, `SecItemDelete` ne supprime qu'une entrée par appel.
        func erase() {
            defaults.removePersistentDomain(forName: name)
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: name
            ]
            while SecItemDelete(query as CFDictionary) == errSecSuccess {}
        }

        /// Supprime les plist laissés par les exécutions terminées. cfprefsd écrit le plist
        /// (vide) d'une suite effacée quelques secondes après `erase()`, souvent après la
        /// sortie du processus : l'exécution ne peut pas le supprimer elle-même. Une
        /// exécution dure quelques secondes, et le plist d'une suite active est réécrit à
        /// chaque modification : au-delà de `age` sans écriture, l'exécution est terminée.
        static func removePlists(olderThan age: TimeInterval, in directory: URL = preferencesDirectory) {
            let cutoff = Date().addingTimeInterval(-age)
            let files = (try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
            )) ?? []
            for file in files where file.lastPathComponent.hasPrefix(namePrefix) && file.pathExtension == "plist" {
                guard let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                      modified < cutoff else { continue }
                try? FileManager.default.removeItem(at: file)
            }
        }

        static var preferencesDirectory: URL {
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Preferences")
        }
    }
}
