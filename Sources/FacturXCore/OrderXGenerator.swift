import Foundation

/// Façade : génère une commande Order-X complète à partir d'un modèle SalesOrder.
/// Produit un PDF lisible (rendu CoreGraphics) + CIO XML (D20B)
/// embarqué dans un conteneur PDF/A-3 avec XMP Order-X (fx:DocumentType selon le type de document).
public struct OrderXGenerator {
    public init() {}

    public func generate(order: SalesOrder) throws -> Data {
        let xmlGenerator = OrderCIOXMLGenerator()
        let xml = try xmlGenerator.generate(order: order)

        let renderer = OrderPDFRenderer()
        let pdf = renderer.render(order: order)

        let embedder = OrderXEmbedder()
        let orderx = try embedder.embed(pdfData: pdf, xml: xml, order: order)
        return orderx
    }

    public func generateXML(order: SalesOrder) throws -> Data {
        let xmlGenerator = OrderCIOXMLGenerator()
        return try xmlGenerator.generate(order: order)
    }

    public func generateVisiblePDF(order: SalesOrder) -> Data {
        let renderer = OrderPDFRenderer()
        return renderer.render(order: order)
    }
}
