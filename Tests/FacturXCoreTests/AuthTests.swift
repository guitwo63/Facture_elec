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
        store.users = []
        let dir = PartyDirectory()
        dir.entries = []
        store.attachDirectory(dir)
        let e1 = DirectoryEntry(kind: .fournisseur, party: InvoiceParty(name: "Société A", street: "", postcode: "", city: ""))
        let e2 = DirectoryEntry(kind: .fournisseur, party: InvoiceParty(name: "Société B", street: "", postcode: "", city: ""))
        let client = DirectoryEntry(kind: .client, party: InvoiceParty(name: "Client X", street: "", postcode: "", city: ""))
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
                     "availableSocieties ne doit renvoyer que les fiches fournisseurs")
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
        var entry = DirectoryEntry(kind: .client,
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
}
