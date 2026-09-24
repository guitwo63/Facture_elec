import Foundation

// MARK: - Pannes des synchronisations SUPER PDP

/// Synchronisation périodique dont les échecs passent par `SyncFailureJournal`.
public enum SyncKind: String {
    /// Statuts des factures de vente déposées sur SUPER PDP (`PDPPeriodicSyncEngine`).
    case salesStatus
    /// Réception des factures d'achat (`PurchasePDPReceptionEngine`).
    case purchaseReception
}

/// Document interrogé pendant un cycle : une facture de vente (`id` = son UUID, `code` = son
/// numéro) ou une facture reçue à importer (`id` = `code` = son identifiant distant).
public struct SyncTarget: Hashable {
    public var id: String
    public var code: String

    public init(id: String, code: String) {
        self.id = id
        self.code = code
    }
}

/// Nature d'un échec. `accountWide` : l'échec touche tout le compte SUPER PDP (réseau coupé,
/// serveur indisponible, identifiants refusés) et ne dit rien du document interrogé. Sinon il
/// est propre à ce document (facture inconnue de SUPER PDP, fichier illisible…).
public struct SyncFailureCause: Equatable {
    public var category: String
    public var accountWide: Bool

    public init(category: String, accountWide: Bool) {
        self.category = category
        self.accountWide = accountWide
    }

    public init(_ error: Error) {
        if error is URLError {
            self.init(category: "réseau", accountWide: true)
            return
        }
        guard let pdpError = error as? SuperPDPError else {
            self.init(category: "autre", accountWide: false)
            return
        }
        switch pdpError {
        case .http(let status, _) where status >= 500:
            self.init(category: "HTTP 5xx", accountWide: true)
        case .http(let status, _) where [401, 403, 407, 429].contains(status):
            self.init(category: "HTTP \(status)", accountWide: true)
        case .http(let status, _):
            self.init(category: "HTTP \(status)", accountWide: false)
        case .notConfigured, .noToken:
            self.init(category: "identifiants", accountWide: true)
        case .decoding:
            self.init(category: "réponse illisible", accountWide: false)
        default:
            self.init(category: "autre", accountWide: false)
        }
    }

    /// Arrêt du moteur en pleine requête (bascule d'environnement, fermeture) : la requête n'a
    /// ni échoué ni réussi.
    public static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }
}

/// Panne en cours, gardée d'un lancement de l'app à l'autre.
public struct SyncIncident: Codable, Equatable {
    /// Premier échec.
    public var since: Date
    /// Cycles en échec depuis `since`, le premier compris.
    public var failureCount: Int
    public var category: String
    public var lastMessage: String

    public init(since: Date, failureCount: Int, category: String, lastMessage: String) {
        self.since = since
        self.failureCount = failureCount
        self.category = category
        self.lastMessage = lastMessage
    }
}

/// Bilan d'un cycle d'une synchronisation pour un compte SUPER PDP. `companyID` : la société dont
/// les identifiants servent, `nil` pour le compte par défaut. `SyncFailureJournal.close(_:audit:)`
/// en tire les entrées du journal d'audit.
public struct SyncCycle {
    struct Failure {
        var cause: SyncFailureCause
        var message: String
    }

    public let kind: SyncKind
    public let companyID: UUID?
    /// Documents encore suivis. La panne propre à un document absent de cette liste est oubliée
    /// sans rien écrire (facture payée entre-temps, facture reçue importée ou disparue). `nil` :
    /// liste inconnue (la liste des factures reçues a échoué), rien n'est oublié.
    public var followedTargets: [SyncTarget]?

    private(set) var accountFailure: Failure?
    private(set) var accountFailureTargets: [SyncTarget] = []
    private(set) var targetFailures: [SyncTarget: Failure] = [:]
    private(set) var succeededTargets: Set<SyncTarget> = []
    /// SUPER PDP a répondu au moins une fois (succès ou refus propre à un document) : le compte
    /// est joignable.
    private(set) var reachedServer = false

    public init(kind: SyncKind, companyID: UUID?, followedTargets: [SyncTarget]? = nil) {
        self.kind = kind
        self.companyID = companyID
        self.followedTargets = followedTargets
    }

    /// Requête réussie. `target` : le document interrogé, `nil` pour une requête de compte (la
    /// liste des factures reçues).
    public mutating func recordSuccess(_ target: SyncTarget? = nil) {
        reachedServer = true
        if let target { succeededTargets.insert(target) }
    }

    /// Requête échouée. Une annulation est ignorée. Sans `target` (requête de compte), l'échec est
    /// toujours celui du compte.
    public mutating func recordFailure(_ error: Error, target: SyncTarget? = nil) {
        guard !SyncFailureCause.isCancellation(error) else { return }
        let failure = Failure(cause: SyncFailureCause(error), message: error.localizedDescription)
        if let target, !failure.cause.accountWide {
            reachedServer = true
            if targetFailures[target] == nil { targetFailures[target] = failure }
        } else {
            if accountFailure == nil { accountFailure = failure }
            if let target { accountFailureTargets.append(target) }
        }
    }
}

/// Tient le journal d'audit à l'écart des erreurs répétées des synchronisations périodiques
/// SUPER PDP. Elles tournent toutes les 15 minutes tant que l'app est ouverte, nuit comprise si le
/// Mac reste allumé. Chaque échec écrivait une entrée (une par facture suivie pour les statuts) :
/// en production, les 500 entrées du journal (`AuditStore.maxEntries`) ne couvraient plus que
/// 4 jours, dont 449 erreurs de synchronisation.
///
/// Une panne n'écrit plus que deux entrées : au premier échec, puis au retour à la normale, avec
/// le nombre d'échecs et le début de la panne. Entre les deux, rien, sauf si la nature de l'échec
/// change (réseau puis HTTP 401, par exemple). Une panne de tout le compte (`SyncFailureCause
/// .accountWide`) compte pour une, quel que soit le nombre de factures suivies ; une erreur propre
/// à un document compte pour une par document. Les pannes en cours sont gardées dans UserDefaults,
/// sous une clé propre à l'environnement : un redémarrage de l'app ne les journalise pas de nouveau.
public final class SyncFailureJournal {
    public static let shared = SyncFailureJournal()

    private let defaults = AppPersistence.defaults
    private let env = AppEnvironment.shared
    private var storageKey: String { env.key("facturx.syncincidents.v1") }
    /// Horloge, remplaçable dans les tests.
    var now: () -> Date = { Date() }

    public init() {}

    /// Pannes en cours, par clé `<synchro>|<compte>` ou `<synchro>|<compte>|<document>`. Relues à
    /// chaque accès, pour suivre une bascule d'environnement.
    public var incidents: [String: SyncIncident] {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: SyncIncident].self, from: data) else { return [:] }
        return decoded
    }

    private func save(_ incidents: [String: SyncIncident]) {
        if incidents.isEmpty {
            defaults.removeObject(forKey: storageKey)
        } else if let data = try? JSONEncoder().encode(incidents) {
            defaults.set(data, forKey: storageKey)
        }
    }

    static func accountKey(_ kind: SyncKind, _ companyID: UUID?) -> String {
        "\(kind.rawValue)|\(companyID?.uuidString ?? "defaut")"
    }

    /// Écrit dans `audit` ce que le cycle apprend (début, changement de nature ou fin d'une
    /// panne), puis met à jour les pannes en cours.
    public func close(_ cycle: SyncCycle, audit: AuditStore?) {
        let before = incidents
        var incidents = before
        let accountKey = Self.accountKey(cycle.kind, cycle.companyID)
        let texts = SyncFailureTexts(kind: cycle.kind)

        func record(_ action: String, _ details: String, target: SyncTarget?) {
            audit?.record(actor: "system", action: action, target: target?.code ?? "", details: details,
                          objectType: texts.objectType, objectCode: target?.code, companyID: cycle.companyID)
        }

        /// Échec d'une clé : une entrée s'il ouvre une panne ou en change la nature.
        func fail(_ key: String, _ failure: SyncCycle.Failure, target: SyncTarget?, affected: [SyncTarget]) {
            if var incident = incidents[key] {
                incident.failureCount += 1
                if incident.category != failure.cause.category {
                    incident.category = failure.cause.category
                    record(texts.failureAction(target: target), texts.causeChanged(failure.message, target: target, affected: affected), target: target)
                }
                incident.lastMessage = failure.message
                incidents[key] = incident
            } else {
                incidents[key] = SyncIncident(since: now(), failureCount: 1,
                                              category: failure.cause.category, lastMessage: failure.message)
                record(texts.failureAction(target: target), texts.firstFailure(failure.message, target: target, affected: affected), target: target)
            }
        }

        // Compte : la panne ne se referme que sur un cycle sans échec de compte où SUPER PDP a répondu.
        if let failure = cycle.accountFailure {
            fail(accountKey, failure, target: nil, affected: cycle.accountFailureTargets)
        } else if cycle.reachedServer, let incident = incidents.removeValue(forKey: accountKey) {
            record(texts.recoveryAction, texts.recovery(incident), target: nil)
        }

        // Documents, dans l'ordre de leur code pour un journal stable.
        for (target, failure) in cycle.targetFailures.sorted(by: { $0.key.code < $1.key.code }) {
            fail(accountKey + "|" + target.id, failure, target: target, affected: [])
        }
        for target in cycle.succeededTargets.sorted(by: { $0.code < $1.code }) {
            guard let incident = incidents.removeValue(forKey: accountKey + "|" + target.id) else { continue }
            if texts.journalsTargetRecovery {
                record(texts.recoveryAction, texts.recovery(incident), target: target)
            }
        }
        if let followed = cycle.followedTargets {
            let followedKeys = Set(followed.map { accountKey + "|" + $0.id })
            for key in incidents.keys where key.hasPrefix(accountKey + "|") && !followedKeys.contains(key) {
                incidents.removeValue(forKey: key)
            }
        }

        if incidents != before { save(incidents) }
    }

    /// Oublie sans rien écrire les pannes des comptes qu'un passage n'a pas interrogés : PDP
    /// désactivé, identifiants retirés, plus aucune facture à suivre. Sans quoi un compte
    /// réactivé des semaines plus tard annoncerait une panne « depuis » ce temps-là.
    public func forgetAccounts(of kind: SyncKind, except companyIDs: Set<UUID?>) {
        let before = incidents
        let kept = Set(companyIDs.map { Self.accountKey(kind, $0) })
        let stale = before.keys.filter { key in
            guard key.hasPrefix(kind.rawValue + "|") else { return false }
            let account = key.split(separator: "|", maxSplits: 2).prefix(2).joined(separator: "|")
            return !kept.contains(account)
        }
        guard !stale.isEmpty else { return }
        var incidents = before
        stale.forEach { incidents.removeValue(forKey: $0) }
        save(incidents)
    }

    /// Message d'erreur raccourci pour un résumé à l'écran (le corps d'une réponse HTTP peut
    /// faire des kilo-octets).
    public static func brief(_ message: String, limit: Int = 200) -> String {
        message.count > limit ? String(message.prefix(limit)) + "…" : message
    }
}

/// Actions et textes du journal d'audit, par synchronisation.
private struct SyncFailureTexts {
    let kind: SyncKind

    var objectType: AuditObjectType { kind == .salesStatus ? .invoice : .purchaseInvoice }

    var recoveryAction: String { kind == .salesStatus ? "pdp_status_recovered" : "purchase_invoice_list_recovered" }

    /// Pour une facture reçue, son import (« purchase_invoice_received ») tient lieu de retour à
    /// la normale.
    var journalsTargetRecovery: Bool { kind == .salesStatus }

    func failureAction(target: SyncTarget?) -> String {
        switch kind {
        case .salesStatus: return "pdp_status_error"
        case .purchaseReception: return target == nil ? "purchase_invoice_list_error" : "purchase_invoice_receive_error"
        }
    }

    func firstFailure(_ message: String, target: SyncTarget?, affected: [SyncTarget]) -> String {
        let message = Self.withoutFinalPeriod(message)
        switch (kind, target) {
        case (.salesStatus, _):
            return "Synchronisation périodique échouée : \(message)\(Self.invoices(affected)). Échecs suivants non répétés jusqu'au retour à la normale."
        case (.purchaseReception, nil):
            return "Échec de la réception des factures d'achat sur SUPER PDP : \(message). Échecs suivants non répétés jusqu'au retour à la normale."
        case (.purchaseReception, let target?):
            return "Échec import facture d'achat (id distant \(target.code)) : \(message). Échecs suivants non répétés jusqu'à son import."
        }
    }

    func causeChanged(_ message: String, target: SyncTarget?, affected: [SyncTarget]) -> String {
        let message = Self.withoutFinalPeriod(message)
        switch (kind, target) {
        case (.salesStatus, _):
            return "Synchronisation périodique toujours en échec, autre cause : \(message)\(Self.invoices(affected))."
        case (.purchaseReception, nil):
            return "Réception des factures d'achat toujours en échec, autre cause : \(message)."
        case (.purchaseReception, let target?):
            return "Import de la facture d'achat (id distant \(target.code)) toujours en échec, autre cause : \(message)."
        }
    }

    /// « La connexion Internet semble être désactivée. » : le point final est celui de la phrase.
    private static func withoutFinalPeriod(_ message: String) -> String {
        var trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix(".") { trimmed.removeLast() }
        return trimmed
    }

    func recovery(_ incident: SyncIncident) -> String {
        let subject = kind == .salesStatus ? "Synchronisation périodique" : "Réception des factures d'achat"
        let failures = incident.failureCount == 1 ? "1 échec" : "\(incident.failureCount) échecs"
        return "\(subject) rétablie après \(failures), en échec depuis le \(Self.format(incident.since))."
    }

    /// « 23/09/2026 à 23:10 », dans le fuseau de l'application (`NSTimeZone.default`, relu à
    /// chaque appel), comme la colonne Date du journal.
    static func format(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.timeZone = NSTimeZone.default
        formatter.dateFormat = "dd/MM/yyyy 'à' HH:mm"
        return formatter.string(from: date)
    }

    /// « (factures FA-1, FA-2) », cinq numéros au plus.
    private static func invoices(_ targets: [SyncTarget]) -> String {
        guard !targets.isEmpty else { return "" }
        let codes = targets.map(\.code)
        let shown = codes.prefix(5).joined(separator: ", ")
        return " (factures \(shown)\(codes.count > 5 ? "…" : ""))"
    }
}
