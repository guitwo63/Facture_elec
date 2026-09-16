import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Empêche deux instances de l'application de tourner en même temps sur la même
/// machine, ce qui provoquerait des écritures concurrentes sur les mêmes clés
/// `UserDefaults` (factures, commandes, annuaire, utilisateurs) et un risque de
/// perte de données. Verrou par fichier (`flock`), indépendant du bundle
/// identifier du process (donc fiable que l'app soit lancée via Xcode ou
/// `swift run`) : le verrou est libéré automatiquement par l'OS si le process
/// se termine, y compris en cas de crash.
public final class SingleInstanceLock {
    public static let shared = SingleInstanceLock(url: SingleInstanceLock.defaultLockURL())

    public let url: URL
    private var fileDescriptor: Int32 = -1

    public init(url: URL) {
        self.url = url
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    public static func defaultLockURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("FacturXMacApp", isDirectory: true)
                    .appendingPathComponent("facturx.lock")
    }

    /// Tente d'acquérir un verrou exclusif non bloquant.
    /// - Returns: `true` si le verrou est obtenu (aucune autre instance active),
    ///   `false` si une autre instance le détient déjà.
    @discardableResult
    public func acquire() -> Bool {
        let fd = open(url.path, O_CREAT | O_RDWR, 0o644)
        guard fd != -1 else { return true } // fichier inaccessible : ne bloque pas le lancement
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            return false
        }
        fileDescriptor = fd
        return true
    }

    public func release() {
        guard fileDescriptor != -1 else { return }
        flock(fileDescriptor, LOCK_UN)
        close(fileDescriptor)
        fileDescriptor = -1
    }
}
