import XCTest
@testable import FacturXCore

final class TOTPServiceTests: XCTestCase {

    /// Vecteur de test officiel RFC 6238 Annexe B (secret ASCII "12345678901234567890",
    /// SHA1, T=59s -> compteur 1, 8 chiffres attendus "94287082"). Vérifié indépendamment
    /// contre une implémentation Python de référence avant d'écrire ce test.
    func testMatchesRFC6238KnownVector() {
        let secretBase32 = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
        let date = Date(timeIntervalSince1970: 59)
        let code = TOTPService.code(secret: secretBase32, date: date, step: 30, digits: 8)
        XCTAssertEqual(code, "94287082")
    }

    func testBase32RoundTrip() {
        let data = Data([0x00, 0xFF, 0x42, 0x13, 0x37, 0xAA, 0xBB, 0xCC, 0xDD])
        let encoded = TOTPService.base32Encode(data)
        let decoded = TOTPService.base32Decode(encoded)
        XCTAssertEqual(decoded, data)
    }

    func testGeneratedSecretProducesVerifiableCode() {
        let secret = TOTPService.generateSecret()
        guard let code = TOTPService.code(secret: secret) else {
            return XCTFail("le secret généré doit produire un code")
        }
        XCTAssertEqual(code.count, 6)
        XCTAssertTrue(TOTPService.verify(code: code, secret: secret))
    }

    func testVerifyRejectsWrongCode() {
        let secret = TOTPService.generateSecret()
        XCTAssertFalse(TOTPService.verify(code: "000000", secret: secret, date: Date(timeIntervalSince1970: 1_700_000_000)))
    }

    func testVerifyToleratesOneStepClockDrift() {
        let secret = TOTPService.generateSecret()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        guard let codeOneStepAhead = TOTPService.code(secret: secret, date: now.addingTimeInterval(30)) else {
            return XCTFail()
        }
        XCTAssertTrue(TOTPService.verify(code: codeOneStepAhead, secret: secret, date: now, window: 1))
    }

    func testVerifyRejectsCodeOutsideWindow() {
        let secret = TOTPService.generateSecret()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        guard let codeFarAhead = TOTPService.code(secret: secret, date: now.addingTimeInterval(300)) else {
            return XCTFail()
        }
        XCTAssertFalse(TOTPService.verify(code: codeFarAhead, secret: secret, date: now, window: 1))
    }

    func testProvisioningURIContainsSecretAndIssuer() {
        let uri = TOTPService.provisioningURI(secret: "ABCD1234", accountName: "alice@exemple.fr")
        XCTAssertTrue(uri.hasPrefix("otpauth://totp/"))
        XCTAssertTrue(uri.contains("secret=ABCD1234"))
        XCTAssertTrue(uri.contains("Facture_elec"))
    }
}

final class RecoveryCodeGeneratorTests: XCTestCase {
    func testGeneratesTenUniqueFormattedCodes() {
        let codes = RecoveryCodeGenerator.generate()
        XCTAssertEqual(codes.count, 10)
        XCTAssertEqual(Set(codes).count, 10, "les codes doivent être uniques")
        for code in codes {
            XCTAssertEqual(code.count, 9, "format XXXX-XXXX")
            XCTAssertTrue(code.contains("-"))
        }
    }

    func testNormalizeTrimsAndUppercases() {
        XCTAssertEqual(RecoveryCodeGenerator.normalize("  ab12-cd34 "), "AB12-CD34")
    }
}

final class TwoFactorAuthStoreTests: XCTestCase {

    private func makeUser(totpEnabled: Bool = false) -> (User, AuthStore) {
        let store = AuthStore()
        // Une session réussie d'un test précédent peut avoir été restaurée depuis
        // UserDefaults (comportement production voulu) : on repart d'un état propre.
        store.currentUser = nil
        store.testBypassSecurity = true
        store.users = []
        let salt = PasswordHasher.generateSalt()
        let hash = PasswordHasher.hash(password: "pw1234", salt: salt)
        var user = User(username: "marie2fa@exemple.fr", displayName: "Marie", role: .comptable,
                         passwordHash: hash, salt: salt, societyIDs: [])
        if totpEnabled {
            let secret = TOTPService.generateSecret()
            user.totpEnabled = true
            user.totpSecret = secret
        }
        store.users = [user]
        return (user, store)
    }

    override func tearDown() {
        TwoFactorSettings.shared.enabledSolutionWide = false
        super.tearDown()
    }

    func testLoginUnaffectedWhenGlobalToggleIsOff() throws {
        TwoFactorSettings.shared.enabledSolutionWide = false
        let (user, store) = makeUser(totpEnabled: true)
        store.testBypassSecurity = false
        let logged = try store.login(username: user.username, password: "pw1234")
        XCTAssertEqual(logged.id, user.id)
        XCTAssertEqual(store.currentUser?.id, user.id)
    }

    func testLoginRequiresTwoFactorWhenEnabledGloballyAndOnUser() throws {
        TwoFactorSettings.shared.enabledSolutionWide = true
        let (user, store) = makeUser(totpEnabled: true)
        store.testBypassSecurity = false
        XCTAssertThrowsError(try store.login(username: user.username, password: "pw1234")) { error in
            guard case AuthError.twoFactorRequired(let userID) = error else {
                return XCTFail("attendu twoFactorRequired, obtenu \(error)")
            }
            XCTAssertEqual(userID, user.id)
        }
        XCTAssertNil(store.currentUser, "la session ne doit pas être ouverte avant vérification du second facteur")
    }

    func testCompleteTwoFactorLoginWithValidCodeSucceeds() throws {
        TwoFactorSettings.shared.enabledSolutionWide = true
        let (user, store) = makeUser(totpEnabled: true)
        store.testBypassSecurity = false
        XCTAssertThrowsError(try store.login(username: user.username, password: "pw1234"))
        guard let code = TOTPService.code(secret: user.totpSecret!) else { return XCTFail() }
        let logged = try store.completeTwoFactorLogin(userID: user.id, code: code)
        XCTAssertEqual(logged.id, user.id)
        XCTAssertEqual(store.currentUser?.id, user.id)
    }

    func testCompleteTwoFactorLoginWithWrongCodeFails() throws {
        TwoFactorSettings.shared.enabledSolutionWide = true
        let (user, store) = makeUser(totpEnabled: true)
        store.testBypassSecurity = false
        XCTAssertThrowsError(try store.login(username: user.username, password: "pw1234"))
        XCTAssertThrowsError(try store.completeTwoFactorLogin(userID: user.id, code: "000000")) { error in
            guard case AuthError.wrongTwoFactorCode = error else {
                return XCTFail("attendu wrongTwoFactorCode, obtenu \(error)")
            }
        }
        XCTAssertNil(store.currentUser)
    }

    func testEnrollmentRequiresCorrectCodeAndGeneratesRecoveryCodes() throws {
        TwoFactorSettings.shared.enabledSolutionWide = true
        let (user, store) = makeUser(totpEnabled: false)
        let (secret, uri) = store.beginEnrollTwoFactor(for: user)
        XCTAssertTrue(uri.contains(secret))
        XCTAssertThrowsError(try store.confirmEnrollTwoFactor(for: user, secret: secret, code: "000000"))
        guard let validCode = TOTPService.code(secret: secret) else { return XCTFail() }
        let recoveryCodes = try store.confirmEnrollTwoFactor(for: user, secret: secret, code: validCode)
        XCTAssertEqual(recoveryCodes.count, 10)
        let updated = store.users.first(where: { $0.id == user.id })
        XCTAssertEqual(updated?.totpEnabled, true)
        XCTAssertEqual(updated?.totpSecret, secret)
    }

    func testRecoveryCodeIsSingleUse() throws {
        TwoFactorSettings.shared.enabledSolutionWide = true
        let (user, store) = makeUser(totpEnabled: false)
        let (secret, _) = store.beginEnrollTwoFactor(for: user)
        guard let validCode = TOTPService.code(secret: secret) else { return XCTFail() }
        let recoveryCodes = try store.confirmEnrollTwoFactor(for: user, secret: secret, code: validCode)
        let enrolledUser = store.users.first(where: { $0.id == user.id })!
        store.testBypassSecurity = false

        XCTAssertThrowsError(try store.login(username: enrolledUser.username, password: "pw1234"))
        let firstAttempt = try store.completeTwoFactorLogin(userID: enrolledUser.id, code: recoveryCodes[0])
        XCTAssertEqual(firstAttempt.id, enrolledUser.id)

        store.currentUser = nil
        XCTAssertThrowsError(try store.login(username: enrolledUser.username, password: "pw1234"))
        XCTAssertThrowsError(try store.completeTwoFactorLogin(userID: enrolledUser.id, code: recoveryCodes[0]),
                              "un code de récupération déjà utilisé ne doit plus être accepté")
    }

    func testEnrollmentRefusedWhenDisabledGlobally() throws {
        TwoFactorSettings.shared.enabledSolutionWide = false
        let (user, store) = makeUser(totpEnabled: false)
        let (secret, _) = store.beginEnrollTwoFactor(for: user)
        guard let validCode = TOTPService.code(secret: secret) else { return XCTFail() }
        XCTAssertThrowsError(try store.confirmEnrollTwoFactor(for: user, secret: secret, code: validCode)) { error in
            guard case AuthError.twoFactorDisabledGlobally = error else {
                return XCTFail("attendu twoFactorDisabledGlobally, obtenu \(error)")
            }
        }
    }

    func testDisableTwoFactorClearsSecretAndRecoveryCodes() throws {
        TwoFactorSettings.shared.enabledSolutionWide = true
        let (user, store) = makeUser(totpEnabled: false)
        let (secret, _) = store.beginEnrollTwoFactor(for: user)
        guard let validCode = TOTPService.code(secret: secret) else { return XCTFail() }
        _ = try store.confirmEnrollTwoFactor(for: user, secret: secret, code: validCode)
        let enrolledUser = store.users.first(where: { $0.id == user.id })!

        store.disableTwoFactor(for: enrolledUser, actor: "admin@exemple.fr")
        let updated = store.users.first(where: { $0.id == user.id })
        XCTAssertEqual(updated?.totpEnabled, false)
        XCTAssertNil(updated?.totpSecret)
        XCTAssertTrue(updated?.totpRecoveryCodeHashes.isEmpty ?? false)
    }

    func testUserDecodingDefaultsTwoFactorFieldsForOlderPersistedData() throws {
        let legacyJSON = """
        {"id":"\(UUID().uuidString)","username":"legacy@exemple.fr","displayName":"Legacy",
         "role":"comptable","roles":["comptable"],"passwordHash":"h","salt":"s",
         "societyIDs":[],"isActive":true,"createdAt":0,"mustChangePassword":false,
         "failedLoginAttempts":0}
        """
        let decoded = try JSONDecoder().decode(User.self, from: Data(legacyJSON.utf8))
        XCTAssertFalse(decoded.totpEnabled)
        XCTAssertNil(decoded.totpSecret)
        XCTAssertTrue(decoded.totpRecoveryCodeHashes.isEmpty)
    }
}
