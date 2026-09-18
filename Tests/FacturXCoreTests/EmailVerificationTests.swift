import XCTest
@testable import FacturXCore

final class EmailVerificationTests: XCTestCase {

    // MARK: - Migration Codable

    func testDecodingLegacyUserWithoutVerificationFieldsDefaultsToVerified() throws {
        // Un compte persisté avant cette fonctionnalité n'a pas ces clés dans son JSON —
        // il doit rester utilisable (pas de blocage rétroactif de la base existante).
        let json = """
        {"id":"\(UUID().uuidString)","username":"legacy@exemple.fr","displayName":"",
        "role":"comptable","roles":["comptable"],"passwordHash":"h","salt":"s",
        "societyIDs":[],"isActive":true,"createdAt":\(Date().timeIntervalSince1970),
        "mustChangePassword":false,"failedLoginAttempts":0,"totpEnabled":false,
        "totpRecoveryCodeHashes":[]}
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let user = try decoder.decode(User.self, from: json)
        XCTAssertTrue(user.emailVerified)
        XCTAssertNil(user.emailVerificationCode)
    }

    func testUserConstructedWithoutArgumentDefaultsToVerified() {
        // Le défaut du paramètre d'init protège tout code (tests, seed admin…) qui
        // construit un User sans se soucier de la vérification d'email.
        let user = User(username: "x@exemple.fr")
        XCTAssertTrue(user.emailVerified)
    }

    // MARK: - createUser : exigence conditionnée à SMTP configuré

    func testCreateUserWithoutSMTPConfiguredDoesNotRequireVerification() throws {
        // Sans SMTP configuré, un compte fraîchement créé serait bloqué sans aucun
        // moyen de recevoir son code — l'exigence est donc désactivée dans ce cas.
        XCTAssertFalse(SMTPSettings.shared.credentials.isConfigured, "précondition : SMTP non configuré dans les tests")
        let store = AuthStore()
        store.testBypassSecurity = true
        store.users = []
        let user = try store.createUser(username: "nosmtp@exemple.fr", password: "Secur3Pass!", role: .admin)
        XCTAssertTrue(user.emailVerified)
    }

    // MARK: - verifyEmail

    func testVerifyEmailWithCorrectCodeActivatesAccount() throws {
        let store = AuthStore()
        store.testBypassSecurity = true
        var user = User(username: "toverify@exemple.fr", role: .admin, emailVerified: false)
        user.emailVerificationCode = "123456"
        user.emailVerificationCodeExpiresAt = Date().addingTimeInterval(3600)
        store.users = [user]

        try store.verifyEmail(code: "123456", for: user)
        XCTAssertTrue(store.users.first(where: { $0.id == user.id })!.emailVerified)
        XCTAssertNil(store.users.first(where: { $0.id == user.id })!.emailVerificationCode)
    }

    func testVerifyEmailWithWrongCodeThrowsAndLeavesAccountUnverified() throws {
        let store = AuthStore()
        store.testBypassSecurity = true
        var user = User(username: "wrongcode@exemple.fr", role: .admin, emailVerified: false)
        user.emailVerificationCode = "123456"
        user.emailVerificationCodeExpiresAt = Date().addingTimeInterval(3600)
        store.users = [user]

        XCTAssertThrowsError(try store.verifyEmail(code: "000000", for: user)) { error in
            guard case AuthError.invalidVerificationCode = error else {
                return XCTFail("Attendu AuthError.invalidVerificationCode, eu \(error)")
            }
        }
        XCTAssertFalse(store.users.first(where: { $0.id == user.id })!.emailVerified)
    }

    func testVerifyEmailWithExpiredCodeThrows() throws {
        let store = AuthStore()
        store.testBypassSecurity = true
        var user = User(username: "expired@exemple.fr", role: .admin, emailVerified: false)
        user.emailVerificationCode = "654321"
        user.emailVerificationCodeExpiresAt = Date().addingTimeInterval(-60) // déjà expiré
        store.users = [user]

        XCTAssertThrowsError(try store.verifyEmail(code: "654321", for: user)) { error in
            guard case AuthError.verificationCodeExpired = error else {
                return XCTFail("Attendu AuthError.verificationCodeExpired, eu \(error)")
            }
        }
    }

    func testVerifyEmailUpdatesCurrentUserWhenSelfVerifying() throws {
        let store = AuthStore()
        store.testBypassSecurity = true
        var user = User(username: "self@exemple.fr", role: .comptable, societyIDs: [UUID()], emailVerified: false)
        user.emailVerificationCode = "111222"
        user.emailVerificationCodeExpiresAt = Date().addingTimeInterval(3600)
        store.users = [user]
        store.currentUser = user

        try store.verifyEmail(code: "111222", for: user)
        XCTAssertEqual(store.currentUser?.emailVerified, true, "currentUser doit refléter l'activation immédiatement (sans re-login)")
    }

    // MARK: - sendEmailVerificationCode

    func testSendVerificationCodeThrowsWhenSMTPNotConfigured() async throws {
        XCTAssertFalse(SMTPSettings.shared.credentials.isConfigured, "précondition : SMTP non configuré dans les tests")
        let store = AuthStore()
        store.testBypassSecurity = true
        let user = User(username: "needscode@exemple.fr", role: .admin, emailVerified: false)
        store.users = [user]

        do {
            try await store.sendEmailVerificationCode(to: user)
            XCTFail("Devait lever AuthError.verificationEmailNotConfigured")
        } catch AuthError.verificationEmailNotConfigured {
            // attendu
        }
    }
}
