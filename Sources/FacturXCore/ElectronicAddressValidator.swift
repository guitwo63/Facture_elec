import Foundation

/// Adresse électronique d'une partie (BT-34 vendeur, BT-49 acheteur) sous le schéma 0225 de
/// l'annuaire français : le SIREN, ou le SIREN suivi de « _ » et d'un SIRET, d'un suffixe ou
/// d'un code de routage (`PartyRoutingAddress.composedAddress`). Et sa longueur, quel que soit
/// son schéma.
public enum ElectronicAddressValidator {
    /// Schéma de l'annuaire (liste EAS), celui que `CIIXMLGenerator` émet par défaut.
    public static let directoryScheme = "0225"

    /// BR-FR-25 (Schematron France CTC, fatale) : une adresse électronique a 125 caractères au
    /// plus, quel que soit son schéma (`string-length(.) le 125`).
    public static let maxLength = 125

    /// Longueur d'une adresse comme la compte `string-length` dans le XML émis : en points de
    /// code, et non en caractères Swift (« e » suivi d'un accent combinant en fait deux) ni en
    /// unités UTF-16 (un émoji n'en fait qu'un). Un retour chariot suivi d'un saut de ligne ne
    /// compte qu'une fois : le lecteur XML les réunit (XML 1.0, § 2.11). Vérifié avec Saxon.
    public static func xmlLength(_ address: String) -> Int {
        let scalars = Array(address.unicodeScalars)
        return scalars.count - zip(scalars, scalars.dropFirst()).filter { $0 == "\r" && $1 == "\n" }.count
    }

    /// BR-FR-23 (Schematron France CTC, fatale) : une adresse de schéma 0225 n'a que des lettres
    /// sans accent, des chiffres et « - », « _ », « . » ; pas d'espace, même autour (le test n'a
    /// pas de `normalize-space`), mais le générateur retire celles d'autour. Le test du Schematron,
    /// `matches($value, '^[A-Za-z0-9+\-_.]+$')`, admet aussi le « + », que ni son propre message
    /// ni l'Annexe A ne citent : refusé ici, comme dans ARVERNX-SaaS.
    public static func isWellFormedDirectoryAddress(_ address: String) -> Bool {
        !address.isEmpty && address.unicodeScalars.allSatisfy { scalar in
            switch scalar {
            case "A"..."Z", "a"..."z", "0"..."9", "-", "_", ".": return true
            default: return false
            }
        }
    }
}

extension InvoiceParty {
    /// BR-FR-23 et BR-FR-25 : l'adresse électronique qu'écrira le XML (`CIIXMLGenerator.xmlEndpoint` :
    /// celle saisie, sinon le SIREN) est admise : 125 caractères au plus, quel que soit son schéma,
    /// et sous le schéma 0225, que des caractères admis. Vrai sans adresse émise. Pilote le liseré
    /// de la partie dans l'éditeur de facture.
    public var hasAdmittedElectronicAddress: Bool {
        guard let endpoint = CIIXMLGenerator.xmlEndpoint(self) else { return true }
        return ElectronicAddressValidator.xmlLength(endpoint.id) <= ElectronicAddressValidator.maxLength
            && (endpoint.schemeID != ElectronicAddressValidator.directoryScheme
                || ElectronicAddressValidator.isWellFormedDirectoryAddress(endpoint.id))
    }
}
