import XCTest
import FacturXCore

final class FacturXEmbedderExtractionTests: XCTestCase {

    private func sampleInvoice() -> Invoice {
        Invoice(
            number: "SUP-2026-0099",
            seller: InvoiceParty(name: "Fournisseur SARL", street: "1 rue Test", postcode: "75000", city: "Paris", siren: "123456789"),
            buyer: InvoiceParty(name: "Notre Société", street: "2 rue Test", postcode: "75001", city: "Paris", siren: "987654321"),
            lines: [InvoiceLine(name: "Prestation", quantity: 1, unitPrice: 100, vatRate: 20)]
        )
    }

    /// Round-trip complet : `FacturXGenerator.generate` (PDF Factur-X) →
    /// `extractXML(fromPDF:)` → doit redonner exactement le XML que `CIIXMLGenerator`
    /// produit directement (c'est le même XML qui a été embarqué).
    func testExtractedXMLMatchesTheDirectlyGeneratedXML() throws {
        let invoice = sampleInvoice()
        let pdf = try FacturXGenerator().generate(invoice: invoice)
        let extracted = try FacturXEmbedder().extractXML(fromPDF: pdf)
        let direct = try CIIXMLGenerator().generate(invoice: invoice)
        XCTAssertEqual(extracted, direct)
    }

    /// Le XML extrait doit lui-même rester parsable et fidèle — bout en bout PDF → XML →
    /// `Invoice`, sans passer par le XML brut intermédiaire.
    func testExtractedXMLParsesBackToTheOriginalInvoice() throws {
        let invoice = sampleInvoice()
        let pdf = try FacturXGenerator().generate(invoice: invoice)
        let parsed = try CIIXMLParser.parseDepositedFile(pdf)
        XCTAssertEqual(parsed.number, invoice.number)
        XCTAssertEqual(parsed.seller.name, invoice.seller.name)
        XCTAssertEqual(parsed.lines.count, invoice.lines.count)
    }

    func testNonFacturXPDFThrowsRatherThanCrashing() {
        // Un PDF minimal valide mais sans fichier embarqué du tout.
        let minimalPDF = """
        %PDF-1.4
        1 0 obj
        << /Type /Catalog /Pages 2 0 R >>
        endobj
        2 0 obj
        << /Type /Pages /Kids [] /Count 0 >>
        endobj
        xref
        0 3
        0000000000 65535 f
        trailer
        << /Size 3 /Root 1 0 R >>
        startxref
        0
        %%EOF
        """.data(using: .ascii)!
        XCTAssertThrowsError(try FacturXEmbedder().extractXML(fromPDF: minimalPDF))
    }

    func testGarbageDataThrowsRatherThanCrashing() {
        let garbage = Data([0x00, 0x01, 0x02, 0x03])
        XCTAssertThrowsError(try FacturXEmbedder().extractXML(fromPDF: garbage)) { error in
            XCTAssertEqual(error as? FacturXEmbedError, .invalidPDF)
        }
    }
}
