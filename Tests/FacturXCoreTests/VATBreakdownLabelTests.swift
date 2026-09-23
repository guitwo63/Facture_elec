import XCTest
import PDFKit
@testable import FacturXCore

/// Libellé des sous-totaux de TVA (`VATBreakdownEntry.label`), commun aux totaux des éditeurs de
/// facture et de commande et à leurs PDF. Avec le taux seul, une ligne à 0 % « Taux zéro » et une
/// ligne à 0 % « Exonérée » donnaient deux sous-totaux au même libellé : « TVA 0% 0.00 EUR » deux
/// fois à l'écran, « TVA 0%: EUR 0.00 » deux fois dans le PDF. Choix retenu le 2026-09-23 : le
/// libellé de la catégorie, dès qu'elle n'est pas S, même quand elle est seule à son taux.
final class VATBreakdownLabelTests: XCTestCase {

    private let seller = InvoiceParty(name: "Émetteur", street: "1 rue Test", postcode: "75001", city: "Paris", country: "FR")
    private let buyer = InvoiceParty(name: "Client", street: "2 rue Test", postcode: "75008", city: "Paris", country: "FR")

    private func vatLine(_ price: Double, _ rate: Double, _ category: VATCategory? = nil) -> InvoiceLine {
        InvoiceLine(name: "Article", quantity: 1, unitPrice: price, vatRate: rate, vatCategory: category,
                    vatExemptionReason: category?.requiresExemptionReason == true ? "Motif d'exonération" : nil)
    }

    private func invoice(_ lines: [InvoiceLine]) -> Invoice {
        Invoice(number: "F-1", seller: seller, buyer: buyer, lines: lines)
    }

    private func order(_ lines: [InvoiceLine]) -> SalesOrder {
        SalesOrder(number: "CD-1", buyer: buyer, seller: seller, lines: lines)
    }

    // MARK: - Libellé

    func testStandardCategoryLabelIsTheRateAlone() {
        XCTAssertEqual(invoice([vatLine(100, 20), vatLine(100, 5.5), vatLine(100, 2.1)]).vatBreakdown.map(\.label),
                       ["TVA 2.1%", "TVA 5.5%", "TVA 20%"])
    }

    func testTwoSubtotalsAtTheSameRateNoLongerShareALabel() {
        let breakdown = invoice([vatLine(100, 20), vatLine(50, 0, .zeroRated), vatLine(30, 0, .exempt)]).vatBreakdown
        XCTAssertEqual(breakdown.map(\.label), ["TVA 0% — Taux zéro", "TVA 0% — Exonérée", "TVA 20%"])
    }

    /// Même seule à son taux, une catégorie autre que S est nommée : le sous-total dit pourquoi
    /// la TVA est nulle, et son libellé ne dépend pas des autres lignes.
    func testEveryOtherCategoryIsNamedEvenAloneAtItsRate() {
        let expected: [VATCategory: String] = [
            .zeroRated: "TVA 0% — Taux zéro",
            .exempt: "TVA 0% — Exonérée",
            .reverseCharge: "TVA 0% — Autoliquidation",
            .intraCommunity: "TVA 0% — Livraison intracommunautaire",
            .export: "TVA 0% — Exportation hors UE",
            .outOfScope: "TVA 0% — Hors champ de TVA",
        ]
        XCTAssertEqual(Set(expected.keys), Set(VATCategory.allCases).subtracting([.standard]))
        for (category, label) in expected {
            XCTAssertEqual(invoice([vatLine(100, 20), vatLine(50, 0, category)]).vatBreakdown.map(\.label),
                           [label, "TVA 20%"], category.rawValue)
        }
    }

    // MARK: - PDF

    func testInvoiceAndOrderPDFsNameTheCategoryOfEachZeroRateSubtotal() throws {
        let lines = [vatLine(100, 20), vatLine(50, 0, .zeroRated), vatLine(30, 0, .exempt)]
        let pdfs = [("facture", InvoicePDFRenderer().render(invoice: invoice(lines))),
                    ("commande", OrderPDFRenderer().render(order: order(lines)))]
        for (document, pdf) in pdfs {
            let text = try XCTUnwrap(PDFDocument(data: pdf)?.string, "\(document) : texte du PDF illisible")
            for label in ["TVA 0% — Taux zéro:", "TVA 0% — Exonérée:", "TVA 20%:"] {
                XCTAssertTrue(text.contains(label), "\(document) : « \(label) » absent de\n\(text)")
            }
            XCTAssertFalse(text.contains("TVA 0%:"), "\(document) : sous-total à 0 % sans sa catégorie\n\(text)")
        }
    }

    /// La colonne des libellés du bloc des totaux (90 pt avant les montants) s'élargit vers la
    /// gauche pour le plus long : « TVA 0% — Livraison intracommunautaire: » fait 203 pt. Avant ce
    /// changement, « Acompte déjà payé: » (97 pt) chevauchait déjà son montant.
    func testTotalsLabelsEndBeforeTheirAmounts() throws {
        var deposit = invoice([vatLine(500, 0, .intraCommunity)])
        deposit.prepaidAmount = 100
        try assertLabelsEndBeforeTheirAmounts(
            InvoicePDFRenderer().render(invoice: deposit),
            ["Total HT:", "TVA 0% — Livraison intracommunautaire:", "Total TTC:", "Acompte déjà payé:", "Net à payer:"])
        try assertLabelsEndBeforeTheirAmounts(
            OrderPDFRenderer().render(order: order([vatLine(500, 0, .intraCommunity)])),
            ["Total HT:", "TVA 0% — Livraison intracommunautaire:", "Total TTC:"])
    }

    private func assertLabelsEndBeforeTheirAmounts(_ pdf: Data, _ labels: [String],
                                                   file: StaticString = #filePath, line: UInt = #line) throws {
        let doc = try XCTUnwrap(PDFDocument(data: pdf), file: file, line: line)
        let page = try XCTUnwrap(doc.page(at: 0), file: file, line: line)
        let amounts = doc.findString("EUR ", withOptions: []).map { $0.bounds(for: page) }
        for label in labels {
            let found = doc.findString(label, withOptions: []).map { $0.bounds(for: page) }
            XCTAssertEqual(found.count, 1, "« \(label) » introuvable ou en double", file: file, line: line)
            guard let box = found.first else { continue }
            let sameLine = amounts.filter { abs($0.midY - box.midY) < 3 }
            XCTAssertEqual(sameLine.count, 1, "montant de la ligne « \(label) »", file: file, line: line)
            if let amount = sameLine.first {
                XCTAssertLessThan(box.maxX, amount.minX, "« \(label) » chevauche son montant", file: file, line: line)
            }
        }
    }
}
