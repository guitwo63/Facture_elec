import Foundation

/// Export groupé des fichiers électroniques, depuis le menu « Exporter » des listes de
/// factures (Factur-X) et de commandes (Order-X).
///
/// Deux temps : l'initialiseur trie les documents, `write(to:)` génère ceux qui restent à
/// exporter et écrit les fichiers dans le dossier choisi.
public struct ElectronicBulkExport {
    /// Un document non exporté, et pourquoi.
    public struct Rejection: Equatable {
        public let number: String
        public let errors: [String]

        public init(number: String, errors: [String]) {
            self.number = number
            self.errors = errors
        }
    }

    /// Un document à générer.
    private struct Pending {
        let number: String
        let fileName: String
        let generate: () throws -> Data
    }

    /// « facture » ou « commande », pour le message de fin.
    private let noun: String
    private var pending: [Pending]
    /// Fichiers écrits, dans l'ordre des documents.
    public private(set) var writtenFiles: [String] = []
    public private(set) var rejections: [Rejection] = []
    /// Documents dont la génération ou l'écriture du fichier a échoué.
    public private(set) var failures: [Rejection] = []
    /// Avoirs internes : jamais de fichier électronique, ils ne vont pas à la PDP.
    public let skippedInternalCreditNotes: Int

    /// Numéros des documents que `write(to:)` générera.
    public var pendingNumbers: [String] { pending.map(\.number) }
    /// Faux quand il n'y a rien à écrire : l'app ne demande alors pas de dossier.
    public var hasPendingDocuments: Bool { !pending.isEmpty }

    public init(invoices: [Invoice],
                generate: @escaping (Invoice) throws -> Data = { try FacturXGenerator().generate(invoice: $0) }) {
        noun = "facture"
        var pending: [Pending] = []
        var skipped = 0
        for invoice in invoices {
            if invoice.type.isInternalCreditNote {
                skipped += 1
                continue
            }
            pending.append(Pending(
                number: invoice.number,
                fileName: invoice.type.isCreditNote ? "avoir-\(invoice.number).pdf" : "facture-\(invoice.number).pdf",
                generate: { try generate(invoice) }))
        }
        self.pending = pending
        skippedInternalCreditNotes = skipped
    }

    public init(orders: [SalesOrder],
                generate: @escaping (SalesOrder) throws -> Data = { try OrderXGenerator().generate(order: $0) }) {
        noun = "commande"
        pending = orders.map { order in
            Pending(number: order.number,
                    fileName: "commande-\(order.number).pdf",
                    generate: { try generate(order) })
        }
        skippedInternalCreditNotes = 0
    }

    /// Génère les documents restant à exporter et écrit leurs fichiers dans `directory`.
    public mutating func write(to directory: URL) {
        for document in pending {
            do {
                let data = try document.generate()
                try data.write(to: directory.appendingPathComponent(document.fileName))
                writtenFiles.append(document.fileName)
            } catch {
                failures.append(Rejection(number: document.number, errors: [error.localizedDescription]))
            }
        }
        pending = []
    }

    /// Compte rendu affiché sous la liste.
    public var message: String {
        let failed = failures.count
        let skipped = skippedInternalCreditNotes
        return "\(writtenFiles.count) fichier(s) généré(s)\(failed > 0 ? ", \(failed) échec(s)" : "")\(skipped > 0 ? ", \(skipped) avoir(s) interne(s) ignoré(s)" : "")"
    }
}
