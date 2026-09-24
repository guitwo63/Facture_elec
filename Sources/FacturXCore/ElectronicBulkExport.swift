import Foundation

/// Export groupé des fichiers électroniques, depuis le menu « Exporter » des listes de
/// factures (Factur-X) et de commandes (Order-X) : même contrôle qu'à l'unité. L'éditeur
/// refuse de générer un document tant que la validation locale relève une erreur bloquante,
/// puis contrôle le PDF produit ; l'export groupé générait tout sans rien vérifier, et la PDP
/// aurait rejeté ces fichiers (BR-FR-10, BR-FR-05, BR-FR-16, BR-CL-23, BR-FR-CO-12…).
/// Choix de Guillaume (2026-09-24) : un document en erreur est ignoré, les autres sont
/// exportés, et le message de fin liste les ignorés avec leurs erreurs.
///
/// Deux temps, pour que l'app ne demande un dossier que s'il y a quelque chose à y écrire :
/// l'initialiseur trie les documents par la validation locale, `write(to:)` génère ceux qui
/// l'ont passée, contrôle chaque PDF et écrit les fichiers.
public struct ElectronicBulkExport {
    /// Un document non exporté, et pourquoi.
    public struct Rejection: Equatable {
        public let number: String
        /// Erreurs bloquantes, autant que `FacturXValidationResult.totalErrorCount` en compte :
        /// celles des règles EN 16931 d'abord (leur message commence par l'identifiant de la
        /// règle, « BR-FR-10 : … »), comme l'éditeur les affiche, puis celles du validateur.
        public let errors: [String]

        public init(number: String, errors: [String]) {
            self.number = number
            self.errors = errors
        }
    }

    /// Un document qui a passé la validation locale, à générer.
    private struct Pending {
        let number: String
        let fileName: String
        let generate: () throws -> Data
        /// Contrôle du PDF produit, comme après la génération à l'unité.
        let check: (Data) -> FacturXValidationResult
    }

    /// « facture » ou « commande », pour le message de fin.
    private let noun: String
    private var pending: [Pending]
    /// Fichiers écrits, dans l'ordre des documents.
    public private(set) var writtenFiles: [String] = []
    /// Documents non exportés pour erreur bloquante : à la validation locale, ou au contrôle
    /// du PDF produit.
    public private(set) var rejections: [Rejection]
    /// Documents dont la génération ou l'écriture du fichier a échoué.
    public private(set) var failures: [Rejection] = []
    /// Avoirs internes : jamais de fichier électronique, ils ne vont pas à la PDP.
    public let skippedInternalCreditNotes: Int

    /// Numéros des documents que `write(to:)` générera.
    public var pendingNumbers: [String] { pending.map(\.number) }
    /// Faux quand il n'y a rien à écrire : l'app ne demande alors pas de dossier.
    public var hasPendingDocuments: Bool { !pending.isEmpty }

    /// `generate` n'est à remplacer que dans les tests. Par défaut, le PDF porte le logo de la
    /// société de la facture, comme à l'export à l'unité.
    public init(invoices: [Invoice],
                generate: @escaping (Invoice) throws -> Data = { invoice in
                    try FacturXGenerator().generate(
                        invoice: invoice, logo: PartyDirectory.shared.logoData(forCompanyID: invoice.companyID))
                }) {
        noun = "facture"
        var pending: [Pending] = []
        var rejections: [Rejection] = []
        var skipped = 0
        for invoice in invoices {
            if invoice.type.isInternalCreditNote {
                skipped += 1
                continue
            }
            let validation = FacturXValidator().validate(invoice: invoice)
            guard validation.isValid else {
                rejections.append(Rejection(number: invoice.number, errors: Self.blockingErrors(validation)))
                continue
            }
            pending.append(Pending(
                number: invoice.number,
                fileName: invoice.type.isCreditNote ? "avoir-\(invoice.number).pdf" : "facture-\(invoice.number).pdf",
                generate: { try generate(invoice) },
                check: { FacturXValidator().validate(pdf: $0) }))
        }
        self.pending = pending
        self.rejections = rejections
        skippedInternalCreditNotes = skipped
    }

    /// `generate` n'est à remplacer que dans les tests.
    public init(orders: [SalesOrder],
                generate: @escaping (SalesOrder) throws -> Data = { try OrderXGenerator().generate(order: $0) }) {
        noun = "commande"
        var pending: [Pending] = []
        var rejections: [Rejection] = []
        for order in orders {
            let validation = OrderXValidator().validate(order: order)
            guard validation.isValid else {
                rejections.append(Rejection(number: order.number, errors: Self.blockingErrors(validation)))
                continue
            }
            pending.append(Pending(
                number: order.number,
                fileName: "commande-\(order.number).pdf",
                generate: { try generate(order) },
                check: { OrderXValidator().validate(pdf: $0) }))
        }
        self.pending = pending
        self.rejections = rejections
        skippedInternalCreditNotes = 0
    }

    /// Génère les documents restant à exporter et écrit dans `directory` ceux dont le PDF
    /// passe son contrôle.
    public mutating func write(to directory: URL) {
        for document in pending {
            do {
                let data = try document.generate()
                let check = document.check(data)
                guard check.isValid else {
                    rejections.append(Rejection(number: document.number, errors: Self.blockingErrors(check)))
                    continue
                }
                try data.write(to: directory.appendingPathComponent(document.fileName))
                writtenFiles.append(document.fileName)
            } catch {
                failures.append(Rejection(number: document.number, errors: [error.localizedDescription]))
            }
        }
        pending = []
    }

    /// Compte rendu affiché sous la liste : fichiers écrits, puis un document non exporté
    /// par ligne, avec sa première erreur.
    public var message: String {
        var summary = "\(writtenFiles.count) fichier(s) généré(s)"
        if skippedInternalCreditNotes > 0 {
            summary += ", \(skippedInternalCreditNotes) avoir(s) interne(s) ignoré(s)"
        }
        var lines = [summary + "."]
        if !rejections.isEmpty {
            lines.append("\(rejections.count) \(noun)(s) non exportée(s), erreurs bloquantes à corriger :")
            lines += rejections.map(Self.line)
        }
        if !failures.isEmpty {
            lines.append("\(failures.count) \(noun)(s) non exportée(s), échec de la génération ou de l'écriture :")
            lines += failures.map(Self.line)
        }
        return lines.joined(separator: "\n")
    }

    private static func line(_ rejection: Rejection) -> String {
        let number = rejection.number.trimmingCharacters(in: .whitespaces)
        let errors = rejection.errors
        let detail = errors.count > 1 ? "\(errors.count) erreurs, dont \(errors[0])" : errors.first ?? ""
        return "• \(number.isEmpty ? "(sans numéro)" : number) — \(detail)"
    }

    private static func blockingErrors(_ validation: FacturXValidationResult) -> [String] {
        validation.businessRules.filter { $0.severity == .error }.map(\.message) + validation.errors
    }
}
