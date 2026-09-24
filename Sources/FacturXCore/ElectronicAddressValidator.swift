import Foundation

/// Adresse électronique d'une partie (BT-34 vendeur, BT-49 acheteur) sous le schéma 0225 de
/// l'annuaire français : le SIREN, ou le SIREN suivi de « _ » et d'un SIRET, d'un suffixe ou
/// d'un code de routage (`PartyRoutingAddress.composedAddress`).
public enum ElectronicAddressValidator {
    /// Schéma de l'annuaire (liste EAS), celui que `CIIXMLGenerator` émet par défaut.
    public static let directoryScheme = "0225"

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

    /// BR-FR-21 : une adresse de schéma 0225 désigne ce SIREN, c'est-à-dire qu'elle vaut « SIREN » ou
    /// commence par « SIREN_ » (suivi d'un SIRET, d'un suffixe ou d'un code de routage). C'est la
    /// forme d'ARVERNX-SaaS (`matches_siren`, tirée de l'Annexe A), plus stricte que le Schematron,
    /// qui n'exige que `starts-with($endpointID, $siren)` : un SIRET seul, qui commence par le SIREN,
    /// y passe.
    public static func designatesSiren(_ address: String, siren: String) -> Bool {
        address == siren || address.hasPrefix(siren + "_")
    }
}

extension InvoiceParty {
    /// BR-FR-23 : l'adresse électronique qu'écrira le XML (`CIIXMLGenerator.xmlEndpoint` : celle
    /// saisie, sinon le SIREN) est admise. Vrai sans adresse émise, ou sous un autre schéma que
    /// 0225, que la règle ne vise pas. Pilote le liseré de la partie dans l'éditeur de facture.
    public var hasAdmittedElectronicAddress: Bool {
        guard let endpoint = CIIXMLGenerator.xmlEndpoint(self),
              endpoint.schemeID == ElectronicAddressValidator.directoryScheme else { return true }
        return ElectronicAddressValidator.isWellFormedDirectoryAddress(endpoint.id)
    }
}
