import XCTest
import PDFKit
@testable import FacturXCore

/// Motif d'exonération (BT-120) et catégorie de TVA dans les PDF lisibles de facture et de
/// commande. Le motif n'était émis que dans le XML, alors qu'une facture doit citer le texte qui
/// fonde l'exonération, ou porter « Autoliquidation » (CGI, annexe II, art. 242 nonies A). La
/// colonne « TVA% » des lignes n'imprimait que le taux : avec deux catégories à 0 %, rien ne
/// disait quelle ligne allait dans quel sous-total. Choix retenu le 2026-09-23 :
/// - une ligne « <sous-total> : <motif> » en pied de page, au-dessus des mentions légales
///   PMD/PMT/AAB, qui ne bougent pas ;
/// - le code de catégorie hors S après le taux (« 0 (E) »), repris dans le libellé du
///   sous-total (« TVA 0% — Exonérée (E): »).
final class VATExemptionMentionPDFTests: XCTestCase {

    private let seller = InvoiceParty(name: "Émetteur", street: "1 rue Test", postcode: "75001", city: "Paris", country: "FR")
    private let buyer = InvoiceParty(name: "Client", street: "2 rue Test", postcode: "75008", city: "Paris", country: "FR")

    /// Pour chaque catégorie qui exige un motif : un motif type et la mention attendue.
    private let mentions: [(category: VATCategory, reason: String, mention: String)] = [
        (.exempt, "Exonération de TVA, article 261 du CGI",
         "TVA 0% — Exonérée (E) : Exonération de TVA, article 261 du CGI"),
        (.reverseCharge, "Autoliquidation, article 283-2 du CGI",
         "TVA 0% — Autoliquidation (AE) : Autoliquidation, article 283-2 du CGI"),
        (.intraCommunity, "Exonération de TVA, article 262 ter I du CGI",
         "TVA 0% — Livraison intracommunautaire (K) : Exonération de TVA, article 262 ter I du CGI"),
        (.export, "Exonération de TVA, article 262 I du CGI",
         "TVA 0% — Exportation hors UE (G) : Exonération de TVA, article 262 I du CGI"),
        (.outOfScope, "Opération hors du champ de la TVA",
         "TVA 0% — Hors champ de TVA (O) : Opération hors du champ de la TVA"),
    ]

    private func line(_ name: String, _ price: Double, _ rate: Double, _ category: VATCategory? = nil,
                      reason: String? = nil) -> InvoiceLine {
        InvoiceLine(name: name, quantity: 1, unitPrice: price, vatRate: rate, vatCategory: category, vatExemptionReason: reason)
    }

    private func invoice(_ lines: [InvoiceLine]) -> Invoice {
        Invoice(number: "F-1", seller: seller, buyer: buyer, lines: lines)
    }

    private func invoicePDF(_ lines: [InvoiceLine]) -> Data {
        InvoicePDFRenderer().render(invoice: invoice(lines))
    }

    private func orderPDF(_ lines: [InvoiceLine]) -> Data {
        OrderPDFRenderer().render(order: SalesOrder(number: "CD-1", buyer: buyer, seller: seller,
                                                    buyerReference: "ACHAT-42", lines: lines))
    }

    /// Le PDF de facture puis celui de commande, pour les mêmes lignes.
    private func pdfs(_ lines: [InvoiceLine]) -> [(document: String, pdf: Data)] {
        [("facture", invoicePDF(lines)), ("commande", orderPDF(lines))]
    }

    private func text(_ pdf: Data, file: StaticString = #filePath, line: UInt = #line) throws -> String {
        try XCTUnwrap(PDFDocument(data: pdf)?.string, "texte du PDF illisible", file: file, line: line)
    }

    /// Boîte de chaque occurrence de `string` sur la page (points PDF, origine en bas à gauche).
    private func boxes(_ string: String, in pdf: Data) throws -> [CGRect] {
        let doc = try XCTUnwrap(PDFDocument(data: pdf))
        let page = try XCTUnwrap(doc.page(at: 0))
        return doc.findString(string, withOptions: []).map { $0.bounds(for: page) }
    }

    /// Boîte de l'unique occurrence de `string`.
    private func box(_ string: String, in pdf: Data, file: StaticString = #filePath, line: UInt = #line) throws -> CGRect {
        let found = try boxes(string, in: pdf)
        XCTAssertEqual(found.count, 1, "« \(string) » introuvable ou en double", file: file, line: line)
        return try XCTUnwrap(found.first, file: file, line: line)
    }

    private func assertSameBox(_ a: CGRect, _ b: CGRect, _ message: String,
                               file: StaticString = #filePath, line: UInt = #line) {
        for (x, y) in [(a.minX, b.minX), (a.minY, b.minY), (a.maxX, b.maxX), (a.maxY, b.maxY)] {
            XCTAssertEqual(x, y, accuracy: 0.01, message, file: file, line: line)
        }
    }

    // MARK: - Mention en pied de page

    func testEachCategoryRequiringAReasonPrintsItInTheFooter() throws {
        XCTAssertEqual(Set(mentions.map(\.category)), Set(VATCategory.allCases.filter(\.requiresExemptionReason)))
        for (category, reason, mention) in mentions {
            for (document, pdf) in pdfs([line("Article", 100, 0, category, reason: reason)]) {
                let text = try text(pdf)
                XCTAssertTrue(text.contains(mention), "\(document), \(category.rawValue) : « \(mention) » absent de\n\(text)")
            }
        }
    }

    /// La mention imprime le motif du sous-total, soit le BT-120 du XML : le premier motif saisi
    /// parmi les lignes du même taux et de la même catégorie, sans les espaces autour.
    func testTheMentionPrintsTheReasonOfTheXML() throws {
        let lines = [line("Formation", 1500, 0, .exempt, reason: "  Exonération de TVA, article 261 du CGI "),
                     line("Autre formation", 500, 0, .exempt, reason: "Autre motif")]
        let xml = String(decoding: try CIIXMLGenerator().generate(invoice: invoice(lines)), as: UTF8.self)
        XCTAssertTrue(xml.contains("<ram:ExemptionReason>Exonération de TVA, article 261 du CGI</ram:ExemptionReason>"), xml)
        for (document, pdf) in pdfs(lines) {
            let text = try text(pdf)
            XCTAssertTrue(text.contains("TVA 0% — Exonérée (E) : Exonération de TVA, article 261 du CGI"), "\(document)\n\(text)")
            XCTAssertFalse(text.contains("Autre motif"), "\(document)\n\(text)")
        }
    }

    /// Ni S ni Z n'ont de motif (BR-Z-10 l'interdit même en Z) : le motif resté sur une ligne
    /// repassée de E à Z, champ masqué dans l'éditeur, ne s'imprime pas.
    func testStandardAndZeroRatedSubtotalsPrintNoMention() throws {
        let lines = [line("Article", 100, 20), line("Article à taux zéro", 50, 0, .zeroRated, reason: "Motif resté de la catégorie E")]
        for (document, pdf) in pdfs(lines) {
            let text = try text(pdf)
            XCTAssertFalse(text.contains("Motif resté"), "\(document)\n\(text)")
            XCTAssertFalse(text.contains("TVA 0% — Taux zéro (Z) :"), "\(document)\n\(text)")
            XCTAssertFalse(text.contains("TVA 20% :"), "\(document)\n\(text)")
        }
    }

    /// Motif non saisi (la pré-vérification signale BR-E-10) : aucune mention, pas même vide, et
    /// le sous-total garde son libellé.
    func testMissingReasonPrintsNoMention() throws {
        for reason in [nil, "", "   "] {
            for (document, pdf) in pdfs([line("Article exonéré", 50, 0, .exempt, reason: reason)]) {
                let text = try text(pdf)
                XCTAssertFalse(text.contains("Exonérée (E) :"), "\(document), motif \(String(describing: reason))\n\(text)")
                XCTAssertTrue(text.contains("TVA 0% — Exonérée (E):"), "\(document)\n\(text)")
            }
        }
    }

    // MARK: - Code de catégorie des lignes

    /// Deux catégories à 0 % : chaque ligne porte le code de son sous-total, repris dans le libellé
    /// de celui-ci. Les lignes et les sous-totaux en S restent au taux seul.
    func testEachLineCarriesTheCategoryCodeOfItsSubtotal() throws {
        let lines = [line("Formation", 1500, 0, .exempt, reason: "Exonération de TVA, article 261 du CGI"),
                     line("Livraison Allemagne", 500, 0, .intraCommunity, reason: "Exonération de TVA, article 262 ter I du CGI"),
                     line("Support", 100, 20)]
        for (document, pdf) in pdfs(lines) {
            let text = try text(pdf)
            for expected in ["Formation 1.00 1500.00 0 (E) 1500.00",
                             "Livraison Allemagne 1.00 500.00 0 (K) 500.00",
                             "Support 1.00 100.00 20 100.00",
                             "TVA 0% — Exonérée (E):", "TVA 0% — Livraison intracommunautaire (K):", "TVA 20%:"] {
                XCTAssertTrue(text.contains(expected), "\(document) : « \(expected) » absent de\n\(text)")
            }
        }
    }

    /// « 0 (AE) », le plus long code, tient dans la colonne « TVA% » : il finit avant le montant
    /// de la colonne « Total HT », 70 pt plus loin.
    func testTheLongestCodeEndsBeforeTheLineTotal() throws {
        for (document, pdf) in pdfs([line("Prestation", 1234.5, 0, .reverseCharge, reason: "Autoliquidation")]) {
            let cell = try box("0 (AE)", in: pdf)
            let lineTotal = try XCTUnwrap(try boxes("1234.50", in: pdf).filter { abs($0.midY - cell.midY) < 3 }.max { $0.minX < $1.minX },
                                          "\(document) : montant de la ligne")
            XCTAssertLessThan(cell.maxX, lineTotal.minX, document)
        }
    }

    // MARK: - Place dans le pied de page

    /// Facture : les mentions TVA s'empilent au-dessus des mentions légales, qui gardent leur place
    /// (une facture sans exonération ne change pas). Elles sont dans l'ordre des sous-totaux,
    /// alignées sur la marge, sous le bloc des totaux.
    func testInvoiceMentionsStackAboveTheLegalNotesWhichDoNotMove() throws {
        let plain = invoicePDF([line("Article", 100, 20)])
        let exempt = invoicePDF([line("Article", 100, 20),
                                 line("Formation", 1500, 0, .exempt, reason: "Exonération de TVA, article 261 du CGI"),
                                 line("Livraison Allemagne", 500, 0, .intraCommunity, reason: "Exonération de TVA, article 262 ter I du CGI")])
        for note in ["Pénalités de retard :", "Frais de recouvrement :", "Escompte :"] {
            assertSameBox(try box(note, in: exempt), try box(note, in: plain), note)
        }
        let firstNote = try box("Pénalités de retard :", in: exempt)
        let e = try box("TVA 0% — Exonérée (E) :", in: exempt)
        let k = try box("TVA 0% — Livraison intracommunautaire (K) :", in: exempt)
        XCTAssertGreaterThan(try box("Total TTC:", in: exempt).minY, e.maxY)
        XCTAssertGreaterThan(e.minY, k.maxY)
        XCTAssertGreaterThan(k.minY, firstNote.maxY)
        XCTAssertEqual(e.minX, firstNote.minX, accuracy: 0.5)
        XCTAssertEqual(k.minX, firstNote.minX, accuracy: 0.5)
    }

    /// Commande (sans mentions légales) : la première mention prend la hauteur de la première
    /// mention légale de la facture (y=120), dans la bande libre au-dessus de la référence
    /// acheteur, qui ne bouge pas. Avec les cinq catégories, le bloc monte sans la chevaucher.
    func testOrderMentionsFillTheFreeBandAboveTheBuyerReference() throws {
        let plain = orderPDF([line("Article", 100, 20)])
        let reference = try box("Réf. acheteur:", in: plain)
        let invoiceFirstNote = try box("Pénalités de retard :", in: invoicePDF([line("Article", 100, 20)]))

        let one = orderPDF([line("Article", 100, 20), line("Formation", 1500, 0, .exempt, reason: "Exonération de TVA, article 261 du CGI")])
        assertSameBox(try box("Réf. acheteur:", in: one), reference, "référence acheteur, une mention")
        XCTAssertEqual(try box("TVA 0% — Exonérée (E) :", in: one).minY, invoiceFirstNote.minY, accuracy: 0.5)

        let all = orderPDF(mentions.map { line("Article \($0.category.rawValue)", 100, 0, $0.category, reason: $0.reason) })
        assertSameBox(try box("Réf. acheteur:", in: all), reference, "référence acheteur, cinq mentions")
        let stacked = try mentions.map { try box(String($0.mention.prefix { $0 != ":" }) + ":", in: all) }
        XCTAssertGreaterThan(try box("Total TTC:", in: all).minY, try XCTUnwrap(stacked.first).maxY)
        for (upper, lower) in zip(stacked, stacked.dropFirst()) {
            XCTAssertGreaterThan(upper.minY, lower.maxY)
        }
        XCTAssertGreaterThan(try XCTUnwrap(stacked.last).minY, reference.maxY)
    }

    /// Un motif long passe à la ligne entre les mots, sans sortir des marges de 50 pt : la page
    /// fait 595 pt de large. Il est imprimé en entier, au-dessus des mentions légales.
    func testALongReasonWrapsInsideTheMargins() throws {
        let reason = "Exonération de TVA, article 262 ter I du CGI : livraison intracommunautaire de biens expédiés vers un "
            + "autre État membre de l'Union européenne, à destination d'un assujetti identifié à la TVA dans cet État membre."
        let mention = "TVA 0% — Livraison intracommunautaire (K) : " + reason
        func words(_ s: String) -> String { s.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
        for (document, pdf) in pdfs([line("Livraison", 500, 0, .intraCommunity, reason: reason)]) {
            let text = try text(pdf)
            XCTAssertTrue(words(text).contains(words(mention)), "\(document) : motif incomplet\n\(text)")
            let head = try box("TVA 0% — Livraison intracommunautaire (K) :", in: pdf)
            let tail = try box("État membre.", in: pdf)
            XCTAssertLessThan(tail.maxY, head.minY, "\(document) : la fin du motif doit passer à la ligne")

            let doc = try XCTUnwrap(PDFDocument(data: pdf))
            let page = try XCTUnwrap(doc.page(at: 0))
            let mentionLines = (page.selection(for: page.bounds(for: .mediaBox))?.selectionsByLine() ?? [])
                .map { $0.bounds(for: page) }
                .filter { $0.midY >= tail.minY && $0.midY <= head.maxY }
            XCTAssertGreaterThanOrEqual(mentionLines.count, 2, document)
            for lineBox in mentionLines {
                XCTAssertGreaterThanOrEqual(lineBox.minX, 49.5, "\(document) : \(lineBox)")
                XCTAssertLessThanOrEqual(lineBox.maxX, 545.5, "\(document) : \(lineBox)")
            }
        }
        let firstNote = try box("Pénalités de retard :", in: invoicePDF([line("Livraison", 500, 0, .intraCommunity, reason: reason)]))
        assertSameBox(firstNote, try box("Pénalités de retard :", in: invoicePDF([line("Article", 100, 20)])), "mentions légales")
    }
}
