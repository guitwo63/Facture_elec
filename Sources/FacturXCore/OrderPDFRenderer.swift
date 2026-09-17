import Foundation
import CoreGraphics
import CoreText
import AppKit

public final class OrderPDFRenderer {
    public init() {}

    private let pageWidth: CGFloat = 595.0
    private let pageHeight: CGFloat = 842.0
    private let margin: CGFloat = 50.0

    public func render(order: SalesOrder) -> Data {
        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData) else {
            return Data()
        }
        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return Data()
        }

        let pageRect = mediaBox
        context.beginPage(mediaBox: &mediaBox)

        let yTop = pageRect.height - margin
        drawHeader(context: context, order: order, y: yTop)
        drawParties(context: context, order: order, y: yTop - 70)
        let tableY = drawLinesTable(context: context, order: order, y: yTop - 230)
        drawTotals(context: context, order: order, y: tableY - 20)
        drawFooter(context: context, order: order)

        context.endPage()
        context.closePDF()

        return pdfData as Data
    }

    private func drawHeader(context: CGContext, order: SalesOrder, y: CGFloat) {
        let title = "COMMANDE"
        drawText(context: context, text: title, x: margin, y: y, font: boldFont(size: 24), color: .black)
        drawText(context: context, text: order.number, x: pageWidth - margin - 180, y: y, font: boldFont(size: 14), color: .black)

        let df = DateFormatter()
        df.dateFormat = "dd/MM/yyyy"
        let issueLine = "Date: \(df.string(from: order.issueDate))"
        let deliveryLine = "Livraison souhaitée: \(df.string(from: order.requestedDeliveryDate))"
        drawText(context: context, text: issueLine, x: pageWidth - margin - 180, y: y - 18, font: font(size: 10), color: .black)
        drawText(context: context, text: deliveryLine, x: pageWidth - margin - 180, y: y - 34, font: font(size: 10), color: .black)
        drawText(context: context, text: order.type.label, x: pageWidth - margin - 180, y: y - 50, font: font(size: 10), color: .darkGray)
    }

    private func drawParties(context: CGContext, order: SalesOrder, y: CGFloat) {
        drawText(context: context, text: "ÉMETTEUR", x: margin, y: y, font: boldFont(size: 11), color: .darkGray)
        drawParty(context: context, party: order.seller, x: margin, y: y - 16)

        drawText(context: context, text: "CLIENT", x: pageWidth / 2, y: y, font: boldFont(size: 11), color: .darkGray)
        drawParty(context: context, party: order.buyer, x: pageWidth / 2, y: y - 16)
    }

    private func drawParty(context: CGContext, party: InvoiceParty, x: CGFloat, y: CGFloat) {
        var cy = y
        drawText(context: context, text: party.name, x: x, y: cy, font: boldFont(size: 12), color: .black)
        cy -= 14
        drawText(context: context, text: party.street, x: x, y: cy, font: font(size: 10), color: .black)
        cy -= 12
        drawText(context: context, text: "\(party.postcode) \(party.city), \(party.country)", x: x, y: cy, font: font(size: 10), color: .black)
        cy -= 12
        if let vat = party.vatNumber {
            drawText(context: context, text: "TVA: \(vat)", x: x, y: cy, font: font(size: 10), color: .black)
            cy -= 12
        }
        if let siren = party.siren {
            drawText(context: context, text: "SIREN: \(siren)", x: x, y: cy, font: font(size: 10), color: .black)
        }
    }

    private func drawLinesTable(context: CGContext, order: SalesOrder, y: CGFloat) -> CGFloat {
        let colX = [margin, margin + 230, margin + 330, margin + 400, margin + 470]
        let headerY = y
        drawText(context: context, text: "Désignation", x: colX[0], y: headerY, font: boldFont(size: 10), color: .black)
        drawText(context: context, text: "Qté", x: colX[1], y: headerY, font: boldFont(size: 10), color: .black)
        drawText(context: context, text: "P.U. HT", x: colX[2], y: headerY, font: boldFont(size: 10), color: .black)
        drawText(context: context, text: "TVA%", x: colX[3], y: headerY, font: boldFont(size: 10), color: .black)
        drawText(context: context, text: "Total HT", x: colX[4], y: headerY, font: boldFont(size: 10), color: .black)

        context.setLineWidth(0.5)
        context.move(to: CGPoint(x: margin, y: headerY - 4))
        context.addLine(to: CGPoint(x: pageWidth - margin, y: headerY - 4))
        context.strokePath()

        var cy = headerY - 18
        for line in order.lines {
            drawText(context: context, text: line.name, x: colX[0], y: cy, font: font(size: 10), color: .black)
            drawText(context: context, text: fmt(line.quantity), x: colX[1], y: cy, font: font(size: 10), color: .black)
            drawText(context: context, text: fmt(line.unitPrice), x: colX[2], y: cy, font: font(size: 10), color: .black)
            drawText(context: context, text: fmt(line.vatRate, dec: 0), x: colX[3], y: cy, font: font(size: 10), color: .black)
            drawText(context: context, text: fmt(line.lineTotal), x: colX[4], y: cy, font: font(size: 10), color: .black)
            cy -= 16
        }
        return cy
    }

    private func drawTotals(context: CGContext, order: SalesOrder, y: CGFloat) {
        let x = pageWidth - margin - 180
        var cy = y
        drawText(context: context, text: "Total HT:", x: x, y: cy, font: font(size: 11), color: .black)
        drawText(context: context, text: "\(order.currency) \(fmt(order.lineTotal))", x: pageWidth - margin - 90, y: cy, font: boldFont(size: 11), color: .black)
        cy -= 16
        for item in order.vatBreakdown {
            drawText(context: context, text: "TVA \(fmt(item.rate, dec: 0))%:", x: x, y: cy, font: font(size: 11), color: .black)
            drawText(context: context, text: "\(order.currency) \(fmt(item.amount))", x: pageWidth - margin - 90, y: cy, font: font(size: 11), color: .black)
            cy -= 16
        }
        cy -= 4
        context.setLineWidth(0.5)
        context.move(to: CGPoint(x: x, y: cy))
        context.addLine(to: CGPoint(x: pageWidth - margin, y: cy))
        context.strokePath()
        cy -= 16
        drawText(context: context, text: "Total TTC:", x: x, y: cy, font: boldFont(size: 13), color: .black)
        drawText(context: context, text: "\(order.currency) \(fmt(order.grandTotal))", x: pageWidth - margin - 90, y: cy, font: boldFont(size: 13), color: .black)
    }

    private func drawFooter(context: CGContext, order: SalesOrder) {
        let y: CGFloat = 80
        if let ref = order.buyerReference, !ref.isEmpty {
            drawText(context: context, text: "Réf. acheteur: \(ref)", x: margin, y: y, font: font(size: 9), color: .darkGray)
        }
        if let terms = order.notes {
            drawText(context: context, text: "Notes: \(terms)", x: margin, y: y - 12, font: font(size: 9), color: .darkGray)
        }
        drawText(context: context, text: "Commande électronique Order-X profil \(order.profile.rawValue) — conforme CIO D20B",
                 x: margin, y: 40, font: font(size: 8), color: .gray)
    }

    private func drawText(context: CGContext, text: String, x: CGFloat, y: CGFloat,
                          font: CTFont, color: NSColor) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color.cgColor,
        ]
        let attr = NSAttributedString(string: text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attr as CFAttributedString)
        context.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, context)
    }

    private func boldFont(size: CGFloat) -> CTFont {
        CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
    }

    private func font(size: CGFloat) -> CTFont {
        CTFontCreateWithName("Helvetica" as CFString, size, nil)
    }

    private func fmt(_ value: Double, dec: Int = 2) -> String {
        if dec == 0 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.\(dec)f", value)
    }
}
