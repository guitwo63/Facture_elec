import XCTest
@testable import FacturXCore

final class EmailTemplatesTests: XCTestCase {

    private let globalKey = "facturx.email.templates.enabled.v1"
    private let templatesKey = "facturx.email.templates.v1"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: globalKey)
        UserDefaults.standard.removeObject(forKey: templatesKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: globalKey)
        UserDefaults.standard.removeObject(forKey: templatesKey)
        super.tearDown()
    }

    // MARK: - EmailTemplateStore

    func testDefaultsCoverAllKindsAndAreEnabled() {
        let store = EmailTemplateStore()
        XCTAssertTrue(store.globalEnabled)
        XCTAssertEqual(Set(store.templates.map(\.kind)), Set(EmailTemplateKind.allCases))
        for kind in EmailTemplateKind.allCases {
            XCTAssertTrue(store.isSendEnabled(kind), "\(kind) devrait être actif par défaut")
        }
    }

    func testGlobalToggleOffDisablesEveryKindRegardlessOfIndividualSetting() {
        let store = EmailTemplateStore()
        store.globalEnabled = false
        for kind in EmailTemplateKind.allCases {
            XCTAssertFalse(store.isSendEnabled(kind))
        }
    }

    func testDisablingOneKindDoesNotAffectOthers() {
        let store = EmailTemplateStore()
        var quote = store.template(for: .quoteSent)
        quote.enabled = false
        store.upsert(quote)

        XCTAssertFalse(store.isSendEnabled(.quoteSent))
        XCTAssertTrue(store.isSendEnabled(.orderConfirmation))
        XCTAssertTrue(store.globalEnabled)
    }

    func testUpsertPersistsAcrossReload() {
        let store = EmailTemplateStore()
        var invoiceSent = store.template(for: .invoiceSent)
        invoiceSent.subject = "Sujet personnalisé {{numero}}"
        invoiceSent.enabled = false
        store.upsert(invoiceSent)
        store.globalEnabled = false
        store.save()

        let reloaded = EmailTemplateStore()
        XCTAssertFalse(reloaded.globalEnabled)
        XCTAssertEqual(reloaded.template(for: .invoiceSent).subject, "Sujet personnalisé {{numero}}")
        XCTAssertFalse(reloaded.template(for: .invoiceSent).enabled)
        // Les autres types ne doivent pas avoir été affectés par la sauvegarde d'un seul.
        XCTAssertEqual(reloaded.template(for: .quoteSent).subject, EmailTemplateKind.quoteSent.defaultSubject)
    }

    func testTemplateForUnknownKindFallsBackToDefault() {
        let store = EmailTemplateStore()
        store.templates.removeAll { $0.kind == .deliveryNotice }
        let fallback = store.template(for: .deliveryNotice)
        XCTAssertEqual(fallback.subject, EmailTemplateKind.deliveryNotice.defaultSubject)
        XCTAssertTrue(fallback.enabled)
    }

    // MARK: - EmailTemplate Codable migration

    func testDecodingTemplateWithMissingFieldsUsesKindDefaults() throws {
        let json = """
        {"kind": "orderConfirmation"}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(EmailTemplate.self, from: json)
        XCTAssertEqual(decoded.subject, EmailTemplateKind.orderConfirmation.defaultSubject)
        XCTAssertEqual(decoded.body, EmailTemplateKind.orderConfirmation.defaultBody)
        XCTAssertTrue(decoded.enabled)
    }

    func testDecodingTemplateWithUnknownKindFallsBackWithoutCrashing() throws {
        let json = """
        {"kind": "somethingNewNotYetSupported", "enabled": false}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(EmailTemplate.self, from: json)
        XCTAssertEqual(decoded.kind, .quoteSent)
    }

    // MARK: - EmailComposer

    func testComposeSubstitutesAllProvidedVariables() {
        let template = EmailTemplate(kind: .invoiceSent, subject: "Facture {{numero}} pour {{client}}",
                                      body: "Montant : {{montant}}. Merci, {{societe}}.")
        let result = EmailComposer.compose(template: template, variables: [
            "numero": "FAC-2026-001",
            "client": "Client SAS",
            "montant": "120,00 EUR",
            "societe": "Arverneo"
        ])
        XCTAssertEqual(result.subject, "Facture FAC-2026-001 pour Client SAS")
        XCTAssertEqual(result.body, "Montant : 120,00 EUR. Merci, Arverneo.")
    }

    func testComposeLeavesUnknownPlaceholdersUntouched() {
        let template = EmailTemplate(kind: .quoteSent, subject: "Devis {{numero}} — {{inconnu}}", body: "corps")
        let result = EmailComposer.compose(template: template, variables: ["numero": "DEV-1"])
        XCTAssertEqual(result.subject, "Devis DEV-1 — {{inconnu}}")
    }

    func testInvoiceReminderHasNoEditableContentByDesign() {
        XCTAssertFalse(EmailTemplateKind.invoiceReminder.hasEditableContent)
        for kind in EmailTemplateKind.allCases where kind != .invoiceReminder {
            XCTAssertTrue(kind.hasEditableContent)
        }
    }
}
