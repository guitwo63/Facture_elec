import Foundation

public enum CIIXMLParserError: Error, Equatable {
    case invalidXML
    case missingRequiredField(String)
}

/// Lit un XML CII (Cross-Industry Invoice) tel que produit par `CIIXMLGenerator` — ou reçu
/// d'un tiers (facture d'achat déposée par un fournisseur sur SUPER PDP) — et reconstruit un
/// `Invoice`. Contrepartie lecture de `CIIXMLGenerator`, qui sert de référence exacte pour
/// les balises parcourues ici ; aucun des deux fichiers n'a besoin de connaître l'autre.
///
/// Conçu pour ce besoin précis (lire une facture CII EN16931/FR), pas comme un outil XML
/// générique : un automate à un seul « conteneur courant » (pas de pile générique), les
/// balises étant toutes des sœurs directes de leur conteneur — jamais imbriquées entre
/// elles — dans la structure que `CIIXMLGenerator` produit.
public struct CIIXMLParser {
    public init() {}

    public func parse(xml: Data) throws -> Invoice {
        try parseWithWarnings(xml: xml).invoice
    }

    /// Variante exposant aussi les avertissements de cohérence (ex. écart entre le total
    /// déclaré par le document et le total recalculé depuis ses lignes) — un avertissement
    /// doux, jamais bloquant (rejeter une vraie facture fournisseur pour un simple écart
    /// d'arrondi serait pire que de le signaler), mais qu'un appelant (réception SUPER PDP,
    /// import manuel) peut vouloir afficher plutôt que d'ignorer silencieusement.
    public func parseWithWarnings(xml: Data) throws -> (invoice: Invoice, warnings: [String]) {
        let delegate = Delegate()
        let parser = XMLParser(data: xml)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        guard parser.parse() else {
            throw CIIXMLParserError.invalidXML
        }
        let invoice = try delegate.buildInvoice()
        return (invoice, delegate.warnings)
    }

    /// Point d'entrée unique pour un fichier tel que déposé sur SUPER PDP : détecte via les
    /// octets magiques s'il s'agit d'un XML CII brut ou d'un PDF Factur-X (auquel cas le XML
    /// embarqué est d'abord extrait via `FacturXEmbedder.extractXML(fromPDF:)`). Le format
    /// exact renvoyé par `SuperPDPService.downloadInvoice` n'est pas documenté avec
    /// certitude — ce sniff couvre les deux cas par précaution plutôt que de supposer l'un
    /// des deux.
    public static func parseDepositedFile(_ data: Data) throws -> Invoice {
        if data.starts(with: [0x25, 0x50, 0x44, 0x46]) { // "%PDF"
            let xml = try FacturXEmbedder().extractXML(fromPDF: data)
            return try CIIXMLParser().parse(xml: xml)
        }
        return try CIIXMLParser().parse(xml: data)
    }
}

/// Accumulateur pour un tiers (émetteur ou destinataire) en cours de lecture.
private struct PartyBuilder {
    var name = ""
    var street = ""
    var postcode = ""
    var city = ""
    var country = "FR"
    var vatNumber: String?
    var siren: String?
    var legalSchemeID = "0002"
    var contactName: String?
    var contactEmail: String?
    var contactPhone: String?
    var endpointID: String?
    var endpointSchemeID = "0225"

    func build() -> InvoiceParty {
        InvoiceParty(
            name: name, street: street, postcode: postcode, city: city, country: country,
            vatNumber: vatNumber, siren: siren, legalSchemeID: legalSchemeID,
            contactName: contactName, contactEmail: contactEmail, contactPhone: contactPhone,
            endpointID: endpointID, endpointSchemeID: endpointSchemeID
        )
    }
}

/// Accumulateur pour une ligne en cours de lecture.
private struct LineBuilder {
    var name = ""
    var description: String?
    var quantity: Double = 1
    var unit = "C62"
    var unitPrice: Double = 0
    /// `nil` tant que `ram:RateApplicablePercent` n'est pas lu : une ligne O n'en porte pas
    /// (BR-O-05). Voir `build()`.
    var vatRate: Double?
    var vatCategory: VATCategory = .standard
    var globalID: String?
    var sellerAssignedID: String?
    var buyerAssignedID: String?
    var orderLineID: String?
    // Hors profil EN16931 (émis par d'anciennes versions de l'app, ou par un fournisseur en
    // profil EXTENDED) : conservés, sous leur balise, comme champs non émis.
    var orderRef: String?
    var contractRef: String?

    func build() -> InvoiceLine {
        var fields: [OptionalField] = []
        if let g = globalID, !g.isEmpty {
            fields.append(OptionalField(tagName: "ram:GlobalID", value: g))
        }
        if let s = sellerAssignedID, !s.isEmpty {
            fields.append(OptionalField(tagName: "ram:SellerAssignedID", value: s))
        }
        if let b = buyerAssignedID, !b.isEmpty {
            fields.append(OptionalField(tagName: "ram:BuyerAssignedID", value: b))
        }
        if let l = orderLineID, !l.isEmpty {
            fields.append(OptionalField(tagName: "ram:BuyerOrderReferencedDocument/ram:LineID", value: l))
        }
        if let o = orderRef, !o.isEmpty {
            fields.append(OptionalField(tagName: "ram:BuyerOrderReferencedDocument/ram:IssuerAssignedID", value: o))
        }
        if let c = contractRef, !c.isEmpty {
            fields.append(OptionalField(tagName: "ram:ContractReferencedDocument/ram:IssuerAssignedID", value: c))
        }
        // Sans taux, toute catégorie autre que S vaut 0 % (le modèle n'en admet pas d'autre) :
        // les 20 % par défaut d'avant faisaient d'une ligne O une ligne à 20 % de TVA.
        return InvoiceLine(
            name: name, description: description, quantity: quantity, unit: unit,
            unitPrice: unitPrice, vatRate: vatRate ?? (vatCategory == .standard ? 20 : 0), vatCategory: vatCategory,
            optionalFields: fields
        )
    }
}

/// Élément déclaré de la ventilation TVA d'en-tête (`ram:ApplicableTradeTax` sous
/// `ApplicableHeaderTradeSettlement`, BG-23). Les montants ne sont jamais copiés sur le
/// modèle (les totaux d'`Invoice` sont calculés depuis les lignes, pas stockés) — gardés
/// uniquement pour la vérification déclaré-vs-recalculé faite juste après le parse, tant
/// qu'ils existent encore. `exemptionReason`, en revanche, EST reporté sur les lignes
/// correspondantes (par couple taux/catégorie) : BT-120 est normativement porté par cette
/// ventilation d'en-tête, pas par la ligne — `CIIXMLGenerator` ne l'écrit d'ailleurs qu'ici,
/// jamais au niveau de la ligne (voir `xmlSettlement`/`vatBreakdown`, vs `xmlLine` qui ne
/// l'émet pas) : c'est la seule façon de le récupérer, pas une limite du parseur.
private struct DeclaredTax {
    var basis: Double = 0
    var amount: Double = 0
    var rate: Double = 0
    var category: String = ""
    var exemptionReason: String?
}

private final class Delegate: NSObject, XMLParserDelegate {
    private enum Container {
        case none
        case businessProcessParam, guidelineParam
        case exchangedDocument, includedNote
        case lineItem, lineProduct, lineAgreement, lineDelivery, lineSettlementTax
        case sellerParty, buyerParty, partyContact, partyAddress, partyLegalOrg, partyTaxReg, partyEndpoint
        case agreement, delivery, settlement
        case settlementTax, paymentMeans, paymentTerms, monetarySummation, invoiceReferenced
        case shipToParty, shipToAddress
    }

    private enum PartyContext { case none, seller, buyer }
    private enum AgreementRef { case none, purchaseOrder, contract, tender, additional, project }
    private enum DeliveryRef { case none, receivingAdvice, despatchAdvice }
    private enum LineRef { case none, order, contract }

    private var container: Container = .none
    private var partyContext: PartyContext = .none
    private var pendingAgreementRef: AgreementRef = .none
    private var pendingDeliveryRef: DeliveryRef = .none
    private var pendingLineRef: LineRef = .none
    private var text = ""

    // En-tête / contexte
    private var billingModeRaw = ""
    private var profileURN = ""
    private var number = ""
    private var typeCodeRaw = ""
    private var issueDateRaw = ""
    private var dueDateRaw = ""
    private var notes: [(content: String, subjectCode: String?)] = []
    private var currentNoteContent = ""
    private var currentNoteSubjectCode: String?

    private var seller = PartyBuilder()
    private var buyer = PartyBuilder()
    private var currentLegalSchemeID = "0002"
    private var currentEndpointSchemeID = "0225"
    private var lines: [InvoiceLine] = []
    private var currentLine = LineBuilder()

    private var buyerReference: String?
    private var purchaseOrderRef: String?
    private var contractRef: String?
    private var tenderRef: String?
    // AdditionalReferencedDocument : son code type (50 = appel d'offres ou lot, BT-17) suit
    // l'identifiant dans le XML — l'identifiant est donc gardé jusqu'à la fermeture du bloc.
    private var additionalRefID: String?
    private var additionalRefTypeCode: String?
    private var procuringProjectID: String?
    private var receivingAdviceRef: String?
    private var despatchAdviceRef: String?
    private var deliveryCountry: String?
    /// Conteneur (livraison d'en-tête ou de ligne) d'où l'on est entré dans un `ShipToTradeParty`.
    private var shipToParent: Container = .none

    private var currency = "EUR"
    private var paymentIBAN: String?
    private var paymentBIC: String?
    private var paymentTermsDescription: String?

    private var declaredTaxes: [DeclaredTax] = []
    private var currentTax = DeclaredTax()

    private var declaredLineTotal: Double?
    private var declaredGrandTotal: Double?
    private var prepaidAmount: Double = 0

    private var precedingInvoiceRef: String?
    private var precedingInvoiceDateRaw: String?

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        text = ""
        // Livré à (BG-13) : sous-arbre à part, dont seul le pays (BT-80, en en-tête) est lu. Ses
        // éléments portent les noms de ceux du vendeur et de l'acheteur (nom, adresse, contact…) :
        // les cas génériques les leur attribueraient, et la fermeture de son adresse basculait le
        // conteneur sur l'acheteur, ce qui faisait perdre BT-15/BT-16, lus ensuite.
        if container == .shipToParty || container == .shipToAddress {
            if container == .shipToParty && elementName == "ram:PostalTradeAddress" { container = .shipToAddress }
            return
        }
        switch elementName {
        case "ram:BusinessProcessSpecifiedDocumentContextParameter": container = .businessProcessParam
        case "ram:GuidelineSpecifiedDocumentContextParameter": container = .guidelineParam
        case "rsm:ExchangedDocument": container = .exchangedDocument
        case "ram:IncludedNote":
            container = .includedNote
            currentNoteContent = ""
            currentNoteSubjectCode = nil
        case "ram:IncludedSupplyChainTradeLineItem":
            container = .lineItem
            currentLine = LineBuilder()
        case "ram:SpecifiedTradeProduct" where container == .lineItem: container = .lineProduct
        case "ram:SpecifiedLineTradeAgreement" where container == .lineItem: container = .lineAgreement
        case "ram:BuyerOrderReferencedDocument" where container == .lineAgreement: pendingLineRef = .order
        case "ram:ContractReferencedDocument" where container == .lineAgreement: pendingLineRef = .contract
        case "ram:SpecifiedLineTradeDelivery" where container == .lineItem: container = .lineDelivery
        case "ram:ApplicableTradeTax" where container == .lineItem: container = .lineSettlementTax
        case "ram:BilledQuantity" where container == .lineDelivery:
            if let unit = attributeDict["unitCode"], !unit.isEmpty { currentLine.unit = unit }

        case "ram:SellerTradeParty": container = .sellerParty; partyContext = .seller
        case "ram:BuyerTradeParty": container = .buyerParty; partyContext = .buyer
        case "ram:DefinedTradeContact" where partyContext != .none: container = .partyContact
        case "ram:PostalTradeAddress" where partyContext != .none: container = .partyAddress
        case "ram:SpecifiedLegalOrganization" where partyContext != .none:
            container = .partyLegalOrg
            currentLegalSchemeID = attributeDict["schemeID"] ?? "0002"
        case "ram:SpecifiedTaxRegistration" where partyContext != .none: container = .partyTaxReg
        case "ram:URIUniversalCommunication" where partyContext != .none: container = .partyEndpoint
        case "ram:URIID" where container == .partyEndpoint:
            currentEndpointSchemeID = attributeDict["schemeID"] ?? "0225"

        case "ram:ApplicableHeaderTradeAgreement": container = .agreement
        case "ram:ApplicableHeaderTradeDelivery": container = .delivery
        case "ram:ApplicableHeaderTradeSettlement": container = .settlement
        case "ram:ApplicableTradeTax" where container == .settlement:
            container = .settlementTax
            currentTax = DeclaredTax()
        case "ram:SpecifiedTradeSettlementPaymentMeans" where container == .settlement: container = .paymentMeans
        case "ram:SpecifiedTradePaymentTerms" where container == .settlement: container = .paymentTerms
        case "ram:SpecifiedTradeSettlementHeaderMonetarySummation" where container == .settlement: container = .monetarySummation
        case "ram:InvoiceReferencedDocument" where container == .settlement: container = .invoiceReferenced

        // Les références d'en-tête (commande/contrat/appel d'offres) et le projet partagent
        // tous la même balise fille `ram:IssuerAssignedID`/`ram:ID` — on pose le drapeau au
        // conteneur (balise ouvrante), lu à la fermeture de la balise fille. L'appel d'offres
        // se lit sous sa forme EN16931 (AdditionalReferencedDocument, code type 50) comme
        // sous l'ancienne balise TendererReferencedDocument des XML déjà émis par l'app.
        case "ram:BuyerOrderReferencedDocument" where container == .agreement: pendingAgreementRef = .purchaseOrder
        case "ram:ContractReferencedDocument" where container == .agreement: pendingAgreementRef = .contract
        case "ram:TendererReferencedDocument" where container == .agreement: pendingAgreementRef = .tender
        case "ram:AdditionalReferencedDocument" where container == .agreement:
            pendingAgreementRef = .additional
            additionalRefID = nil
            additionalRefTypeCode = nil
        case "ram:SpecifiedProcuringProject" where container == .agreement: pendingAgreementRef = .project
        case "ram:ReceivingAdviceReferencedDocument" where container == .delivery: pendingDeliveryRef = .receivingAdvice
        case "ram:DespatchAdviceReferencedDocument" where container == .delivery: pendingDeliveryRef = .despatchAdvice
        case "ram:ShipToTradeParty" where container == .delivery || container == .lineDelivery:
            shipToParent = container
            container = .shipToParty
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        defer { text = "" }

        if container == .shipToParty || container == .shipToAddress {
            switch elementName {
            case "ram:CountryID" where container == .shipToAddress && shipToParent == .delivery: deliveryCountry = value
            case "ram:PostalTradeAddress" where container == .shipToAddress: container = .shipToParty
            case "ram:ShipToTradeParty" where container == .shipToParty: container = shipToParent
            default: break
            }
            return
        }

        switch elementName {
        case "ram:ID" where container == .businessProcessParam: billingModeRaw = value
        case "ram:ID" where container == .guidelineParam: profileURN = value
        case "ram:ID" where container == .exchangedDocument: number = value
        case "ram:TypeCode" where container == .exchangedDocument: typeCodeRaw = value
        case "udt:DateTimeString" where container == .exchangedDocument: issueDateRaw = value
        case "ram:Content" where container == .includedNote: currentNoteContent = value
        case "ram:SubjectCode" where container == .includedNote: currentNoteSubjectCode = value
        case "ram:IncludedNote":
            notes.append((currentNoteContent, currentNoteSubjectCode))
            container = .exchangedDocument

        // Lignes
        case "ram:Name" where container == .lineProduct: currentLine.name = value
        case "ram:Description" where container == .lineProduct: currentLine.description = value.isEmpty ? nil : value
        case "ram:GlobalID" where container == .lineProduct: currentLine.globalID = value
        case "ram:SellerAssignedID" where container == .lineProduct: currentLine.sellerAssignedID = value
        case "ram:BuyerAssignedID" where container == .lineProduct: currentLine.buyerAssignedID = value
        case "ram:SpecifiedTradeProduct": container = .lineItem
        case "ram:IssuerAssignedID" where container == .lineAgreement:
            switch pendingLineRef {
            case .order: currentLine.orderRef = value
            case .contract: currentLine.contractRef = value
            case .none: break
            }
        case "ram:LineID" where container == .lineAgreement && pendingLineRef == .order: currentLine.orderLineID = value
        case "ram:ChargeAmount" where container == .lineAgreement: currentLine.unitPrice = Double(value) ?? 0
        case "ram:SpecifiedLineTradeAgreement": container = .lineItem
        case "ram:BilledQuantity" where container == .lineDelivery: currentLine.quantity = Double(value) ?? 1
        case "ram:SpecifiedLineTradeDelivery": container = .lineItem
        case "ram:CategoryCode" where container == .lineSettlementTax: currentLine.vatCategory = VATCategory(rawValue: value) ?? .standard
        case "ram:RateApplicablePercent" where container == .lineSettlementTax: currentLine.vatRate = Double(value) ?? 0
        case "ram:ApplicableTradeTax" where container == .lineSettlementTax: container = .lineItem
        case "ram:IncludedSupplyChainTradeLineItem":
            lines.append(currentLine.build())
            container = .none

        // Tiers (seller/buyer) — `partyContext` reste posé tant qu'on n'a pas refermé la
        // balise SellerTradeParty/BuyerTradeParty correspondante, y compris à l'intérieur
        // des sous-conteneurs (adresse, contact, tiers légal…).
        case "ram:Name" where container == .sellerParty: seller.name = value
        case "ram:Name" where container == .buyerParty: buyer.name = value
        case "ram:ID" where container == .partyLegalOrg:
            if partyContext == .seller { seller.siren = value; seller.legalSchemeID = currentLegalSchemeID }
            else if partyContext == .buyer { buyer.siren = value; buyer.legalSchemeID = currentLegalSchemeID }
        case "ram:SpecifiedLegalOrganization": container = partyContext == .seller ? .sellerParty : .buyerParty
        case "ram:PersonName" where container == .partyContact:
            if partyContext == .seller { seller.contactName = value } else if partyContext == .buyer { buyer.contactName = value }
        case "ram:CompleteNumber" where container == .partyContact:
            if partyContext == .seller { seller.contactPhone = value } else if partyContext == .buyer { buyer.contactPhone = value }
        case "ram:URIID" where container == .partyContact:
            // EmailURIUniversalCommunication réutilise aussi URIID — distingué du cas
            // .partyEndpoint (adresse électronique PDP) par le conteneur courant.
            if partyContext == .seller { seller.contactEmail = value } else if partyContext == .buyer { buyer.contactEmail = value }
        case "ram:DefinedTradeContact": container = partyContext == .seller ? .sellerParty : .buyerParty
        case "ram:PostcodeCode" where container == .partyAddress:
            if partyContext == .seller { seller.postcode = value } else if partyContext == .buyer { buyer.postcode = value }
        case "ram:LineOne" where container == .partyAddress:
            if partyContext == .seller { seller.street = value } else if partyContext == .buyer { buyer.street = value }
        case "ram:CityName" where container == .partyAddress:
            if partyContext == .seller { seller.city = value } else if partyContext == .buyer { buyer.city = value }
        case "ram:CountryID" where container == .partyAddress:
            if partyContext == .seller { seller.country = value } else if partyContext == .buyer { buyer.country = value }
        case "ram:PostalTradeAddress": container = partyContext == .seller ? .sellerParty : .buyerParty
        case "ram:URIID" where container == .partyEndpoint:
            if partyContext == .seller { seller.endpointID = value; seller.endpointSchemeID = currentEndpointSchemeID }
            else if partyContext == .buyer { buyer.endpointID = value; buyer.endpointSchemeID = currentEndpointSchemeID }
        case "ram:URIUniversalCommunication": container = partyContext == .seller ? .sellerParty : .buyerParty
        case "ram:ID" where container == .partyTaxReg:
            if partyContext == .seller { seller.vatNumber = value } else if partyContext == .buyer { buyer.vatNumber = value }
        case "ram:SpecifiedTaxRegistration": container = partyContext == .seller ? .sellerParty : .buyerParty
        case "ram:SellerTradeParty": container = .agreement; partyContext = .none
        case "ram:BuyerTradeParty": container = .agreement; partyContext = .none

        // En-tête agreement
        case "ram:BuyerReference" where container == .agreement: buyerReference = value
        case "ram:IssuerAssignedID" where container == .agreement:
            switch pendingAgreementRef {
            case .purchaseOrder: purchaseOrderRef = value
            case .contract: contractRef = value
            case .tender: tenderRef = value
            case .additional: additionalRefID = value
            case .project, .none: break
            }
        case "ram:TypeCode" where container == .agreement && pendingAgreementRef == .additional: additionalRefTypeCode = value
        case "ram:ID" where container == .agreement && pendingAgreementRef == .project: procuringProjectID = value
        case "ram:BuyerOrderReferencedDocument", "ram:ContractReferencedDocument":
            if container == .agreement { pendingAgreementRef = .none }
            else if container == .lineAgreement { pendingLineRef = .none }
        case "ram:AdditionalReferencedDocument" where container == .agreement:
            if additionalRefTypeCode == "50", let id = additionalRefID, !id.isEmpty { tenderRef = id }
            pendingAgreementRef = .none
        case "ram:TendererReferencedDocument", "ram:SpecifiedProcuringProject":
            if container == .agreement { pendingAgreementRef = .none }

        // Delivery
        case "ram:IssuerAssignedID" where container == .delivery:
            if pendingDeliveryRef == .receivingAdvice { receivingAdviceRef = value }
            else if pendingDeliveryRef == .despatchAdvice { despatchAdviceRef = value }
        case "ram:ReceivingAdviceReferencedDocument", "ram:DespatchAdviceReferencedDocument":
            if container == .delivery { pendingDeliveryRef = .none }
        case "ram:ApplicableHeaderTradeDelivery": container = .none

        // Settlement
        case "ram:InvoiceCurrencyCode" where container == .settlement: currency = value
        case "ram:IBANID" where container == .paymentMeans: paymentIBAN = value
        case "ram:BICID" where container == .paymentMeans: paymentBIC = value
        case "ram:SpecifiedTradeSettlementPaymentMeans": container = .settlement
        case "ram:CalculatedAmount" where container == .settlementTax: currentTax.amount = Double(value) ?? 0
        case "ram:BasisAmount" where container == .settlementTax: currentTax.basis = Double(value) ?? 0
        case "ram:CategoryCode" where container == .settlementTax: currentTax.category = value
        case "ram:ExemptionReason" where container == .settlementTax: currentTax.exemptionReason = value
        case "ram:RateApplicablePercent" where container == .settlementTax: currentTax.rate = Double(value) ?? 0
        case "ram:ApplicableTradeTax" where container == .settlementTax:
            declaredTaxes.append(currentTax)
            container = .settlement
        case "ram:Description" where container == .paymentTerms: paymentTermsDescription = value
        case "udt:DateTimeString" where container == .paymentTerms: dueDateRaw = value
        case "ram:SpecifiedTradePaymentTerms": container = .settlement
        case "ram:LineTotalAmount" where container == .monetarySummation: declaredLineTotal = Double(value)
        case "ram:GrandTotalAmount" where container == .monetarySummation: declaredGrandTotal = Double(value)
        case "ram:TotalPrepaidAmount" where container == .monetarySummation: prepaidAmount = Double(value) ?? 0
        case "ram:SpecifiedTradeSettlementHeaderMonetarySummation": container = .settlement
        case "ram:IssuerAssignedID" where container == .invoiceReferenced: precedingInvoiceRef = value
        case "qdt:DateTimeString" where container == .invoiceReferenced: precedingInvoiceDateRaw = value
        case "ram:InvoiceReferencedDocument": container = .settlement
        case "ram:ApplicableHeaderTradeSettlement": container = .none
        case "ram:ApplicableHeaderTradeAgreement": container = .none
        default:
            break
        }
    }

    func buildInvoice() throws -> Invoice {
        guard !number.isEmpty else { throw CIIXMLParserError.missingRequiredField("ram:ID (numéro de facture)") }
        guard !seller.name.isEmpty else { throw CIIXMLParserError.missingRequiredField("ram:SellerTradeParty/ram:Name") }
        guard !buyer.name.isEmpty else { throw CIIXMLParserError.missingRequiredField("ram:BuyerTradeParty/ram:Name") }

        let type = InvoiceTypeCode(rawValue: typeCodeRaw) ?? .commercialInvoice
        let profile = FacturXProfile.allCases.first { $0.urn == profileURN } ?? .en16931
        let billingMode = BillingMode(rawValue: billingModeRaw) ?? .m1
        // Le jour du XML, lu dans le fuseau de l'app comme `CIIXMLGenerator` l'écrit : l'app
        // affiche ce jour-là, et le régénérer redonne la même date.
        let issueDate = issueDateRaw.isEmpty ? Date() : (DocumentDate.date(xmlString: issueDateRaw) ?? Date())
        let dueDate = dueDateRaw.isEmpty ? issueDate : (DocumentDate.date(xmlString: dueDateRaw) ?? issueDate)
        let precedingDate = precedingInvoiceDateRaw.flatMap { DocumentDate.date(xmlString: $0) }

        let plainNote = notes.first { $0.subjectCode == nil }?.content
        let pmt = notes.first { $0.subjectCode == "PMT" }?.content ?? ""
        let pmd = notes.first { $0.subjectCode == "PMD" }?.content ?? ""
        let aab = notes.first { $0.subjectCode == "AAB" }?.content ?? ""

        // Un ram:TypeCode hors des 4 cas connus d'InvoiceTypeCode (le flux FR EN16931 en
        // accepte 16 au total — voir CIIXMLGenerator.xmlTypeCode) retombe sur "Facture
        // commerciale" par défaut, mais la valeur d'origine est conservée plutôt que
        // silencieusement perdue.
        var optionalFields: [OptionalField] = []
        if !typeCodeRaw.isEmpty, InvoiceTypeCode(rawValue: typeCodeRaw) == nil {
            optionalFields.append(OptionalField(tagName: "ram:TypeCode", value: typeCodeRaw))
        }
        if let p = procuringProjectID, !p.isEmpty {
            optionalFields.append(OptionalField(tagName: "ram:SpecifiedProcuringProject/ram:ID", value: p))
        }

        var invoice = Invoice(
            number: number,
            type: type,
            issueDate: issueDate,
            dueDate: dueDate,
            currency: currency,
            profile: profile,
            seller: seller.build(),
            buyer: buyer.build(),
            buyerReference: buyerReference,
            purchaseOrderRef: purchaseOrderRef,
            precedingInvoiceRef: precedingInvoiceRef,
            precedingInvoiceDate: precedingDate,
            lines: lines,
            paymentIBAN: paymentIBAN,
            paymentBIC: paymentBIC,
            paymentTerms: paymentTermsDescription,
            notes: plainNote,
            billingMode: billingMode,
            // Des notes PMT/PMD/AAB absentes du document veulent dire qu'il n'y en a pas —
            // contrairement à la valeur par défaut de l'initialisateur (texte français
            // standard), qui n'a de sens que pour une facture qu'on émet nous-mêmes, pas
            // pour un document tiers reçu tel quel.
            legalNotePMT: pmt,
            legalNotePMD: pmd,
            legalNoteAAB: aab,
            prepaidAmount: prepaidAmount,
            optionalFields: optionalFields
        )
        invoice.contractRef = contractRef
        invoice.tenderRef = tenderRef
        invoice.receivingAdviceRef = receivingAdviceRef
        invoice.despatchAdviceRef = despatchAdviceRef
        invoice.deliveryCountry = deliveryCountry

        // BT-120 (motif d'exonération) est porté par la ventilation TVA d'en-tête (BG-23),
        // jamais par la ligne elle-même dans le XML que produit CIIXMLGenerator — voir la
        // doc de DeclaredTax. Reporté ici sur chaque ligne dont le couple (taux, catégorie)
        // correspond à un groupe d'en-tête ayant un motif déclaré.
        for taxGroup in declaredTaxes {
            guard let reason = taxGroup.exemptionReason, !reason.isEmpty else { continue }
            for idx in invoice.lines.indices {
                let line = invoice.lines[idx]
                if line.vatRate == taxGroup.rate, line.vatCategory.rawValue == taxGroup.category,
                   (line.vatExemptionReason ?? "").isEmpty {
                    invoice.lines[idx].vatExemptionReason = reason
                }
            }
        }

        checkDeclaredTotals(against: invoice)
        return invoice
    }

    /// Avertissements de cohérence relevés pendant le parse (voir `checkDeclaredTotals`) —
    /// exposés via `CIIXMLParser.parseWithWarnings(xml:)`.
    private(set) var warnings: [String] = []

    /// Comparaison déclaré vs recalculé, faite ici (au parse) car `Invoice` ne conserve pas
    /// les totaux déclarés par le document d'origine — seulement les lignes, dont les
    /// totaux sont toujours recalculés à la volée. Sans ce contrôle immédiat, une
    /// incohérence dans un document reçu (saisie manuelle erronée, XML corrompu) ne serait
    /// plus jamais détectable après coup. Avertissement doux (jamais une erreur bloquante) :
    /// rejeter une vraie facture fournisseur pour un simple écart d'arrondi serait pire que
    /// de juste le signaler.
    private func checkDeclaredTotals(against invoice: Invoice) {
        let tolerance = 0.02
        if let declared = declaredLineTotal, abs(declared - invoice.lineTotal) > tolerance {
            warnings.append("Écart total HT déclaré (\(declared)) vs recalculé (\(invoice.lineTotal)) pour la facture \(invoice.number).")
        }
        if let declared = declaredGrandTotal, abs(declared - invoice.grandTotal) > tolerance {
            warnings.append("Écart total TTC déclaré (\(declared)) vs recalculé (\(invoice.grandTotal)) pour la facture \(invoice.number).")
        }
    }
}
