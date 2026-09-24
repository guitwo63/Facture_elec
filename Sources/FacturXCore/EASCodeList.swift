import Foundation

/// Schémas d'adresse électronique (BT-34-1, BT-49-1) admis par le Schematron Factur-X EN16931 :
/// liste 17 de `FACTUR-X_EN16931_codedb.xml`, dans le paquet Python factur-x 6.8
/// (`facturx/xsd_and_schematron/facturx-en16931/`). C'est la liste EAS (Electronic Address
/// Scheme) du CEF (BR-CL-25). Les mêmes 102 codes forment la liste 13 du Schematron EXTENDED ; la
/// liste BR-CL-25 (fatale) d'`EXTENDED-CTC-FR-CII.xslt` y ajoute 0219 et 0220, que le Schematron
/// EN16931 refuse. Le XSD n'en vérifie aucun, et le Schematron France CTC non plus. Même liste
/// qu'ARVERNX-SaaS (`EAS_CODES`, `shared/codelists`). Contrôle local : BR-CL-25 dans
/// `EN16931BusinessRules`.
///
/// Régénérer la liste, depuis le dossier du codedb, puis mettre à jour l'empreinte vérifiée
/// par `EASSchemeRuleTests` :
/// `xmllint --xpath '//cl[@id="17"]/enumeration/@value' FACTUR-X_EN16931_codedb.xml | sed -E 's/.*"(.*)"/\1/' | paste -sd ' ' - | fold -w 80 -s`
public enum EASCodeList {
    public static let codes: Set<String> = Set(list.split(whereSeparator: \.isWhitespace).map(String.init))

    public static func contains(_ code: String) -> Bool {
        codes.contains(code)
    }

    private static let list = """
    0002 0007 0009 0037 0060 0088 0096 0097 0106 0130 0135 0142 0147 0151 0154 0158
    0170 0177 0183 0184 0188 0190 0191 0192 0193 0194 0195 0196 0198 0199 0200 0201
    0202 0203 0204 0205 0208 0209 0210 0211 0212 0213 0215 0216 0217 0218 0221 0225
    0230 0235 0240 0242 0244 0245 0246 0248 9910 9913 9914 9915 9918 9919 9920 9922
    9923 9924 9925 9926 9927 9928 9929 9930 9931 9932 9933 9934 9935 9936 9937 9938
    9939 9940 9941 9942 9943 9944 9945 9946 9947 9948 9949 9950 9951 9952 9953 9957
    9959 AN AQ AS AU EM
    """
}

extension InvoiceParty {
    /// BR-CL-25 : le schéma de l'adresse électronique qu'écrira le XML (`CIIXMLGenerator.xmlEndpoint`)
    /// est dans la liste EAS. Vrai sans adresse émise. Pilote le liseré de la partie dans l'éditeur
    /// de facture.
    public var hasAdmittedEndpointScheme: Bool {
        guard let endpoint = CIIXMLGenerator.xmlEndpoint(self) else { return true }
        return EASCodeList.contains(endpoint.schemeID)
    }
}
