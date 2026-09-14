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
        _ = try store.createUser(username: "alice", password: "pw", role: .comptable)
        XCTAssertThrowsError(try store.createUser(username: "alice", password: "pw")) { error in
            guard case AuthError.duplicateUsername = error else {
                return XCTFail("Attendu AuthError.duplicateUsername, eu \(error)")
            }
        }
        XCTAssertThrowsError(try store.createUser(username: "bob", password: "")) { error in
            guard case AuthError.emptyPassword = error else {
                return XCTFail("Attendu AuthError.emptyPassword, eu \(error)")
            }
        }
    }

    func testUpdatePasswordRehashes() throws {
        let store = AuthStore()
        store.users = []
        let user = try store.createUser(username: "jo", password: "oldpw")
        let oldHash = store.users.first(where: { $0.id == user.id })?.passwordHash
        try store.updatePassword(user, newPassword: "newpw")
        let updated = store.users.first(where: { $0.id == user.id })
        XCTAssertNotEqual(updated?.passwordHash, oldHash)
        XCTAssertThrowsError(try store.login(username: "jo", password: "oldpw")) { _ in }
        let logged = try store.login(username: "jo", password: "newpw")
        XCTAssertEqual(logged.id, user.id)
    }

    func testPerimeterFiltering() {
        let store = AuthStore()
        let s1 = Society(name: "Société A")
        let s2 = Society(name: "Société B")
        store.societies = [s1, s2]

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
        let store = AuthStore()
        let s1 = Society(name: "A")
        let s2 = Society(name: "B")
        let s3 = Society(name: "C")
        store.societies = [s1, s2, s3]
        let admin = User(username: "admin", role: .admin, societyIDs: [])
        let comptable = User(username: "compta", role: .comptable, societyIDs: [s2.id, s3.id])
        XCTAssertEqual(Set(store.visibleSocieties(for: admin).map(\.name)), Set(["A", "B", "C"]))
        XCTAssertEqual(Set(store.visibleSocieties(for: comptable).map(\.name)), Set(["B", "C"]))
        XCTAssertTrue(store.visibleSocieties(for: nil).isEmpty)
    }

    func testDeleteSocietyCleansPerimeters() {
        let store = AuthStore()
        let s1 = Society(name: "A")
        store.societies = [s1]
        let user = User(username: "u", role: .comptable, societyIDs: [s1.id])
        store.users = [user]
        store.currentUser = user
        store.delete(s1)
        XCTAssertTrue(store.societies.isEmpty)
        XCTAssertTrue(store.users.first(where: { $0.id == user.id })?.societyIDs.isEmpty ?? false)
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
}
