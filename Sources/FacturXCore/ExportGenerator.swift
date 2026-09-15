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
            "Désignation", "Quantité", "Unité", "P.U. HT", "TVA %", "Cat. TVA (BT-151)", "Total HT", "Réf. commande"
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
                    csv(inv.vatCategory(for: line.vatRate)),
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
            "Désignation", "Quantité", "Unité", "P.U. HT", "TVA %", "Cat. TVA (BT-151)", "Total HT"
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
                    csv(order.vatCategory(for: line.vatRate)),
                    String(format: "%.2f", line.lineTotal)
                ])
            }
        }
        return encode(rows: rows)
    }

    /// En-têtes et lignes CSV pour une liste de tiers (annuaire).
    public func directoryCSV(_ entries: [DirectoryEntry]) -> String {
        var rows: [[String]] = []
        rows.append([
            "Raison sociale", "Type", "SIREN", "SIRET", "TVA",
            "Rue", "Code postal", "Ville", "Pays",
            "Contact (nom)", "Contact (email)", "Contact (tél.)",
            "Endpoint ID", "Schéma endpoint", "IBAN", "BIC", "Conditions paiement",
            "Note", "Archivé"
        ])
        for e in entries {
            let p = e.party
            let c = e.defaultContact
            rows.append([
                csv(p.name),
                csv(e.kind.label),
                csv(orBlank(p.siren)),
                csv(orBlank(p.siret)),
                csv(orBlank(p.vatNumber)),
                csv(p.street),
                csv(p.postcode),
                csv(p.city),
                csv(p.country),
                csv(c?.name ?? ""),
                csv(c?.email ?? ""),
                csv(c?.phone ?? ""),
                csv(orBlank(p.endpointID)),
                csv(p.endpointSchemeID),
                csv(orBlank(p.iban)),
                csv(orBlank(p.bic)),
                csv(orBlank(p.paymentTerms)),
                csv(orBlank(e.note)),
                e.isArchived ? "Oui" : "Non"
            ])
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

    // MARK: - Import tiers (CSV)

    public struct PartyImportResult {
        public var entries: [DirectoryEntry]
        public var errors: [String]
        public init(entries: [DirectoryEntry], errors: [String]) {
            self.entries = entries
            self.errors = errors
        }
    }

    /// Parse un CSV de tiers. En-têtes reconnues (insensible à la casse) :
    /// Raison sociale (obligatoire), SIREN (obligatoire), Type, SIRET, TVA,
    /// Rue, Code postal, Ville, Pays, Contact (nom), Contact (email), Contact (tél.),
    /// Endpoint ID, Schéma endpoint, IBAN, BIC, Conditions paiement, Note.
    /// Tous les champs sont optionnels sauf « Raison sociale » et « SIREN ».
    public func parseDirectoryCSV(_ csv: String) -> PartyImportResult {
        let cleaned = csv.hasPrefix("\u{FEFF}") ? String(csv.dropFirst()) : csv
        let lines = cleaned
            .components(separatedBy: "\r\n")
            .flatMap { $0.components(separatedBy: "\n") }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !lines.isEmpty else {
            return PartyImportResult(entries: [], errors: ["Le fichier est vide."])
        }
        let header = parseCSVRow(lines[0]).map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        let nameIdx = header.firstIndex(of: "raison sociale")
            ?? header.firstIndex(of: "nom")
            ?? header.firstIndex(of: "raison sociale (nom)")
        let sirenIdx = header.firstIndex(of: "siren")
        if nameIdx == nil {
            return PartyImportResult(entries: [], errors: ["Colonne « Raison sociale » introuvable."])
        }
        if sirenIdx == nil {
            return PartyImportResult(entries: [], errors: ["Colonne « SIREN » introuvable."])
        }
        func col(_ key: String) -> Int? {
            header.firstIndex(of: key.lowercased())
        }
        let typeIdx = col("type")
        let siretIdx = col("siret")
        let vatIdx = col("tva")
        let streetIdx = col("rue")
        let postcodeIdx = col("code postal")
        let cityIdx = col("ville")
        let countryIdx = col("pays")
        let contactNameIdx = col("contact (nom)")
        let contactEmailIdx = col("contact (email)")
        let contactPhoneIdx = col("contact (tél.)") ?? col("contact (tel)")
        let endpointIdx = col("endpoint id")
        let endpointSchemeIdx = col("schéma endpoint")
        let ibanIdx = col("iban")
        let bicIdx = col("bic")
        let termsIdx = col("conditions paiement")
        let noteIdx = col("note")

        var entries: [DirectoryEntry] = []
        var errors: [String] = []
        for (i, line) in lines.dropFirst().enumerated() {
            let row = parseCSVRow(line)
            func value(_ idx: Int?) -> String? {
                guard let idx = idx, idx < row.count else { return nil }
                let v = row[idx].trimmingCharacters(in: .whitespaces)
                return v.isEmpty ? nil : v
            }
            let name = value(nameIdx) ?? ""
            let siren = value(sirenIdx) ?? ""
            if name.isEmpty {
                errors.append("Ligne \(i + 2) : raison sociale manquante, ignorée.")
                continue
            }
            if siren.isEmpty {
                errors.append("Ligne \(i + 2) : SIREN manquant pour « \(name) », ignoré.")
                continue
            }
            let kindStr = value(typeIdx)?.lowercased() ?? "client"
            let kind: DirectoryEntryKind
            switch kindStr {
            case "societe", "société": kind = .societe
            case "fournisseur": kind = .fournisseur
            case "client / fournisseur", "client/fournisseur", "both", "les deux": kind = .both
            default: kind = .client
            }
            var contacts: [PartyContact] = []
            let cname = value(contactNameIdx)
            let cemail = value(contactEmailIdx)
            let cphone = value(contactPhoneIdx)
            if cname != nil || cemail != nil || cphone != nil {
                contacts.append(PartyContact(
                    name: cname ?? "",
                    email: cemail,
                    phone: cphone,
                    isActive: true,
                    isDefault: true
                ))
            }
            let party = InvoiceParty(
                name: name,
                street: value(streetIdx) ?? "",
                postcode: value(postcodeIdx) ?? "",
                city: value(cityIdx) ?? "",
                country: value(countryIdx) ?? "FR",
                vatNumber: value(vatIdx),
                siren: siren,
                siret: value(siretIdx),
                contactName: cname,
                contactEmail: cemail,
                contactPhone: cphone,
                endpointID: value(endpointIdx),
                endpointSchemeID: value(endpointSchemeIdx) ?? "0225",
                iban: value(ibanIdx),
                bic: value(bicIdx),
                paymentTerms: value(termsIdx)
            )
            let entry = DirectoryEntry(
                kind: kind,
                party: party,
                note: value(noteIdx),
                contacts: contacts
            )
            entries.append(entry)
        }
        return PartyImportResult(entries: entries, errors: errors)
    }

    /// Analyse une ligne CSV en gérant les guillemets et le séparateur « ; ».
    private func parseCSVRow(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var iter = line.makeIterator()
        while let ch = iter.next() {
            if inQuotes {
                if ch == "\"" {
                    let peeked = peekAhead(&iter)
                    if peeked == "\"" {
                        current.append("\"")
                        _ = iter.next()
                    } else {
                        inQuotes = false
                    }
                } else {
                    current.append(ch)
                }
            } else {
                if ch == "\"" {
                    inQuotes = true
                } else if ch == ";" {
                    fields.append(current)
                    current = ""
                } else {
                    current.append(ch)
                }
            }
        }
        fields.append(current)
        return fields
    }

    /// Récupère le prochain caractère sans le consommer.
    private func peekAhead(_ iter: inout String.Iterator) -> Character? {
        var copy = iter
        return copy.next()
    }
}
