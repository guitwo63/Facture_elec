import XCTest
@testable import FacturXCore

final class AuditActionLabelStoreTests: XCTestCase {

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "facturx.auditactionlabels.v1")
        super.tearDown()
    }

    func testDefaultLabelsCoverKnownActionCodes() {
        // Codes réellement émis par AuditStore.record(action:) dans le reste du code —
        // un code sans libellé retomberait sur son code technique brut dans l'UI.
        let knownCodes = [
            "status_change", "invoice_created", "invoice_updated", "invoice_deleted",
            "order_created", "order_updated", "order_deleted",
            "quote_created", "quote_updated", "quote_deleted",
            "directory_entry_created", "directory_entry_updated", "directory_entry_deleted",
            "pdp_deposit_sent", "pdp_deposit_error", "pdp_status_received", "pdp_status_sent",
            "pdp_status_error", "pdp_status_send_error",
            "login_success", "login_failed", "login_blocked", "logout",
            "account_locked", "session_expired", "user_created", "user_deleted", "seed_admin",
            "password_changed", "role_changed", "scope_changed",
            "twofactor_enabled", "twofactor_disabled",
            "email_verification_sent", "email_verified", "smtp_alert_error"
        ]
        let ids = Set(AuditActionLabelStore.defaultLabels.map(\.id))
        for code in knownCodes {
            XCTAssertTrue(ids.contains(code), "Aucun libellé par défaut pour le code « \(code) »")
        }
    }

    func testLabelFallsBackToRawCodeWhenUnknown() {
        let store = AuditActionLabelStore()
        XCTAssertEqual(store.label(for: "totalement_inconnu"), "totalement_inconnu")
    }

    func testLabelReturnsKnownTranslation() {
        let store = AuditActionLabelStore()
        XCTAssertEqual(store.label(for: "invoice_created"), "Facture créée")
    }

    func testUpsertPersistsCustomLabelAcrossReload() {
        let store = AuditActionLabelStore()
        store.upsert(AuditActionLabel(id: "invoice_created", label: "Nouvelle facture"))
        XCTAssertEqual(store.label(for: "invoice_created"), "Nouvelle facture")

        let reloaded = AuditActionLabelStore()
        XCTAssertEqual(reloaded.label(for: "invoice_created"), "Nouvelle facture")
    }

    func testLoadMergesNewDefaultCodesWithoutOverwritingCustomizedOnes() {
        let store = AuditActionLabelStore()
        store.upsert(AuditActionLabel(id: "invoice_created", label: "Personnalisé"))
        // Simule une base partielle (comme si un ancien build n'avait persisté qu'un
        // sous-ensemble des codes connus) : le rechargement doit compléter les codes
        // manquants sans écraser la personnalisation déjà faite.
        let partial = [AuditActionLabel(id: "invoice_created", label: "Personnalisé")]
        let data = try! JSONEncoder().encode(partial)
        UserDefaults.standard.set(data, forKey: "facturx.auditactionlabels.v1")

        let reloaded = AuditActionLabelStore()
        XCTAssertEqual(reloaded.label(for: "invoice_created"), "Personnalisé")
        XCTAssertEqual(reloaded.label(for: "invoice_deleted"), "Facture supprimée", "les codes absents du JSON partiel doivent revenir avec leur libellé par défaut")
    }

    func testResetToDefaultsDiscardsCustomizations() {
        let store = AuditActionLabelStore()
        store.upsert(AuditActionLabel(id: "invoice_created", label: "Personnalisé"))
        store.resetToDefaults()
        XCTAssertEqual(store.label(for: "invoice_created"), "Facture créée")
    }
}
