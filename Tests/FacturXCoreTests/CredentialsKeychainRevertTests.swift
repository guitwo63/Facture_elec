import XCTest
@testable import FacturXCore

/// Couvre le retour arrière (2026-09-18) du stockage des identifiants sensibles
/// (SMTP, pCloud, Chorus Pro, SUPER PDP) : depuis le Keychain (instable — voir
/// KeychainStore.swift, signature "ad hoc" changeant à chaque build) vers UserDefaults
/// en clair, avec migration one-shot d'un secret resté dans le Keychain d'une build
/// précédente.
final class CredentialsKeychainRevertTests: XCTestCase {

    private let env = AppEnvironment.shared

    override func tearDown() {
        for key in [
            "facturx.smtp.credentials.v1", "facturx.smtp.password.v1",
            "facturx.pcloud.credentials.v1", "facturx.pcloud.password.v1",
            "facturx.choruspro.credentials.v1", "facturx.choruspro.clientSecret.v1", "facturx.choruspro.techPassword.v1",
            "facturx.superpdp.credentials.v1", "facturx.superpdp.clientSecret.v1"
        ] {
            UserDefaults.standard.removeObject(forKey: env.key(key))
            KeychainStore.delete(forKey: env.key(key))
        }
        super.tearDown()
    }

    // MARK: - SMTP

    func testSMTPSettingsMigratesPasswordFromLegacyKeychainEntry() throws {
        var legacy = SMTPCredentials(host: "smtp.exemple.fr", fromAddress: "a@exemple.fr")
        legacy.password = ""
        UserDefaults.standard.set(try JSONEncoder().encode(legacy), forKey: env.key("facturx.smtp.credentials.v1"))
        KeychainStore.set("s3cret-smtp", forKey: env.key("facturx.smtp.password.v1"))

        let settings = SMTPSettings()
        XCTAssertEqual(settings.credentials.password, "s3cret-smtp")
    }

    func testSMTPSettingsSavePersistsPasswordInPlainUserDefaultsAndClearsKeychain() throws {
        let settings = SMTPSettings()
        settings.credentials = SMTPCredentials(host: "smtp.exemple.fr", password: "p4ssw0rd", fromAddress: "a@exemple.fr")
        settings.save()

        let data = UserDefaults.standard.data(forKey: env.key("facturx.smtp.credentials.v1"))
        let decoded = try JSONDecoder().decode(SMTPCredentials.self, from: XCTUnwrap(data))
        XCTAssertEqual(decoded.password, "p4ssw0rd", "le mot de passe doit être persisté directement dans le JSON, plus dans le Keychain")
        XCTAssertNil(KeychainStore.get(forKey: env.key("facturx.smtp.password.v1")), "l'ancienne entrée Keychain doit être nettoyée")
    }

    // MARK: - pCloud

    func testPCloudSettingsMigratesPasswordFromLegacyKeychainEntry() throws {
        var legacy = PCloudCredentials()
        legacy.password = ""
        UserDefaults.standard.set(try JSONEncoder().encode(legacy), forKey: env.key("facturx.pcloud.credentials.v1"))
        KeychainStore.set("s3cret-pcloud", forKey: env.key("facturx.pcloud.password.v1"))

        let settings = PCloudSettings()
        XCTAssertEqual(settings.credentials.password, "s3cret-pcloud")
    }

    // MARK: - Chorus Pro

    func testChorusProSettingsMigratesBothSecretsFromLegacyKeychainEntries() throws {
        var legacy = ChorusProCredentials(clientID: "id", clientSecret: "")
        legacy.techPassword = ""
        UserDefaults.standard.set(try JSONEncoder().encode(legacy), forKey: env.key("facturx.choruspro.credentials.v1"))
        KeychainStore.set("s3cret-clientsecret", forKey: env.key("facturx.choruspro.clientSecret.v1"))
        KeychainStore.set("s3cret-techpassword", forKey: env.key("facturx.choruspro.techPassword.v1"))

        let settings = ChorusProSettings()
        XCTAssertEqual(settings.credentials.clientSecret, "s3cret-clientsecret")
        XCTAssertEqual(settings.credentials.techPassword, "s3cret-techpassword")
    }

    // MARK: - SUPER PDP

    func testSuperPDPSettingsMigratesClientSecretFromLegacyKeychainEntry() throws {
        var legacy = SuperPDPCredentials(clientID: "id", clientSecret: "")
        legacy.clientSecret = ""
        UserDefaults.standard.set(try JSONEncoder().encode(legacy), forKey: env.key("facturx.superpdp.credentials.v1"))
        KeychainStore.set("s3cret-superpdp", forKey: env.key("facturx.superpdp.clientSecret.v1"))

        let settings = SuperPDPSettings()
        XCTAssertEqual(settings.credentials.clientSecret, "s3cret-superpdp")
    }

    func testSuperPDPSettingsSavePersistsClientSecretInPlainUserDefaults() throws {
        let settings = SuperPDPSettings()
        settings.credentials = SuperPDPCredentials(clientID: "id", clientSecret: "s3cret")
        settings.save()

        let data = UserDefaults.standard.data(forKey: env.key("facturx.superpdp.credentials.v1"))
        let decoded = try JSONDecoder().decode(SuperPDPCredentials.self, from: XCTUnwrap(data))
        XCTAssertEqual(decoded.clientSecret, "s3cret")
        XCTAssertNil(KeychainStore.get(forKey: env.key("facturx.superpdp.clientSecret.v1")))
    }
}
