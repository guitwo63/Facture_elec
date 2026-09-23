import Foundation

public struct BackupStrategySettings: Codable, Equatable {
    public var retentionCount: Int
    public var autoBackupOnLaunch: Bool
    public var localBackupFolderPath: String?

    public init(retentionCount: Int = 3, autoBackupOnLaunch: Bool = false, localBackupFolderPath: String? = nil) {
        self.retentionCount = retentionCount
        self.autoBackupOnLaunch = autoBackupOnLaunch
        self.localBackupFolderPath = localBackupFolderPath
    }

    private enum CodingKeys: String, CodingKey {
        case retentionCount, autoBackupOnLaunch, localBackupFolderPath
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        retentionCount = try c.decodeIfPresent(Int.self, forKey: .retentionCount) ?? 3
        autoBackupOnLaunch = try c.decodeIfPresent(Bool.self, forKey: .autoBackupOnLaunch) ?? false
        localBackupFolderPath = try c.decodeIfPresent(String.self, forKey: .localBackupFolderPath)
    }
}

public final class BackupStrategyStore: ObservableObject {
    public static let shared = BackupStrategyStore()

    @Published public var settings: BackupStrategySettings

    private let defaults = AppPersistence.defaults
    private let env = AppEnvironment.shared
    private var storageKey: String { env.key("facturx.backupstrategy.v1") }

    public init() {
        if let data = defaults.data(forKey: env.key("facturx.backupstrategy.v1")),
           let decoded = try? JSONDecoder().decode(BackupStrategySettings.self, from: data) {
            settings = decoded
        } else {
            settings = BackupStrategySettings()
        }
    }

    public func load() {
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(BackupStrategySettings.self, from: data) {
            settings = decoded
        } else {
            settings = BackupStrategySettings()
        }
    }

    public func save() {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: storageKey)
        }
    }
}

/// Politique de rétention pure (aucun accès réseau/disque) : à partir d'une
/// liste de noms déjà triés du plus récent au plus ancien (l'horodatage dans
/// le nom de fichier, ex. facture_elec_sauvegarde_2026-09-17_0130.json, rend
/// l'ordre lexical équivalent à l'ordre chronologique), indique lesquels
/// supprimer pour n'en garder que les `keep` plus récents.
public enum BackupRetention {
    public static func namesToDelete(sortedDescendingNames: [String], keep: Int) -> [String] {
        guard keep >= 0 else { return [] }
        return Array(sortedDescendingNames.dropFirst(keep))
    }
}
