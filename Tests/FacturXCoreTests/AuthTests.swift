import XCTest
import FacturXCore

final class AuthTests: XCTestCase {

    func testPasswordHashDeterministicAndVerifiable() {
        let salt = PasswordHasher.generateSalt()
        XCTAssertFalse(salt.isEmpty)
        let h1 = PasswordHasher.hash(password: "S3cret!", salt: salt)
        let h2 = PasswordHasher.hash(password: "S3cret!", salt: salt)
        XCTAssertEqual(h1, h2, "Le hash doit être déterministe pour un même sel")
        XCTAssertNotEqual(h1, PasswordHasher.hash(password: "other", salt: salt))
        XCTAssertTrue(PasswordHasher.verify(password: "S3cret!", salt: salt, expectedHash: h1))
        XCTAssertFalse(PasswordHasher.verify(password: "wrong", salt: salt, expectedHash: h1))
    }

    func testConstantTimeEquals() {
        XCTAssertTrue(PasswordHasher.constantTimeEquals("abcd", "abcd"))
        XCTAssertFalse(PasswordHasher.constantTimeEquals("abcd", "abce"))
        XCTAssertFalse(PasswordHasher.constantTimeEquals("abcd", "abc"))
    }

    func testEmailValidator() {
        XCTAssertTrue(EmailValidator.isValid("alice@exemple.fr"))
        XCTAssertTrue(EmailValidator.isValid("  bob@exemple.fr  "))
        XCTAssertTrue(EmailValidator.isValid("a.b+c@d.co"))
        XCTAssertFalse(EmailValidator.isValid("pasunemail"))
        XCTAssertFalse(EmailValidator.isValid("@domain.com"))
        XCTAssertFalse(EmailValidator.isValid("user@.com"))
        XCTAssertFalse(EmailValidator.isValid("user@domain"))
        XCTAssertFalse(EmailValidator.isValid("user@domain.c"))
        XCTAssertFalse(EmailValidator.isValid(""))
    }

    func testLoginSuccessAndWrongPassword() throws {
        let store = AuthStore()
        store.testBypassSecurity = true
        store.users = []
        let salt = PasswordHasher.generateSalt()
        let hash = PasswordHasher.hash(password: "pw1234", salt: salt)
        let user = User(username: "marie", displayName: "Marie", role: .comptable,
                        passwordHash: hash, salt: salt, societyIDs: [])
        store.users = [user]

        let logged = try store.login(username: "marie", password: "pw1234")
        XCTAssertEqual(logged.id, user.id)
        XCTAssertNotNil(store.currentUser)

        XCTAssertThrowsError(try store.login(username: "marie", password: "bad")) { error in
            guard case AuthError.wrongPassword = error else {
                return XCTFail("Attendu AuthError.wrongPassword, eu \(error)")
            }
        }
        XCTAssertThrowsError(try store.login(username: "inconnu", password: "x")) { error in
            guard case AuthError.unknownUser = error else {
                return XCTFail("Attendu AuthError.unknownUser, eu \(error)")
            }
        }
    }

    func testInactiveUserCannotLogin() throws {
        let store = AuthStore()
        store.testBypassSecurity = true
        let salt = PasswordHasher.generateSalt()
        let hash = PasswordHasher.hash(password: "pw", salt: salt)
        let user = User(username: "off", role: .comptable, passwordHash: hash, salt: salt, isActive: false)
        store.users = [user]
        store.currentUser = nil
        XCTAssertThrowsError(try store.login(username: "off", password: "pw")) { error in
            guard case AuthError.inactiveUser = error else {
                return XCTFail("Attendu AuthError.inactiveUser, eu \(error)")
            }
        }
        XCTAssertNil(store.currentUser)
    }

    func testCreateUserDuplicateRejected() throws {
        let store = AuthStore()
        store.testBypassSecurity = true
        store.users = []
        _ = try store.createUser(username: "dup@exemple.fr", password: "pw", role: .admin)
        XCTAssertThrowsError(try store.createUser(username: "dup@exemple.fr", password: "pw", role: .admin)) { error in
            guard case AuthError.duplicateUsername = error else {
                return XCTFail("Attendu AuthError.duplicateUsername, eu \(error)")
            }
        }
        XCTAssertThrowsError(try store.createUser(username: "nopw@exemple.fr", password: "", role: .admin)) { error in
            guard case AuthError.emptyPassword = error else {
                return XCTFail("Attendu AuthError.emptyPassword, eu \(error)")
            }
        }
        XCTAssertThrowsError(try store.createUser(username: "pasunemail", password: "pw", role: .admin)) { error in
            guard case AuthError.invalidEmail = error else {
                return XCTFail("Attendu AuthError.invalidEmail, eu \(error)")
            }
        }
    }

    func testUpdatePasswordRehashes() throws {
        let store = AuthStore()
        store.testBypassSecurity = true
        store.users = []
        let user = try store.createUser(username: "rehash@exemple.fr", password: "oldpw", role: .admin)
        let oldHash = store.users.first(where: { $0.id == user.id })?.passwordHash
        try store.updatePassword(user, newPassword: "newpw")
        let updated = store.users.first(where: { $0.id == user.id })
        XCTAssertNotEqual(updated?.passwordHash, oldHash)
        XCTAssertThrowsError(try store.login(username: "rehash@exemple.fr", password: "oldpw")) { _ in }
        let logged = try store.login(username: "rehash@exemple.fr", password: "newpw")
        XCTAssertEqual(logged.id, user.id)
    }

    private func makeDirectoryStore() -> (AuthStore, PartyDirectory, [DirectoryEntry]) {
        let store = AuthStore()
        store.testBypassSecurity = true
        store.users = []
        let dir = PartyDirectory()
        dir.entries = []
        store.attachDirectory(dir)
        let e1 = DirectoryEntry(kinds: [.societe], party: InvoiceParty(name: "Société A", street: "", postcode: "", city: ""))
        let e2 = DirectoryEntry(kinds: [.societe], party: InvoiceParty(name: "Société B", street: "", postcode: "", city: ""))
        let client = DirectoryEntry(kinds: [.client], party: InvoiceParty(name: "Client X", street: "", postcode: "", city: ""))
        dir.entries = [e1, e2, client]
        return (store, dir, [e1, e2, client])
    }

    func testPerimeterFiltering() {
        let (store, _, entries) = makeDirectoryStore()
        let s1 = entries[0]; let s2 = entries[1]

        let admin = User(username: "admin", role: .admin, societyIDs: [])
        let comptable = User(username: "compta", role: .comptable, societyIDs: [s1.id])

        XCTAssertTrue(store.userCanAccessSociety(admin, societyID: s1.id))
        XCTAssertTrue(store.userCanAccessSociety(admin, societyID: s2.id))
        XCTAssertTrue(store.userCanAccessSociety(comptable, societyID: s1.id))
        XCTAssertFalse(store.userCanAccessSociety(comptable, societyID: s2.id))
        XCTAssertFalse(store.userCanAccessSociety(comptable, societyID: nil))

        XCTAssertNil(store.visibleInvoiceCompanyIDs(for: admin), "Admin: pas de filtre (nil = tout)")
        XCTAssertEqual(store.visibleInvoiceCompanyIDs(for: comptable), Set([s1.id]))
        XCTAssertNil(store.visibleInvoiceCompanyIDs(for: nil))
    }

    func testVisibleSocietiesScopedForComptable() {
        let (store, directory, entries) = makeDirectoryStore()
        _ = directory  // retient la référence faible attachée à AuthStore
        let s2 = entries[1]
        let admin = User(username: "admin", role: .admin, societyIDs: [])
        let comptable = User(username: "compta", role: .comptable, societyIDs: [s2.id])
        XCTAssertEqual(Set(store.visibleSocieties(for: admin).map(\.displayName)), Set(["Société A", "Société B"]))
        XCTAssertEqual(Set(store.visibleSocieties(for: comptable).map(\.displayName)), Set(["Société B"]))
        XCTAssertTrue(store.visibleSocieties(for: nil).isEmpty)
        XCTAssertEqual(Set(store.availableSocieties().map(\.displayName)), Set(["Société A", "Société B"]),
                     "availableSocieties ne doit renvoyer que les fiches sociétés")
    }

    func testMultiRoleCumulatesProfiles() throws {
        let (store, _, entries) = makeDirectoryStore()
        let s1 = entries[0]
        let multi = User(username: "multi", role: .comptable, roles: [.comptable, .admin], societyIDs: [s1.id])
        XCTAssertTrue(multi.hasRole(.comptable))
        XCTAssertTrue(multi.hasRole(.admin))
        XCTAssertTrue(multi.isAdmin)
        XCTAssertEqual(multi.rolesLabel, "Comptable client, Administrateur")
        // un admin cumulé voit toutes les sociétés même avec un périmètre défini
        XCTAssertEqual(Set(store.visibleSocieties(for: multi).map(\.displayName)), Set(["Société A", "Société B"]))
        XCTAssertNil(store.visibleInvoiceCompanyIDs(for: multi), "Le cumul admin lève le filtre de périmètre")
        // rétrocompatibilité : User(role:) donne un seul profil
        let single = User(username: "single", role: .acheteur, societyIDs: [s1.id])
        XCTAssertFalse(single.isAdmin)
        XCTAssertTrue(single.hasRole(.acheteur))
        XCTAssertEqual(single.roles.count, 1)
    }

    func testCreateComptableRequiresSociety() throws {
        let (store, _, _) = makeDirectoryStore()
        XCTAssertThrowsError(try store.createUser(username: "nocompta@exemple.fr", password: "pw", role: .comptable, societyIDs: [])) { error in
            guard case AuthError.missingSociety = error else {
                return XCTFail("Attendu AuthError.missingSociety, eu \(error)")
            }
        }
    }

    func testInvoiceCompanyIDRetrocompatibility() throws {
        let json = """
        {"id":"\(UUID().uuidString)","number":"FAC-1","type":"380","status":"draft",
         "issueDate":682000000,"dueDate":682860000,"currency":"EUR","profile":"EN 16931",
         "seller":{"name":"S","street":"","postcode":"","city":""},"buyer":{"name":"B","street":"","postcode":"","city":""},
         "lines":[]}
        """.data(using: .utf8)!
        let inv = try JSONDecoder().decode(Invoice.self, from: json)
        XCTAssertNil(inv.companyID, "Une facture sans companyID doit se décoder avec companyID nil")
    }

    func testInvoiceCompanyIDRoundTrip() throws {
        let cid = UUID()
        var inv = Invoice(number: "FAC-2",
                          seller: InvoiceParty(name: "S", street: "", postcode: "", city: ""),
                          buyer: InvoiceParty(name: "B", street: "", postcode: "", city: ""),
                          companyID: cid)
        XCTAssertEqual(inv.companyID, cid)
        let data = try JSONEncoder().encode(inv)
        let decoded = try JSONDecoder().decode(Invoice.self, from: data)
        XCTAssertEqual(decoded.companyID, cid)
        inv.companyID = nil
        let data2 = try JSONEncoder().encode(inv)
        let decoded2 = try JSONDecoder().decode(Invoice.self, from: data2)
        XCTAssertNil(decoded2.companyID)
    }

    func testDirectoryEntryCompanyIDRetrocompatibility() throws {
        let json = """
        {"id":"\(UUID().uuidString)","kind":"client",
         "party":{"name":"Client A","street":"","postcode":"","city":""}}
        """.data(using: .utf8)!
        let entry = try JSONDecoder().decode(DirectoryEntry.self, from: json)
        XCTAssertNil(entry.companyID,
                     "Une fiche annuaire sans companyID doit se décoder avec companyID nil")
        XCTAssertEqual(entry.party.name, "Client A")
    }

    func testDirectoryEntryCompanyIDRoundTrip() throws {
        let cid = UUID()
        var entry = DirectoryEntry(kinds: [.client],
                                   party: InvoiceParty(name: "Client A", street: "", postcode: "", city: ""),
                                   companyID: cid)
        XCTAssertEqual(entry.companyID, cid)
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(DirectoryEntry.self, from: data)
        XCTAssertEqual(decoded.companyID, cid)
        entry.companyID = nil
        let data2 = try JSONEncoder().encode(entry)
        let decoded2 = try JSONDecoder().decode(DirectoryEntry.self, from: data2)
        XCTAssertNil(decoded2.companyID)
    }

    func testUserDefaultSellerEntryIDRetrocompatibility() throws {
        let json = """
        {"id":"\(UUID().uuidString)","username":"compta@exemple.fr","role":"comptable",
         "passwordHash":"","salt":"","societyIDs":["\(UUID().uuidString)"],"isActive":true,"createdAt":0}
        """.data(using: .utf8)!
        let user = try JSONDecoder().decode(User.self, from: json)
        XCTAssertNil(user.defaultSellerEntryID,
                     "Un utilisateur sans defaultSellerEntryID doit se décoder avec nil")
    }

    func testCreateUserWithDefaultSeller() throws {
        let store = AuthStore()
        store.testBypassSecurity = true
        store.users = []
        let sid = UUID()
        let user = try store.createUser(username: "compta2@exemple.fr", password: "pw",
                                        role: .comptable, societyIDs: [sid],
                                        defaultSellerEntryID: sid)
        XCTAssertEqual(user.defaultSellerEntryID, sid)
        let data = try JSONEncoder().encode(user)
        let decoded = try JSONDecoder().decode(User.self, from: data)
        XCTAssertEqual(decoded.defaultSellerEntryID, sid)
    }

    // MARK: - Sécurité (A1, A4, A5, A6, B1)

    func testPasswordPolicyRejectsWeak() {
        XCTAssertNotNil(PasswordPolicy.validate("cour"), "trop court")
        XCTAssertNotNil(PasswordPolicy.validate("admin"), "trivial")
        XCTAssertNotNil(PasswordPolicy.validate("password1"), "trivial")
        XCTAssertNotNil(PasswordPolicy.validate("abcdefghij"), "aucune classe diversifiée")
        XCTAssertNil(PasswordPolicy.validate("Abcdef1!xyz"), "valide")
        XCTAssertNil(PasswordPolicy.validate("Secur3Pass!"), "valide")
    }

    func testPasswordPolicyRejectsReusedPassword() throws {
        let store = AuthStore()
        store.testBypassSecurity = true
        store.users = []
        let user = try store.createUser(username: "policy@exemple.fr", password: "pw", role: .admin)
        let strong = "Secur3Pass!"
        try store.updatePassword(user, newPassword: strong, forceChange: true)
        // Récupère l'utilisateur à jour (sel/hash régénérés par forceChange)
        let current = store.users.first(where: { $0.id == user.id })!
        store.testBypassSecurity = false
        // Le même mot de passe doit être refusé comme « réutilisé »
        XCTAssertThrowsError(try store.updatePassword(current, newPassword: strong)) { error in
            guard case AuthError.passwordPolicy(.reused) = error else {
                return XCTFail("Attendu .reused, eu \(error)")
            }
        }
    }

    func testCreateUserEnforcesPolicyWithoutBypass() throws {
        let store = AuthStore()
        store.testBypassSecurity = true
        store.users = []
        store.testBypassSecurity = false
        XCTAssertThrowsError(try store.createUser(username: "weak@exemple.fr", password: "pw", role: .admin)) { error in
            guard case AuthError.passwordPolicy(.tooShort) = error else {
                return XCTFail("Attendu .tooShort, eu \(error)")
            }
        }
        XCTAssertThrowsError(try store.createUser(username: "weak2@exemple.fr", password: "admin", role: .admin)) { error in
            guard case AuthError.passwordPolicy = error else {
                return XCTFail("Attendu .passwordPolicy, eu \(error)")
            }
        }
        let ok = try store.createUser(username: "strong@exemple.fr", password: "Secur3Pass!", role: .admin)
        XCTAssertTrue(ok.mustChangePassword == false, "sans mustChangePassword explicite = false")
    }

    func testAccountLockoutAfterFailedAttempts() throws {
        let store = AuthStore()
        store.testBypassSecurity = true
        store.users = []
        let user = try store.createUser(username: "lock@exemple.fr", password: "pw", role: .admin)
        store.testBypassSecurity = false
        // 4 échecs : pas encore verrouillé
        for _ in 0..<4 {
            XCTAssertThrowsError(try store.login(username: "lock@exemple.fr", password: "bad"))
        }
        let after4 = store.users.first(where: { $0.id == user.id })!
        XCTAssertEqual(after4.failedLoginAttempts, 4)
        XCTAssertNil(after4.lockUntil)
        // 5e échec : verrouillage
        XCTAssertThrowsError(try store.login(username: "lock@exemple.fr", password: "bad"))
        let after5 = store.users.first(where: { $0.id == user.id })!
        XCTAssertNotNil(after5.lockUntil, "le compte doit être verrouillé après 5 échecs")
        // Login même avec le bon mot de passe doit échouer tant que verrouillé
        XCTAssertThrowsError(try store.login(username: "lock@exemple.fr", password: "pw")) { error in
            guard case AuthError.lockedOut = error else {
                return XCTFail("Attendu .lockedOut, eu \(error)")
            }
        }
        // forceChange par admin déverrouille
        try store.updatePassword(user, newPassword: "NewSecur3!", forceChange: true)
        store.testBypassSecurity = true
        let logged = try store.login(username: "lock@exemple.fr", password: "NewSecur3!")
        XCTAssertEqual(logged.id, user.id)
        XCTAssertNil(store.users.first(where: { $0.id == user.id })?.lockUntil)
    }

    func testSeedingOnlyOnce() {
        let store = AuthStore()
        store.testBypassSecurity = true
        store.users = []
        UserDefaults.standard.removeObject(forKey: "facturx.auth.seeded.v1")
        // Premier seeding
        store.seedDefaultAdminIfEmpty()
        XCTAssertTrue(store.users.first?.mustChangePassword == true)
        // Modification du hash (simule un changement par l'admin)
        var admin = store.users.first!
        admin.passwordHash = "CHANGED"
        admin.mustChangePassword = false
        store.users[0] = admin
        store.save()
        // Re-seeding : ne doit PAS réinitialiser le mot de passe
        store.seedDefaultAdminIfEmpty()
        XCTAssertEqual(store.users.first?.passwordHash, "CHANGED", "Le mot de passe admin ne doit pas être réinitialisé au redémarrage")
        XCTAssertEqual(store.users.first?.mustChangePassword, false)
    }

    func testSessionExpiration() throws {
        let store = AuthStore()
        store.testBypassSecurity = true
        store.users = []
        let user = try store.createUser(username: "session@exemple.fr", password: "pw", role: .admin)
        _ = try store.login(username: "session@exemple.fr", password: "pw")
        XCTAssertEqual(store.currentUser?.id, user.id)
        // Simule une dernière activité ancienne au-delà du délai
        if let idx = store.users.firstIndex(where: { $0.id == user.id }) {
            store.users[idx].lastActivityAt = Date().addingTimeInterval(-PasswordPolicy.sessionMaxInactivitySeconds - 1)
            store.currentUser = store.users[idx]
        }
        store.testBypassSecurity = false
        XCTAssertTrue(store.validateSession(), "La session doit expirer après inactivité")
        XCTAssertNil(store.currentUser, "L'utilisateur doit être déconnecté après expiration")
    }

    func testAuditLogRecordsActions() throws {
        let store = AuthStore()
        store.testBypassSecurity = true
        store.users = []
        store.audit.clear()
        _ = try store.createUser(username: "audit@exemple.fr", password: "pw", role: .admin)
        XCTAssertTrue(store.audit.entries.contains(where: { $0.action == "user_created" && $0.target == "audit@exemple.fr" }))
        _ = try store.login(username: "audit@exemple.fr", password: "pw")
        XCTAssertTrue(store.audit.entries.contains(where: { $0.action == "login_success" }))
        store.logout()
        XCTAssertTrue(store.audit.entries.contains(where: { $0.action == "logout" }))
    }

    func testInvoiceNumberingIsPerCompany() {
        let store = InvoiceStore()
        store.invoices = []
        store.numberPrefix = "FAC"
        store.numberIncludeYear = true
        store.numberStart = 1
        store.numberUseSeparator = true

        let companyA = UUID()
        let companyB = UUID()

        // Aucune facture: chaque société démarre à 0001
        XCTAssertEqual(String(store.nextNumber(companyID: companyA).suffix(4)), "0001")
        XCTAssertEqual(String(store.nextNumber(companyID: companyB).suffix(4)), "0001")

        // On crée une facture pour la société A
        let invA1 = Invoice(number: store.nextNumber(companyID: companyA),
                            seller: InvoiceParty(name: "A", street: "", postcode: "", city: ""),
                            buyer: InvoiceParty(name: "B", street: "", postcode: "", city: ""),
                            companyID: companyA)
        store.invoices.append(invA1)

        // A doit passer à 0002, B reste à 0001
        XCTAssertEqual(String(store.nextNumber(companyID: companyA).suffix(4)), "0002")
        XCTAssertEqual(String(store.nextNumber(companyID: companyB).suffix(4)), "0001")

        // Une facture pour B
        let invB1 = Invoice(number: store.nextNumber(companyID: companyB),
                            seller: InvoiceParty(name: "A", street: "", postcode: "", city: ""),
                            buyer: InvoiceParty(name: "B", street: "", postcode: "", city: ""),
                            companyID: companyB)
        store.invoices.append(invB1)
        XCTAssertEqual(String(store.nextNumber(companyID: companyB).suffix(4)), "0002")
        XCTAssertEqual(String(store.nextNumber(companyID: companyA).suffix(4)), "0002")

        // Le chrono sans société est distinct (companyID nil)
        XCTAssertEqual(String(store.nextNumber(companyID: nil).suffix(4)), "0001")
    }
}
