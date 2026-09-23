import XCTest
@testable import FacturXCore

/// Menu « Conditions de paiement » de l'éditeur de facture et de la fiche société
/// (`PaymentTermsPresetSelection`) : « Personnalisé » doit tenir même quand le texte est encore
/// celui d'un préréglage, et rendre modifiables le texte et l'échéance. Une facture n'affiche
/// un préréglage que si son échéance est celle qu'il calcule
/// (`PaymentTermsPresetStore.matchingPreset(for:)`), d'où l'échéance des factures créées.
final class PaymentTermsPresetSelectionTests: XCTestCase {

    private let keys = [
        "facturx.paymentTermsPresets.v1",
        "facturx.paymentTermsPresets.bysociety.v1",
        "facturx.directory.v1",
        "facturx.directory.societeInterco.migrated.v1",
        "facturx.invoices.v1",
        "facturx.mycompany.v1",
        "facturx.defaultseller.entryid.v1",
        "facturx.number.prefix.v1",
        "facturx.number.includeyear.v1",
        "facturx.number.start.v1",
        "facturx.number.useseparator.v1",
        "facturx.number.overrides.bysociety.v1",
    ]

    override func setUp() {
        super.setUp()
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        PartyDirectory.shared.entries = []
    }

    override func tearDown() {
        PartyDirectory.shared.entries = []
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        super.tearDown()
    }

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Paris")!
        return cal
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    /// Facture du 15/03/2026 : « 30 jours net » calcule le 14/04, « 30 jours fin de mois » le 30/04.
    private func invoice(terms: String?, due: Date, companyID: UUID? = nil) -> Invoice {
        let party = InvoiceParty(name: "", street: "", postcode: "", city: "")
        return Invoice(number: "FAC0001", issueDate: date(2026, 3, 15), dueDate: due,
                       seller: party, buyer: party, companyID: companyID, paymentTerms: terms)
    }

    // MARK: - « Personnalisé » depuis un préréglage

    /// Le bug : le menu déduisait sa sélection du seul texte et ignorait « Personnalisé » (tag
    /// nil). Le texte restant celui du préréglage, le menu y revenait aussitôt : texte en
    /// lecture seule, échéance grisée.
    func testChoosingCustomFromAPresetShowsCustomWithoutChangingTheInvoice() {
        let store = PaymentTermsPresetStore()
        var selection = PaymentTermsPresetSelection()
        let inv = invoice(terms: "Paiement à 30 jours", due: date(2026, 4, 14))
        XCTAssertEqual(selection.activePreset(for: inv, in: store, calendar: calendar)?.id, "net30")

        XCTAssertNil(selection.select(nil, for: inv, in: store, calendar: calendar), "« Personnalisé » ne réécrit pas la facture")

        XCTAssertTrue(selection.isCustom)
        XCTAssertNil(selection.activePreset(for: inv, in: store, calendar: calendar), "le menu reste sur « Personnalisé »")
        XCTAssertEqual(store.matchingPreset(for: inv, calendar: calendar)?.id, "net30",
                       "sans ce choix retenu, le texte et l'échéance désigneraient encore 30 jours net")
    }

    func testChoosingAPresetAfterCustomRewritesTextAndDueDate() {
        let store = PaymentTermsPresetStore()
        var selection = PaymentTermsPresetSelection()
        var inv = invoice(terms: "Paiement à 30 jours", due: date(2026, 4, 14))
        _ = selection.select(nil, for: inv, in: store, calendar: calendar)
        inv.paymentTerms = "Paiement à 45 jours"
        inv.dueDate = date(2026, 4, 29)

        let updated = selection.select("finDeMois30", for: inv, in: store, calendar: calendar)

        XCTAssertEqual(updated?.paymentTerms, "Paiement à 30 jours fin de mois")
        XCTAssertTrue(calendar.isDate(updated!.dueDate, inSameDayAs: date(2026, 4, 30)))
        XCTAssertFalse(selection.isCustom)
        XCTAssertEqual(selection.activePreset(for: updated!, in: store, calendar: calendar)?.id, "finDeMois30")
    }

    func testChoosingAPresetMissingFromTheListChangesNothing() {
        let store = PaymentTermsPresetStore()
        var selection = PaymentTermsPresetSelection()
        let inv = invoice(terms: "Paiement à 30 jours", due: date(2026, 4, 14))
        _ = selection.select(nil, for: inv, in: store, calendar: calendar)

        XCTAssertNil(selection.select("supprime", for: inv, in: store, calendar: calendar))
        XCTAssertTrue(selection.isCustom)
    }

    /// Même règle que le reste du menu : préréglages et règle d'échéance de la société de la
    /// facture (#128).
    func testInvoiceMenuUsesItsCompanyDueRule() {
        let store = PaymentTermsPresetStore()
        let cidA = UUID()
        var net30 = store.presets.first { $0.id == "net30" }!
        net30.dueRule = .days(45)
        store.setOverride(net30, companyID: cidA)
        var selection = PaymentTermsPresetSelection()

        let updated = selection.select("net30", for: invoice(terms: nil, due: date(2026, 3, 15), companyID: cidA), in: store, calendar: calendar)

        XCTAssertTrue(calendar.isDate(updated!.dueDate, inSameDayAs: date(2026, 4, 29)))
        XCTAssertEqual(selection.activePreset(for: updated!, in: store, calendar: calendar)?.id, "net30")
        XCTAssertNil(selection.activePreset(for: invoice(terms: "Paiement à 30 jours", due: date(2026, 4, 14), companyID: cidA), in: store, calendar: calendar),
                     "30 jours nets ne sont pas la règle de cette société")
    }

    // MARK: - Échéance saisie à la main

    /// Le choix « Personnalisé » est un état local, perdu au changement de facture ou au
    /// redémarrage : c'est l'échéance, différente de celle du préréglage, qui le garde.
    func testManualDueDateShowsCustomWithoutTheLocalChoice() {
        let store = PaymentTermsPresetStore()
        let fresh = PaymentTermsPresetSelection()

        XCTAssertNil(fresh.activePreset(for: invoice(terms: "Paiement à 30 jours", due: date(2026, 4, 20)), in: store, calendar: calendar))
        XCTAssertEqual(fresh.activePreset(for: invoice(terms: "Paiement à 30 jours", due: date(2026, 4, 14, hour: 0)), in: store, calendar: calendar)?.id, "net30",
                       "comparaison au jour près : l'heure enregistrée ne compte pas")
    }

    func testPresetWithoutDueRuleIsShownWhateverTheDueDate() {
        let store = PaymentTermsPresetStore()
        let selection = PaymentTermsPresetSelection()

        XCTAssertEqual(selection.activePreset(for: invoice(terms: "Comptant", due: date(2026, 4, 20)), in: store, calendar: calendar)?.id, "comptant")
        XCTAssertFalse(PaymentTermsDueRule.none.computesDueDate)
        XCTAssertTrue(PaymentTermsDueRule.days(0).computesDueDate)
        XCTAssertTrue(PaymentTermsDueRule.endOfMonthPlusDays(30).computesDueDate)
    }

    /// Saisie de l'échéance en « Personnalisé » : passer par la date que calcule le préréglage
    /// ne doit pas griser le champ en pleine saisie.
    func testEditingTheDueDateThroughTheComputedDayKeepsCustom() {
        let store = PaymentTermsPresetStore()
        var selection = PaymentTermsPresetSelection()
        var inv = invoice(terms: "Paiement à 30 jours", due: date(2026, 4, 20))
        XCTAssertNil(selection.activePreset(for: inv, in: store, calendar: calendar), "précondition : échéance saisie à la main")

        selection.keepCustomIfShown(for: inv, in: store, calendar: calendar)
        inv.dueDate = date(2026, 4, 14)

        XCTAssertNil(selection.activePreset(for: inv, in: store, calendar: calendar))
        XCTAssertEqual(PaymentTermsPresetSelection().activePreset(for: inv, in: store, calendar: calendar)?.id, "net30",
                       "sans ce choix retenu, le menu repasserait sur 30 jours net")
    }

    func testEditingTheDueDateUnderAPresetWithoutRuleKeepsThePreset() {
        let store = PaymentTermsPresetStore()
        var selection = PaymentTermsPresetSelection()

        selection.keepCustomIfShown(for: invoice(terms: "Comptant", due: date(2026, 3, 15)), in: store, calendar: calendar)

        XCTAssertFalse(selection.isCustom)
    }

    /// Texte saisi en « Personnalisé » : la frappe passe par « Paiement à 30 jours » avant
    /// « … fin de mois ». Le menu ne doit pas repasser sur 30 jours net entre-temps (le champ
    /// de saisie disparaîtrait).
    func testTypingThroughAPresetTextKeepsCustom() {
        let store = PaymentTermsPresetStore()
        var selection = PaymentTermsPresetSelection()
        var inv = invoice(terms: "Paiement à", due: date(2026, 4, 14))

        selection.keepCustom()
        inv.paymentTerms = "Paiement à 30 jours"

        XCTAssertNil(selection.activePreset(for: inv, in: store, calendar: calendar))
        XCTAssertNil(selection.activePreset(for: "Paiement à 30 jours", companyID: nil, in: store))
    }

    /// Setter de la date de facture dans l'éditeur : le préréglage affiché doit être lu avant
    /// d'écrire la nouvelle date. Après, l'échéance ne correspond plus et le menu afficherait
    /// « Personnalisé », sans recalcul.
    func testIssueDateChangeMustReadThePresetBeforeTheNewDate() {
        let store = PaymentTermsPresetStore()
        let selection = PaymentTermsPresetSelection()
        let inv = invoice(terms: "Paiement à 30 jours", due: date(2026, 4, 14))
        let preset = selection.activePreset(for: inv, in: store, calendar: calendar)
        XCTAssertEqual(preset?.id, "net30")

        var moved = inv
        moved.issueDate = date(2026, 4, 1)
        XCTAssertNil(selection.activePreset(for: moved, in: store, calendar: calendar), "date changée, échéance pas encore recalculée")

        moved.dueDate = preset!.dueRule.dueDate(from: moved.issueDate, calendar: calendar)
        XCTAssertTrue(calendar.isDate(moved.dueDate, inSameDayAs: date(2026, 5, 1)))
        XCTAssertEqual(selection.activePreset(for: moved, in: store, calendar: calendar)?.id, "net30")
    }

    // MARK: - Fiche société (texte seul)

    func testPartyMenuSwitchesToCustomAndBack() {
        let store = PaymentTermsPresetStore()
        var selection = PaymentTermsPresetSelection()
        XCTAssertEqual(selection.activePreset(for: "Paiement à 30 jours", companyID: nil, in: store)?.id, "net30")

        XCTAssertNil(selection.select(nil, companyID: nil, in: store))
        XCTAssertNil(selection.activePreset(for: "Paiement à 30 jours", companyID: nil, in: store),
                     "« Personnalisé » tient : le texte devient modifiable")

        XCTAssertEqual(selection.select("comptant", companyID: nil, in: store)?.text, "Comptant")
        XCTAssertEqual(selection.activePreset(for: "Comptant", companyID: nil, in: store)?.id, "comptant")
    }

    // MARK: - Échéance des factures créées

    private func sellerDirectory(terms: String) -> (PartyDirectory, UUID) {
        let directory = PartyDirectory()
        var entry = DirectoryEntry(kinds: [.societe], party: InvoiceParty(name: "Vendeur", street: "", postcode: "", city: ""))
        entry.party.paymentTerms = terms
        directory.upsert(entry)
        return (directory, entry.id)
    }

    func testNewDraftDueDateFollowsTheSellerPresetRule() {
        let (directory, sellerID) = sellerDirectory(terms: "Paiement à 30 jours fin de mois")
        let store = InvoiceStore()
        store.paymentTermsPresets = PaymentTermsPresetStore()

        let draft = store.newDraft(directory: directory, preferredSellerEntryID: sellerID)

        let expected = PaymentTermsDueRule.endOfMonthPlusDays(30).dueDate(from: draft.issueDate)
        XCTAssertTrue(Calendar.current.isDate(draft.dueDate, inSameDayAs: expected))
        XCTAssertEqual(PaymentTermsPresetSelection().activePreset(for: draft, in: store.paymentTermsPresets)?.id, "finDeMois30",
                       "l'éditeur affiche le préréglage, pas « Personnalisé »")
    }

    func testNewDraftDueDateUsesTheCompanyDueRule() {
        let presets = PaymentTermsPresetStore()
        let cid = UUID()
        var net30 = presets.presets.first { $0.id == "net30" }!
        net30.dueRule = .days(45)
        presets.setOverride(net30, companyID: cid)
        let store = InvoiceStore()
        store.paymentTermsPresets = presets

        let draft = store.newDraft(companyID: cid)

        XCTAssertEqual(draft.paymentTerms, "Paiement à 30 jours")
        let expected = Calendar.current.date(byAdding: .day, value: 45, to: draft.issueDate)!
        XCTAssertTrue(Calendar.current.isDate(draft.dueDate, inSameDayAs: expected))
    }

    func testNewDraftKeepsTheDefaultDueDateForAPresetWithoutRule() {
        let (directory, sellerID) = sellerDirectory(terms: "Comptant")
        let store = InvoiceStore()
        store.paymentTermsPresets = PaymentTermsPresetStore()

        let draft = store.newDraft(directory: directory, preferredSellerEntryID: sellerID)

        XCTAssertEqual(draft.dueDate.timeIntervalSince(draft.issueDate), 30 * 86400, accuracy: 1)
    }

    /// Copie, acompte : « 30 jours fin de mois » ne fait pas le même nombre de jours d'un mois
    /// à l'autre, l'échéance est recalculée depuis la nouvelle date.
    func testCopiesOfAnInvoiceFollowingAPresetRecomputeTheDueDate() {
        let store = InvoiceStore()
        store.paymentTermsPresets = PaymentTermsPresetStore()
        let party = InvoiceParty(name: "", street: "", postcode: "", city: "")
        let issue = Calendar.current.date(byAdding: .day, value: -40, to: Date())!
        let source = Invoice(number: "FAC0001", issueDate: issue, dueDate: PaymentTermsDueRule.endOfMonthPlusDays(30).dueDate(from: issue),
                             seller: party, buyer: party, paymentTerms: "Paiement à 30 jours fin de mois")

        for copy in [store.duplicate(from: source), store.newDeposit(from: source), store.newFinalSettlement(from: source, deposits: [])] {
            let expected = PaymentTermsDueRule.endOfMonthPlusDays(30).dueDate(from: copy.issueDate)
            XCTAssertTrue(Calendar.current.isDate(copy.dueDate, inSameDayAs: expected), "\(copy.type)")
            XCTAssertEqual(store.paymentTermsPresets.matchingPreset(for: copy)?.id, "finDeMois30")
        }
    }

    /// Une échéance saisie à la main (« Personnalisé ») garde son délai dans la copie, même si
    /// le texte est celui d'un préréglage.
    func testCopyOfAManualDueDateKeepsItsTermLength() {
        let store = InvoiceStore()
        store.paymentTermsPresets = PaymentTermsPresetStore()
        let party = InvoiceParty(name: "", street: "", postcode: "", city: "")
        let issue = Date().addingTimeInterval(-10 * 86400)
        let source = Invoice(number: "FAC0001", issueDate: issue, dueDate: issue.addingTimeInterval(45 * 86400),
                             seller: party, buyer: party, paymentTerms: "Paiement à 30 jours")

        let copy = store.duplicate(from: source)

        XCTAssertEqual(copy.dueDate.timeIntervalSince(copy.issueDate), 45 * 86400, accuracy: 1)
    }
}
