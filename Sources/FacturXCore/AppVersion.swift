import Foundation

/// Source unique de la version affichée dans l'app (page de connexion, réglages).
/// À incrémenter en même temps que le tag git (ex. v0.5.0 -> "0.5.0").
public enum AppVersion {
    public static let current = "0.5.0"
    public static let repositoryURL = URL(string: "https://github.com/guitwo63/Facture_elec")!
    public static let copyrightHolder = "Arverneo"
    public static let licenseName = "Apache License 2.0"
}
