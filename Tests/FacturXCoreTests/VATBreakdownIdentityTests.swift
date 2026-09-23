import XCTest
@testable import FacturXCore

/// Les éditeurs de facture et de commande affichent les totaux TVA avec
/// `ForEach(….vatBreakdown)`, donc via l'`id` de chaque sous-total. La ventilation regroupe
/// les lignes par couple (taux, catégorie) : une ligne à 0 % « Taux zéro » et une ligne à 0 %
/// « Exonérée » donnent deux sous-totaux au même taux. Avec l'ancienne identité
/// `id: \.rate`, ces deux lignes avaient la même identité, et SwiftUI affichait le contenu
/// d'un seul des deux sous-totaux sur les deux lignes.
final class VATBreakdownIdentityTests: XCTestCase {

    private let seller = InvoiceParty(name: "Émetteur", street: "1 rue Test", postcode: "75001", city: "Paris", country: "FR")
    private let buyer = InvoiceParty(name: "Client", street: "2 rue Test", postcode: "75008", city: "Paris", country: "FR")

    private let exemptionReason = "Exonération de TVA, article 261 du CGI"

    /// Le scénario du test manuel : une ligne à 20 %, une à 0 % « Taux zéro » et une à 0 %
    /// « Exonérée » avec un motif.
    private func lines(exemptPrice: Double = 30) -> [InvoiceLine] {
        [
            InvoiceLine(name: "Normal", quantity: 1, unitPrice: 100, vatRate: 20),
            InvoiceLine(name: "Taux zéro", quantity: 1, unitPrice: 50, vatRate: 0, vatCategory: .zeroRated),
            InvoiceLine(name: "Exonérée", quantity: 1, unitPrice: exemptPrice, vatRate: 0, vatCategory: .exempt,
                        vatExemptionReason: exemptionReason),
        ]
    }

    private func breakdowns() -> [(String, [VATBreakdownEntry])] {
        [
            ("facture", Invoice(number: "F-1", seller: seller, buyer: buyer, lines: lines()).vatBreakdown),
            ("commande", SalesOrder(number: "CD-1", buyer: buyer, seller: seller, lines: lines()).vatBreakdown),
            ("devis", Quote(number: "DEV-1", seller: seller, buyer: buyer, lines: lines()).vatBreakdown),
        ]
    }

    func testSameRateDifferentCategoriesHaveDistinctIdentities() {
        let zero = VATBreakdownEntry.Key(rate: 0, category: .zeroRated)
        let exempt = VATBreakdownEntry.Key(rate: 0, category: .exempt)
        let standard = VATBreakdownEntry.Key(rate: 20, category: .standard)
        for (document, breakdown) in breakdowns() {
            XCTAssertEqual(breakdown.count, 3, document)
            XCTAssertEqual(Set(breakdown.map(\.rate)).count, 2,
                           "\(document) : deux sous-totaux à 0 %, le taux seul ne peut pas servir d'identité")
            XCTAssertEqual(Set(breakdown.map(\.id)).count, breakdown.count, "\(document) : identités en double")
            XCTAssertEqual(Set(breakdown.map(\.id)), [zero, exempt, standard], document)

            // Ce que chaque ligne de totaux doit montrer : le contenu de son propre sous-total.
            let byID = Dictionary(uniqueKeysWithValues: breakdown.map { ($0.id, $0) })
            XCTAssertEqual(byID[zero]?.basis, 50, document)
            XCTAssertNil(byID[zero]?.exemptionReason, document)
            XCTAssertEqual(byID[exempt]?.basis, 30, document)
            XCTAssertEqual(byID[exempt]?.exemptionReason, exemptionReason, document)
            XCTAssertEqual(byID[standard]?.amount, 20, document)
        }
    }

    /// Modifier le prix d'une ligne ou le motif ne change pas l'identité du sous-total : SwiftUI
    /// garde la même ligne de totaux pendant la saisie. Une ligne de plus dans un couple
    /// (taux, catégorie) existant ne crée pas de nouvelle identité.
    func testIdentityDependsOnlyOnRateAndCategory() {
        let before = Invoice(number: "F-1", seller: seller, buyer: buyer, lines: lines()).vatBreakdown
        var edited = lines(exemptPrice: 45)
        edited[2].vatExemptionReason = "Autre motif"
        edited.append(InvoiceLine(name: "Taux zéro bis", quantity: 2, unitPrice: 10, vatRate: 0, vatCategory: .zeroRated))
        let after = Invoice(number: "F-1", seller: seller, buyer: buyer, lines: edited).vatBreakdown

        XCTAssertEqual(Set(after.map(\.id)), Set(before.map(\.id)))
        XCTAssertNotEqual(after.map(\.basis).sorted(), before.map(\.basis).sorted(), "les bases ont bien changé")
    }
}
