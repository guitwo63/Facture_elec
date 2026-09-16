import XCTest
@testable import FacturXCore

final class SMTPServiceTests: XCTestCase {

    func testIsConfiguredRequiresHostAndFromAddress() {
        var creds = SMTPCredentials()
        XCTAssertFalse(creds.isConfigured)
        creds.host = "smtp.exemple.fr"
        XCTAssertFalse(creds.isConfigured, "fromAddress manquant")
        creds.fromAddress = "alertes@exemple.fr"
        XCTAssertTrue(creds.isConfigured)
    }

    func testDefaultsFavorImplicitTLSOnPort465() {
        let creds = SMTPCredentials()
        XCTAssertEqual(creds.port, 465)
        XCTAssertTrue(creds.useTLS)
    }

    func testDecodingToleratesMissingFieldsFromOlderPersistedData() throws {
        // Simule une valeur persistée avant l'ajout d'un champ (ex. alertOnNewUser).
        let legacyJSON = """
        {"host":"smtp.exemple.fr","port":465,"username":"","password":"","fromAddress":"a@b.fr","fromName":"X","useTLS":true,"alertsEnabled":true}
        """
        let data = Data(legacyJSON.utf8)
        let decoded = try JSONDecoder().decode(SMTPCredentials.self, from: data)
        XCTAssertEqual(decoded.host, "smtp.exemple.fr")
        XCTAssertTrue(decoded.alertsEnabled)
        XCTAssertTrue(decoded.alertOnNewUser, "doit retomber sur la valeur par défaut si absente des données")
        XCTAssertTrue(decoded.alertOnInvoiceStatusChange)
    }

    func testSendRejectsRecipientWithoutAtSign() async {
        let credentials = SMTPCredentials(host: "smtp.exemple.fr", fromAddress: "a@b.fr")
        do {
            try await SMTPService().send(to: "pas-un-email", subject: "x", body: "y", credentials: credentials)
            XCTFail("devrait lever invalidRecipient")
        } catch let error as SMTPError {
            guard case .invalidRecipient = error else {
                return XCTFail("erreur inattendue : \(error)")
            }
        } catch {
            XCTFail("erreur inattendue : \(error)")
        }
    }

    func testSendRequiresConfiguredCredentials() async {
        do {
            try await SMTPService().send(to: "a@b.fr", subject: "x", body: "y", credentials: SMTPCredentials())
            XCTFail("devrait lever notConfigured")
        } catch let error as SMTPError {
            guard case .notConfigured = error else {
                return XCTFail("erreur inattendue : \(error)")
            }
        } catch {
            XCTFail("erreur inattendue : \(error)")
        }
    }
}
