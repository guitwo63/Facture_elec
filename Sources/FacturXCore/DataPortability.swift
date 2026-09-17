import Foundation

public enum DataPortabilityError: Error, LocalizedError {
    case encodingFailed(String)
    case decodingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .encodingFailed(let m): return "Échec de l'export : \(m)"
        case .decodingFailed(let m): return "Échec de l'import : fichier illisible ou format inattendu (\(m))"
        }
    }
}

/// Export/import « format structuré » (JSON) par module : contrairement au CSV
/// (à plat, pour tableur), ce format est fidèle — il conserve les lignes de
/// facture, statuts, champs optionnels — et permet donc un import fiable, pas
/// seulement une extraction pour lecture externe.
public enum DataPortability {
    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public static func exportJSON<T: Encodable>(_ items: [T]) throws -> Data {
        do {
            return try makeEncoder().encode(items)
        } catch {
            throw DataPortabilityError.encodingFailed(error.localizedDescription)
        }
    }

    public static func importJSON<T: Decodable>(_ type: T.Type, from data: Data) throws -> [T] {
        do {
            return try makeDecoder().decode([T].self, from: data)
        } catch {
            throw DataPortabilityError.decodingFailed(error.localizedDescription)
        }
    }
}

/// Regroupe les réglages de personnalisation (numérotation, statuts
/// personnalisés, tags, couleurs) pour les transférer d'une installation à
/// une autre — délibérément **sans** identifiants ni clés API (SUPER PDP,
/// SMTP…), qui restent propres à chaque poste/environnement.
public struct AppConfigurationBundle: Codable {
    public var invoiceNumberPrefix: String
    public var invoiceNumberIncludeYear: Bool
    public var invoiceNumberStart: Int
    public var invoiceNumberUseSeparator: Bool
    public var orderNumberPrefix: String
    public var orderNumberIncludeYear: Bool
    public var orderNumberStart: Int
    public var orderNumberUseSeparator: Bool
    public var invoiceStatusOverrides: [InvoiceStatusOverride]
    public var orderStatusOverrides: [OrderStatusOverride]
    public var tags: [PartyTag]
    public var kindColors: [String: String]

    public init(
        invoiceNumberPrefix: String = "",
        invoiceNumberIncludeYear: Bool = true,
        invoiceNumberStart: Int = 1,
        invoiceNumberUseSeparator: Bool = true,
        orderNumberPrefix: String = "",
        orderNumberIncludeYear: Bool = true,
        orderNumberStart: Int = 1,
        orderNumberUseSeparator: Bool = true,
        invoiceStatusOverrides: [InvoiceStatusOverride] = [],
        orderStatusOverrides: [OrderStatusOverride] = [],
        tags: [PartyTag] = [],
        kindColors: [String: String] = [:]
    ) {
        self.invoiceNumberPrefix = invoiceNumberPrefix
        self.invoiceNumberIncludeYear = invoiceNumberIncludeYear
        self.invoiceNumberStart = invoiceNumberStart
        self.invoiceNumberUseSeparator = invoiceNumberUseSeparator
        self.orderNumberPrefix = orderNumberPrefix
        self.orderNumberIncludeYear = orderNumberIncludeYear
        self.orderNumberStart = orderNumberStart
        self.orderNumberUseSeparator = orderNumberUseSeparator
        self.invoiceStatusOverrides = invoiceStatusOverrides
        self.orderStatusOverrides = orderStatusOverrides
        self.tags = tags
        self.kindColors = kindColors
    }

    public static func capture(
        invoiceStore: InvoiceStore,
        orderStore: OrderStore,
        invoiceStatusStore: InvoiceStatusStore,
        orderStatusStore: OrderStatusStore,
        tagStore: TagStore,
        kindColorStore: KindColorStore
    ) -> AppConfigurationBundle {
        AppConfigurationBundle(
            invoiceNumberPrefix: invoiceStore.numberPrefix,
            invoiceNumberIncludeYear: invoiceStore.numberIncludeYear,
            invoiceNumberStart: invoiceStore.numberStart,
            invoiceNumberUseSeparator: invoiceStore.numberUseSeparator,
            orderNumberPrefix: orderStore.numberPrefix,
            orderNumberIncludeYear: orderStore.numberIncludeYear,
            orderNumberStart: orderStore.numberStart,
            orderNumberUseSeparator: orderStore.numberUseSeparator,
            invoiceStatusOverrides: invoiceStatusStore.overrides,
            orderStatusOverrides: orderStatusStore.overrides,
            tags: tagStore.tags,
            kindColors: kindColorStore.colors.reduce(into: [String: String]()) { acc, entry in
                acc[entry.key.rawValue] = entry.value
            }
        )
    }

    public func apply(
        invoiceStore: InvoiceStore,
        orderStore: OrderStore,
        invoiceStatusStore: InvoiceStatusStore,
        orderStatusStore: OrderStatusStore,
        tagStore: TagStore,
        kindColorStore: KindColorStore
    ) {
        invoiceStore.numberPrefix = invoiceNumberPrefix
        invoiceStore.numberIncludeYear = invoiceNumberIncludeYear
        invoiceStore.numberStart = invoiceNumberStart
        invoiceStore.numberUseSeparator = invoiceNumberUseSeparator
        invoiceStore.save()

        orderStore.numberPrefix = orderNumberPrefix
        orderStore.numberIncludeYear = orderNumberIncludeYear
        orderStore.numberStart = orderNumberStart
        orderStore.numberUseSeparator = orderNumberUseSeparator
        orderStore.save()

        invoiceStatusStore.overrides = invoiceStatusOverrides
        invoiceStatusStore.save()

        orderStatusStore.overrides = orderStatusOverrides
        orderStatusStore.save()

        tagStore.tags = tags
        tagStore.save()

        for (rawKind, hex) in kindColors {
            if let kind = DirectoryEntryKind(rawValue: rawKind) {
                kindColorStore.colors[kind] = hex
            }
        }
        kindColorStore.save()
    }
}
