import Foundation
import CoreGraphics
import CoreText
import AppKit

public final class InvoicePDFRenderer {
    public init() {}

    private let pageWidth: CGFloat = 595.0
    private let pageHeight: CGFloat = 842.0
    private let margin: CGFloat = 50.0

    public func render(invoice: Invoice) -> Data {
        render(invoice: invoice, logo: nil)
    }

    /// Rend le PDF lisible. Si `logo` est fourni (données d'image PNG/JPEG/TIFF),
    /// il est dessiné en en-tête à gauche, à la place du nom de l'émetteur.
    public func render(invoice: Invoice, logo: Data?) -> Data {
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
        let logoBox: CGRect? = drawLogo(context: context, logo: logo, y: yTop, maxWidth: 160, maxHeight: 60)
        drawHeader(context: context, invoice: invoice, y: yTop, logoBox: logoBox)
        drawParties(context: context, invoice: invoice, y: yTop - 84)
        let tableY = drawLinesTable(context: context, invoice: invoice, y: yTop - 230)
        drawTotals(context: context, invoice: invoice, y: tableY - 20)
        drawFooter(context: context, invoice: invoice)

        context.endPage()
        context.closePDF()

        return pdfData as Data
    }

    private func drawLogo(context: CGContext, logo: Data?, y: CGFloat, maxWidth: CGFloat, maxHeight: CGFloat) -> CGRect? {
        guard let data = logo, !data.isEmpty,
              let provider = CGDataProvider(data: data as CFData) else {
            return nil
        }
        let image = CGImage(pngDataProviderSource: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
            ?? CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        guard let image = image else { return nil }
        let imgW = CGFloat(image.width)
        let imgH = CGFloat(image.height)
        guard imgW > 0, imgH > 0 else { return nil }
        let scale = min(maxWidth / imgW, maxHeight / imgH, 1.0)
        let drawW = imgW * scale
        let drawH = imgH * scale
        let rect = CGRect(x: margin, y: y - maxHeight + (maxHeight - drawH) / 2, width: drawW, height: drawH)
        context.saveGState()
        context.draw(image, in: rect)
        context.restoreGState()
        return rect
    }

    private func drawHeader(context: CGContext, invoice: Invoice, y: CGFloat, logoBox: CGRect?) {
        let title: String
        if invoice.type.isInternalCreditNote {
            title = "AVOIR INTERNE"
        } else if invoice.type.isCreditNote {
            title = "AVOIR"
        } else {
            title = "FACTURE"
        }
        let titleX: CGFloat = (logoBox?.maxX ?? margin) + 10
        drawText(context: context, text: title, x: titleX, y: y, font: boldFont(size: 24), color: .black)
        drawText(context: context, text: invoice.number, x: pageWidth - margin - 180, y: y, font: boldFont(size: 14), color: .black)

        if let ref = invoice.precedingInvoiceRef?.trimmingCharacters(in: .whitespaces), !ref.isEmpty {
            let refDf = DateFormatter()
            refDf.dateFormat = "dd/MM/yyyy"
            let refLine: String
            if let date = invoice.precedingInvoiceDate {
                refLine = "Facture antérieure: \(ref) du \(refDf.string(from: date))"
            } else {
                refLine = "Facture antérieure: \(ref)"
            }
            drawText(context: context, text: refLine, x: titleX, y: y - 34, font: font(size: 10), color: .darkGray)
        }

        let df = DateFormatter()
        df.dateFormat = "dd/MM/yyyy"
        let issueLine = "Date: \(df.string(from: invoice.issueDate))"
        let dueLine = "Échéance: \(df.string(from: invoice.dueDate))"
        drawText(context: context, text: issueLine, x: pageWidth - margin - 180, y: y - 18, font: font(size: 10), color: .black)
        drawText(context: context, text: dueLine, x: pageWidth - margin - 180, y: y - 34, font: font(size: 10), color: .black)
        var infoY = y - 50
        if let terms = invoice.paymentTerms?.trimmingCharacters(in: .whitespaces), !terms.isEmpty {
            drawText(context: context, text: "Conditions: \(terms)", x: pageWidth - margin - 180, y: infoY, font: font(size: 9), color: .darkGray)
            infoY -= 14
        }
        drawText(context: context, text: invoice.type.label, x: pageWidth - margin - 180, y: infoY, font: font(size: 10), color: .darkGray)
    }

    private func drawParties(context: CGContext, invoice: Invoice, y: CGFloat) {
        drawText(context: context, text: "ÉMETTEUR", x: margin, y: y, font: boldFont(size: 11), color: .darkGray)
        drawParty(context: context, party: invoice.seller, x: margin, y: y - 16)

        drawText(context: context, text: "DESTINATAIRE", x: pageWidth / 2, y: y, font: boldFont(size: 11), color: .darkGray)
        drawParty(context: context, party: invoice.buyer, x: pageWidth / 2, y: y - 16)
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

    private func drawLinesTable(context: CGContext, invoice: Invoice, y: CGFloat) -> CGFloat {
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
        for line in invoice.lines {
            drawText(context: context, text: line.name, x: colX[0], y: cy, font: font(size: 10), color: .black)
            drawText(context: context, text: fmt(line.quantity), x: colX[1], y: cy, font: font(size: 10), color: .black)
            drawText(context: context, text: fmt(line.unitPrice), x: colX[2], y: cy, font: font(size: 10), color: .black)
            drawText(context: context, text: line.pdfVATRate, x: colX[3], y: cy, font: font(size: 10), color: .black)
            drawText(context: context, text: fmt(line.lineTotal), x: colX[4], y: cy, font: font(size: 10), color: .black)
            cy -= 16
        }
        return cy
    }

    /// Ligne du bloc des totaux : libellé dans la colonne des libellés, montant dans celle des montants.
    private struct TotalsRow {
        let label: String
        let amount: String
        let font: CTFont
        var amountFont: CTFont? = nil
        var color: NSColor = .black
    }

    private func drawTotals(context: CGContext, invoice: Invoice, y: CGFloat) {
        let amount = { (value: Double) in "\(invoice.currency) \(self.fmt(value))" }
        let rowsAboveRule = [TotalsRow(label: "Total HT:", amount: amount(invoice.lineTotal), font: font(size: 11), amountFont: boldFont(size: 11))]
            + invoice.vatBreakdown.map { TotalsRow(label: "\($0.pdfLabel):", amount: amount($0.amount), font: font(size: 11)) }
        var rowsBelowRule = [TotalsRow(label: "Total TTC:", amount: amount(invoice.grandTotal), font: boldFont(size: 13))]
        if invoice.prepaidAmount > 0 {
            rowsBelowRule.append(TotalsRow(label: "\(invoice.prepaidAmountLabel):", amount: amount(invoice.prepaidAmount), font: font(size: 11), color: .darkGray))
            rowsBelowRule.append(TotalsRow(label: "Net à payer:", amount: amount(invoice.netToPay), font: boldFont(size: 13)))
        }
        // Hors euro, la TVA doit aussi figurer en euros (directive TVA, art. 230 ; BT-111 du XML),
        // suivie du taux appliqué. Une facture en euros garde exactement la même page.
        if let taxInEuros = invoice.taxTotalInEuros {
            rowsBelowRule.append(TotalsRow(label: "Total TVA en EUR:", amount: "EUR \(fmt(taxInEuros))", font: font(size: 11)))
        }
        let x = totalsLabelX(rowsAboveRule + rowsBelowRule)
        var cy = y
        for row in rowsAboveRule {
            drawTotalsRow(context: context, row, x: x, y: cy)
            cy -= 16
        }
        cy -= 4
        context.setLineWidth(0.5)
        context.move(to: CGPoint(x: x, y: cy))
        context.addLine(to: CGPoint(x: pageWidth - margin, y: cy))
        context.strokePath()
        for row in rowsBelowRule {
            cy -= 16
            drawTotalsRow(context: context, row, x: x, y: cy)
        }
        for sentence in invoice.exchangeRateMention {
            for line in wrappedLines(sentence, font: font(size: 8), width: pageWidth - margin - x) {
                cy -= 11
                drawText(context: context, text: line, x: x, y: cy, font: font(size: 8), color: .darkGray)
            }
        }
    }

    /// Colonne des montants du bloc des totaux, à 90 pt de la marge droite.
    private var totalsAmountX: CGFloat { pageWidth - margin - 90 }

    /// Colonne des libellés : 90 pt avant les montants, décalée vers la gauche dès qu'un libellé
    /// n'y tient plus avec 12 pt d'écart. « TVA 0% — Livraison intracommunautaire (K): » fait
    /// 221 pt, et « Acompte déjà payé: » (97 pt) chevauchait déjà son montant.
    private func totalsLabelX(_ rows: [TotalsRow]) -> CGFloat {
        let widest = rows.map { textWidth($0.label, font: $0.font) }.max() ?? 0
        return min(totalsAmountX - 90, totalsAmountX - 12 - widest)
    }

    private func drawTotalsRow(context: CGContext, _ row: TotalsRow, x: CGFloat, y: CGFloat) {
        drawText(context: context, text: row.label, x: x, y: y, font: row.font, color: row.color)
        drawText(context: context, text: row.amount, x: totalsAmountX, y: y, font: row.amountFont ?? row.font, color: row.color)
    }

    private func drawFooter(context: CGContext, invoice: Invoice) {
        // Mentions d'exonération de TVA au-dessus des mentions légales, qui restent à y=120 :
        // le pied de page monte de 11 pt par ligne de mention, et une facture sans exonération
        // garde la même page.
        let vatMentions = invoice.vatBreakdown.compactMap(\.pdfExemptionMention)
            .flatMap { wrappedLines($0, font: font(size: 8), width: pageWidth - 2 * margin) }
        var y: CGFloat = 120 + 11 * CGFloat(vatMentions.count)
        for mention in vatMentions {
            drawText(context: context, text: mention, x: margin, y: y, font: font(size: 8), color: .darkGray)
            y -= 11
        }
        let legalNotes: [(String, String)] = [
            ("Pénalités de retard", invoice.legalNotePMD),
            ("Frais de recouvrement", invoice.legalNotePMT),
            ("Escompte", invoice.legalNoteAAB)
        ]
        for (label, note) in legalNotes {
            let text = note.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            drawText(context: context, text: "\(label) : \(text)",
                     x: margin, y: y, font: font(size: 8), color: .darkGray)
            y -= 11
        }

        let paymentY: CGFloat = 80
        if let iban = invoice.paymentIBAN {
            drawText(context: context, text: "IBAN: \(IBANValidator.formatted(iban))", x: margin, y: paymentY, font: font(size: 9), color: .darkGray)
        }
        if let bic = invoice.paymentBIC {
            drawText(context: context, text: "BIC: \(bic)", x: margin, y: paymentY - 12, font: font(size: 9), color: .darkGray)
        }
        // Conditions de paiement affichées en haut (drawHeader), pas ici, pour rester visibles sans défiler.
        drawText(context: context, text: "Facture électronique Factur-X profil \(invoice.profile.rawValue) — conforme EN 16931",
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

    /// Largeur du texte tel que `drawText` le dessine.
    private func textWidth(_ text: String, font: CTFont) -> CGFloat {
        let attr = NSAttributedString(string: text, attributes: [.font: font])
        let line = CTLineCreateWithAttributedString(attr as CFAttributedString)
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    /// Lignes d'au plus `width` pt, coupées entre les mots : un motif saisi librement ne sort
    /// pas de la page.
    private func wrappedLines(_ text: String, font: CTFont, width: CGFloat) -> [String] {
        let attr = NSAttributedString(string: text, attributes: [.font: font])
        let typesetter = CTTypesetterCreateWithAttributedString(attr as CFAttributedString)
        let string = attr.string as NSString
        var lines: [String] = []
        var start = 0
        while start < string.length {
            let count = CTTypesetterSuggestLineBreak(typesetter, start, Double(width))
            guard count > 0 else { break }
            lines.append(string.substring(with: NSRange(location: start, length: count))
                .trimmingCharacters(in: .whitespacesAndNewlines))
            start += count
        }
        return lines.filter { !$0.isEmpty }
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
