import Foundation

/// Générateur d'export de listes de factures et commandes au format CSV
/// (compatible Excel : BOM UTF-8, séparateur « ; »).
/// Sans dépendance externe : produit un .csv ouvert directement par Excel/Numbers.
public struct ExportGenerator {
    public init() {}

    private let df: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd/MM/yyyy"
        return f
    }()

    private func csv(_ s: String) -> String {
        let needsQuote = s.contains(";") || s.contains("\"") || s.contains("\n") || s.contains("\r")
        if needsQuote {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }

    private func orBlank(_ s: String?) -> String {
        (s ?? "").trimmingCharacters(in: .whitespaces)
    }

    /// En-têtes et lignes CSV pour une liste de factures.
    public func invoiceCSV(_ invoices: [Invoice]) -> String {
        var rows: [[String]] = []
        rows.append([
            "Numéro", "Type", "Statut", "Date", "Échéance", "Devise",
            "Émetteur (nom)", "Émetteur (SIREN)", "Émetteur (TVA)",
            "Destinataire (nom)", "Destinataire (SIREN)", "Destinataire (TVA)",
            "Réf. commande", "Réf. contrat", "Réf. facture antérieure",
            "Total HT", "Total TVA", "Total TTC", "Mode facturation", "Notes",
            "IBAN", "BIC", "Conditions de paiement"
        ])
        for inv in invoices {
            rows.append([
                csv(inv.number),
                csv(inv.type.label),
                csv(inv.status.label),
                csv(df.string(from: inv.issueDate)),
                csv(df.string(from: inv.dueDate)),
                csv(inv.currency),
                csv(inv.seller.name),
                csv(orBlank(inv.seller.siren)),
                csv(orBlank(inv.seller.vatNumber)),
                csv(inv.buyer.name),
                csv(orBlank(inv.buyer.siren)),
                csv(orBlank(inv.buyer.vatNumber)),
                csv(orBlank(inv.purchaseOrderRef)),
                csv(orBlank(inv.contractRef)),
                csv(orBlank(inv.precedingInvoiceRef)),
                String(format: "%.2f", inv.lineTotal),
                String(format: "%.2f", inv.taxTotal),
                String(format: "%.2f", inv.grandTotal),
                csv(inv.billingMode.rawValue),
                csv(orBlank(inv.notes)),
                csv(orBlank(inv.paymentIBAN)),
                csv(orBlank(inv.paymentBIC)),
                csv(orBlank(inv.paymentTerms))
            ])
        }
        return encode(rows: rows)
    }

    /// En-têtes et lignes CSV pour une liste de commandes.
    public func orderCSV(_ orders: [SalesOrder]) -> String {
        var rows: [[String]] = []
        rows.append([
            "Numéro", "Type", "Statut", "Date", "Livraison souhaitée", "Devise",
            "Acheteur (nom)", "Acheteur (SIREN)", "Acheteur (TVA)",
            "Client (nom)", "Client (SIREN)", "Client (TVA)",
            "Réf. devis", "Réf. contrat", "Réf. commande cadre",
            "Réf. acheteur", "Total HT", "Total TVA", "Total TTC", "Notes"
        ])
        for order in orders {
            rows.append([
                csv(order.number),
                csv(order.type.label),
                csv(order.status.label),
                csv(df.string(from: order.issueDate)),
                csv(df.string(from: order.requestedDeliveryDate)),
                csv(order.currency),
                csv(order.buyer.name),
                csv(orBlank(order.buyer.siren)),
                csv(orBlank(order.buyer.vatNumber)),
                csv(order.seller.name),
                csv(orBlank(order.seller.siren)),
                csv(orBlank(order.seller.vatNumber)),
                csv(orBlank(order.quotationRef)),
                csv(orBlank(order.contractRef)),
                csv(orBlank(order.blanketOrderRef)),
                csv(orBlank(order.buyerReference)),
                String(format: "%.2f", order.lineTotal),
                String(format: "%.2f", order.taxTotal),
                String(format: "%.2f", order.grandTotal),
                csv(orBlank(order.notes))
            ])
        }
        return encode(rows: rows)
    }

    /// En-têtes et lignes CSV détaillant toutes les lignes de factures.
    public func invoiceLinesCSV(_ invoices: [Invoice]) -> String {
        var rows: [[String]] = []
        rows.append([
            "N° facture", "Type", "Date", "Destinataire",
            "Désignation", "Quantité", "Unité", "P.U. HT", "TVA %", "Total HT", "Réf. commande"
        ])
        for inv in invoices {
            for line in inv.lines {
                rows.append([
                    csv(inv.number),
                    csv(inv.type.label),
                    csv(df.string(from: inv.issueDate)),
                    csv(inv.buyer.name),
                    csv(line.name),
                    String(format: "%g", line.quantity),
                    csv(line.unit),
                    String(format: "%.2f", line.unitPrice),
                    String(format: "%g", line.vatRate),
                    String(format: "%.2f", line.lineTotal),
                    csv(orBlank(line.orderReference))
                ])
            }
        }
        return encode(rows: rows)
    }

    /// En-têtes et lignes CSV détaillant toutes les lignes de commandes.
    public func orderLinesCSV(_ orders: [SalesOrder]) -> String {
        var rows: [[String]] = []
        rows.append([
            "N° commande", "Type", "Date", "Client",
            "Désignation", "Quantité", "Unité", "P.U. HT", "TVA %", "Total HT"
        ])
        for order in orders {
            for line in order.lines {
                rows.append([
                    csv(order.number),
                    csv(order.type.label),
                    csv(df.string(from: order.issueDate)),
                    csv(order.seller.name),
                    csv(line.name),
                    String(format: "%g", line.quantity),
                    csv(line.unit),
                    String(format: "%.2f", line.unitPrice),
                    String(format: "%g", line.vatRate),
                    String(format: "%.2f", line.lineTotal)
                ])
            }
        }
        return encode(rows: rows)
    }

    private func encode(rows: [[String]]) -> String {
        let body = rows.map { $0.joined(separator: ";") }.joined(separator: "\r\n")
        return body
    }

    /// Écrit le CSV (avec BOM UTF-8) à l'URL donnée.
    public func writeCSV(_ csv: String, to url: URL) throws {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(contentsOf: csv.utf8)
        try data.write(to: url)
    }
}
