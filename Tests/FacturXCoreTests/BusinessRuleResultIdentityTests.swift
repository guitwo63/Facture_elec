import XCTest
import FacturXCore

/// Le panneau de validation de l'éditeur de facture affiche les résultats avec
/// `ForEach(ruleErrors)` / `ForEach(ruleWarnings)`, donc via leur `id`. Plusieurs résultats
/// partagent souvent le même `ruleId` (les trois mentions BR-FR-05, une règle par ligne
/// fautive, BR-FR-09 et BR-CO-09 émetteur + destinataire…) : si l'`id` n'était que le `ruleId`,
/// SwiftUI aurait des identités en double — comportement indéfini, lignes dupliquées ou
/// manquantes à l'écran. Le `ruleId` lui-même ne change pas : le surlignage rouge des
/// champs (`errorRuleIDs`) et les autres tests s'en servent.
final class BusinessRuleResultIdentityTests: XCTestCase {

    /// Déclenche en une seule évaluation chaque règle qui peut sortir plusieurs fois : les
    /// trois mentions légales, SIRET invalide et n° TVA sans préfixe pays des deux côtés,
    /// et toutes les règles par ligne sur au moins deux lignes.
    private func invoiceWithRepeatedRuleIds() -> Invoice {
        func faultyLine() -> InvoiceLine {
            InvoiceLine(name: "", quantity: 0, unit: "", unitPrice: -10, vatRate: 0,
                        optionalFields: [OptionalField(tagName: "ram:GlobalID", value: "123")])
        }
        func exemptLineWithRate() -> InvoiceLine {
            InvoiceLine(name: "Exonérée", quantity: 1, unitPrice: 100, vatRate: 5.5, vatCategory: .exempt)
        }
        func zeroRatedLineWithRate() -> InvoiceLine {
            InvoiceLine(name: "Taux zéro", quantity: 1, unitPrice: 100, vatRate: 5.5, vatCategory: .zeroRated)
        }
        return Invoice(
            number: "2026-0002",
            seller: InvoiceParty(name: "Émetteur", street: "1 rue Test", postcode: "75001", city: "Paris",
                                 vatNumber: "XX123", siret: "1234", endpointID: "123456782"),
            buyer: InvoiceParty(name: "Client", street: "2 rue Test", postcode: "75008", city: "Paris",
                                vatNumber: "XX456", siret: "5678", endpointID: "987654324"),
            lines: [faultyLine(), faultyLine(), exemptLineWithRate(), exemptLineWithRate(),
                    zeroRatedLineWithRate(), zeroRatedLineWithRate()],
            legalNotePMT: "",
            legalNotePMD: "",
            legalNoteAAB: ""
        )
    }

    private func duplicatedIDs(_ results: [BusinessRuleResult]) -> [String] {
        Dictionary(grouping: results, by: \.id).filter { $0.value.count > 1 }.keys.sorted()
    }

    func testEveryResultHasADistinctIdentityEvenWhenRuleIdsRepeat() {
        for context in [EN16931RuleContext.issued, .received] {
            let results = EN16931BusinessRules.evaluate(invoice: invoiceWithRepeatedRuleIds(), context: context)
            let repeatedRuleIDs = Set(Dictionary(grouping: results, by: \.ruleId).filter { $0.value.count > 1 }.keys)
            var expectedRepeats: Set<String> = ["BR-FR-09", "BR-CO-09", "BR-25", "BT-129-POSITIVE", "BR-27", "BR-23",
                                                "BT-152-ZERO", "BR-E-05", "BR-E-10", "BR-Z-05", "BT-157-GTIN"]
            if context == .issued { expectedRepeats.insert("BR-FR-05") }
            XCTAssertTrue(expectedRepeats.isSubset(of: repeatedRuleIDs),
                          "\(context) : ruleId attendus en double mais absents : \(expectedRepeats.subtracting(repeatedRuleIDs).sorted())")

            XCTAssertEqual(Set(results.map(\.id)).count, results.count,
                           "\(context) : identités en double dans le panneau de validation : \(duplicatedIDs(results))")
        }
    }

    /// Cas le plus courant à l'écran : une facture sans mentions légales doit afficher trois
    /// erreurs BR-FR-05 distinctes (PMT, PMD, AAB), pas trois fois la même.
    func testMissingLegalNotesGiveThreeDistinctBRFR05Errors() {
        let invoice = Invoice(
            number: "2026-0001",
            seller: InvoiceParty(name: "Émetteur", street: "1 rue Test", postcode: "75001", city: "Paris",
                                 vatNumber: "FR12345678901", endpointID: "123456782"),
            buyer: InvoiceParty(name: "Client", street: "2 rue Test", postcode: "75008", city: "Paris",
                                endpointID: "987654324"),
            lines: [InvoiceLine(name: "Prestation", quantity: 1, unitPrice: 100, vatRate: 20)],
            legalNotePMT: "",
            legalNotePMD: "",
            legalNoteAAB: ""
        )
        let errors = EN16931BusinessRules.evaluate(invoice: invoice).filter { $0.ruleId == "BR-FR-05" }

        XCTAssertEqual(errors.map(\.ruleId), ["BR-FR-05", "BR-FR-05", "BR-FR-05"], "le ruleId, utilisé par le surlignage, ne change pas")
        XCTAssertEqual(Set(errors.map(\.id)).count, 3, "trois identités distinctes : \(errors.map(\.id))")
        for code in ["PMT", "PMD", "AAB"] {
            XCTAssertEqual(errors.filter { $0.message.contains("SubjectCode \(code)") }.count, 1, code)
        }
    }

    /// L'identité dépend du contenu, pas d'un UUID : relancer la validation sur la même
    /// facture redonne les mêmes identités (SwiftUI garde les mêmes lignes) et des résultats
    /// égaux au sens de `Hashable`.
    func testIdentityIsStableAcrossEvaluations() {
        let first = EN16931BusinessRules.evaluate(invoice: invoiceWithRepeatedRuleIds())
        let second = EN16931BusinessRules.evaluate(invoice: invoiceWithRepeatedRuleIds())
        XCTAssertEqual(first.map(\.id), second.map(\.id))
        XCTAssertEqual(first, second)
    }
}
