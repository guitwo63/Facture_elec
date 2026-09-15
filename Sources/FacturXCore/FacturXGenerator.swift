import Foundation

/// Façade : génère une facture Factur-X complète à partir d'un modèle Invoice.
/// Produit un PDF lisible (rendu CoreGraphics) + CII XML (conforme EN 16931)
/// embarqué dans un conteneur PDF/A-3 avec XMP Factur-X.
public struct FacturXGenerator {
    public init() {}

    public func generate(invoice: Invoice) throws -> Data {
        try generate(invoice: invoice, logo: nil)
    }

    public func generate(invoice: Invoice, logo: Data?) throws -> Data {
        let xmlGenerator = CIIXMLGenerator()
        let xml = try xmlGenerator.generate(invoice: invoice)

        let renderer = InvoicePDFRenderer()
        let pdf = renderer.render(invoice: invoice, logo: logo)

        let embedder = FacturXEmbedder()
        let facturx = try embedder.embed(pdfData: pdf, xml: xml, invoice: invoice)
        return facturx
    }

    public func generateXML(invoice: Invoice) throws -> Data {
        let xmlGenerator = CIIXMLGenerator()
        return try xmlGenerator.generate(invoice: invoice)
    }

    public func generateVisiblePDF(invoice: Invoice) -> Data {
        generateVisiblePDF(invoice: invoice, logo: nil)
    }

    public func generateVisiblePDF(invoice: Invoice, logo: Data?) -> Data {
        let renderer = InvoicePDFRenderer()
        return renderer.render(invoice: invoice, logo: logo)
    }
}
