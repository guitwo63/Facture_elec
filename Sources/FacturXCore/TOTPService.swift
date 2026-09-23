import Foundation
import CryptoKit

/// TOTP (RFC 6238) sur HMAC-SHA1 (RFC 4226) — aucune dépendance externe,
/// entièrement local comme recommandé dans docs/2fa-analysis.md.
public enum TOTPService {
    private static let base32Alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    public static func generateSecret(byteCount: Int = 20) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        for i in 0..<byteCount { bytes[i] = UInt8.random(in: 0...255) }
        return base32Encode(Data(bytes))
    }

    public static func base32Encode(_ data: Data) -> String {
        guard !data.isEmpty else { return "" }
        var result = ""
        var buffer: UInt64 = 0
        var bitsLeft = 0
        for byte in data {
            buffer = (buffer << 8) | UInt64(byte)
            bitsLeft += 8
            while bitsLeft >= 5 {
                bitsLeft -= 5
                let index = Int((buffer >> UInt64(bitsLeft)) & 0x1F)
                result.append(base32Alphabet[index])
            }
        }
        if bitsLeft > 0 {
            let index = Int((buffer << UInt64(5 - bitsLeft)) & 0x1F)
            result.append(base32Alphabet[index])
        }
        return result
    }

    public static func base32Decode(_ string: String) -> Data? {
        let cleaned = string.uppercased().filter { $0 != "=" }
        guard !cleaned.isEmpty else { return nil }
        var buffer: UInt64 = 0
        var bitsLeft = 0
        var bytes = [UInt8]()
        for char in cleaned {
            guard let index = base32Alphabet.firstIndex(of: char) else { return nil }
            buffer = (buffer << 5) | UInt64(index)
            bitsLeft += 5
            if bitsLeft >= 8 {
                bitsLeft -= 8
                bytes.append(UInt8((buffer >> UInt64(bitsLeft)) & 0xFF))
            }
        }
        return Data(bytes)
    }

    /// Code HOTP pour un compteur donné (RFC 4226), tronqué à `digits` chiffres.
    private static func hotpCode(secretData: Data, counter: UInt64, digits: Int) -> String {
        var counterBytes = [UInt8](repeating: 0, count: 8)
        for i in 0..<8 {
            counterBytes[7 - i] = UInt8((counter >> (8 * UInt64(i))) & 0xFF)
        }
        let key = SymmetricKey(data: secretData)
        let mac = HMAC<Insecure.SHA1>.authenticationCode(for: Data(counterBytes), using: key)
        let digest = Array(mac)
        let offset = Int(digest[digest.count - 1] & 0x0F)
        let truncated = (UInt32(digest[offset] & 0x7F) << 24)
            | (UInt32(digest[offset + 1]) << 16)
            | (UInt32(digest[offset + 2]) << 8)
            | UInt32(digest[offset + 3])
        let modulus = UInt32(pow(10.0, Double(digits)))
        let code = truncated % modulus
        return String(format: "%0\(digits)d", code)
    }

    public static func code(secret: String, date: Date = Date(), step: TimeInterval = 30, digits: Int = 6) -> String? {
        guard let secretData = base32Decode(secret) else { return nil }
        let counter = UInt64(date.timeIntervalSince1970 / step)
        return hotpCode(secretData: secretData, counter: counter, digits: digits)
    }

    /// Vérifie un code en tolérant un décalage de `window` pas de 30s (avant/après),
    /// pour absorber une horloge légèrement désynchronisée sur le téléphone.
    public static func verify(code: String, secret: String, date: Date = Date(), window: Int = 1, step: TimeInterval = 30, digits: Int = 6) -> Bool {
        guard let secretData = base32Decode(secret) else { return false }
        let trimmed = code.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        let counter = Int64(date.timeIntervalSince1970 / step)
        for offset in -window...window {
            let c = UInt64(max(0, counter + Int64(offset)))
            if hotpCode(secretData: secretData, counter: c, digits: digits) == trimmed {
                return true
            }
        }
        return false
    }

    public static func provisioningURI(secret: String, accountName: String, issuer: String = "Facture_elec") -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+")
        let encodedAccount = accountName.addingPercentEncoding(withAllowedCharacters: allowed) ?? accountName
        let encodedIssuer = issuer.addingPercentEncoding(withAllowedCharacters: allowed) ?? issuer
        return "otpauth://totp/\(encodedIssuer):\(encodedAccount)?secret=\(secret)&issuer=\(encodedIssuer)&algorithm=SHA1&digits=6&period=30"
    }
}

/// Paramètre global (niveau solution) : contrôle si la 2FA est disponible dans
/// toute l'application, indépendamment de ce que chaque utilisateur a configuré.
public final class TwoFactorSettings: ObservableObject {
    public static let shared = TwoFactorSettings()

    @Published public var enabledSolutionWide: Bool

    private let defaults = AppPersistence.defaults
    private let env = AppEnvironment.shared
    private var storageKey: String { env.key("facturx.2fa.enabled.v1") }

    public init() {
        self.enabledSolutionWide = false
        load()
    }

    public func load() {
        enabledSolutionWide = defaults.object(forKey: storageKey) as? Bool ?? false
    }

    public func save() {
        defaults.set(enabledSolutionWide, forKey: storageKey)
    }
}

public enum RecoveryCodeGenerator {
    /// 10 codes à usage unique, format lisible "XXXX-XXXX" (Crockford base32, sans caractères ambigus).
    private static let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")

    public static func generate(count: Int = 10) -> [String] {
        (0..<count).map { _ in
            let part1 = (0..<4).map { _ in alphabet.randomElement()! }
            let part2 = (0..<4).map { _ in alphabet.randomElement()! }
            return String(part1) + "-" + String(part2)
        }
    }

    public static func normalize(_ code: String) -> String {
        code.trimmingCharacters(in: .whitespaces).uppercased()
    }
}
