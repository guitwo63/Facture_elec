import Foundation

public enum OrderCIOXMLError: Error {
    case emptyLines
    case invalidAmount
}

/// Générateur XML Order-X : Cross Industry Order (CIO) D20B.
/// Racine rsm:SCRDMCCBDACIOMessageStructure (UN/CEFACT 2020), TypeCode 220,
/// embedded file order-x.xml, profils urn:order-x.eu:1p0:{basic,comfort,extended}.
public struct OrderCIOXMLGenerator {
    public init() {}

    public func generate(order: SalesOrder) throws -> Data {
        guard !order.lines.isEmpty else { throw OrderCIOXMLError.emptyLines }

        // Jour du fuseau de l'app, celui du PDF de la commande (voir `DocumentDate`).
        let issue = DocumentDate.xmlString(order.issueDate)
        let requested = DocumentDate.xmlString(order.requestedDeliveryDate)

        let xmlLines = order.lines.enumerated().map { xmlLine($0.element, index: $0.offset, profile: order.profile) }.joined()

        let seller = xmlParty(order.seller, role: .seller)
        let buyer = xmlParty(order.buyer, role: .buyer)
        // Ordre du XSD (HeaderTradeAgreementType, les trois profils) : la commande
        // (BuyerOrderReferencedDocument) AVANT le devis (QuotationReferencedDocument). L'ordre
        // inverse rendait le XML invalide dès qu'une référence de devis était saisie.
        let agreement = """
        <ram:ApplicableHeaderTradeAgreement>
\(buyerReferenceXML(order))\(seller)\(buyer)\(buyerOrderXML(order))\(quotationXML(order))\(contractXML(order))\(blanketOrderXML(order))\(previousOrderChangeXML(order))\(previousOrderResponseXML(order))
        </ram:ApplicableHeaderTradeAgreement>
"""
        let delivery = """
        <ram:ApplicableHeaderTradeDelivery>
          <ram:RequestedDeliverySupplyChainEvent>
            <ram:OccurrenceDateTime>
              <udt:DateTimeString format="102">\(requested)</udt:DateTimeString>
            </ram:OccurrenceDateTime>
          </ram:RequestedDeliverySupplyChainEvent>
        </ram:ApplicableHeaderTradeDelivery>
"""
        let settlement = xmlSettlement(order)

        let xml = """
<?xml version="1.0" encoding="UTF-8"?>
<rsm:SCRDMCCBDACIOMessageStructure xmlns:rsm="urn:un:unece:uncefact:data:SCRDMCCBDACIOMessageStructure:100" xmlns:ram="urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:128" xmlns:qdt="urn:un:unece:uncefact:data:standard:QualifiedDataType:128" xmlns:udt="urn:un:unece:uncefact:data:standard:UnqualifiedDataType:128">
  <rsm:ExchangedDocumentContext>
    <ram:BusinessProcessSpecifiedDocumentContextParameter>
      <ram:ID>A1</ram:ID>
    </ram:BusinessProcessSpecifiedDocumentContextParameter>
    <ram:GuidelineSpecifiedDocumentContextParameter>
      <ram:ID>\(order.profile.urn)</ram:ID>
    </ram:GuidelineSpecifiedDocumentContextParameter>
  </rsm:ExchangedDocumentContext>
  <rsm:ExchangedDocument>
    <ram:ID>\(escape(order.number))</ram:ID>
    <ram:TypeCode>\(order.type.rawValue)</ram:TypeCode>
    <ram:IssueDateTime>
      <udt:DateTimeString format="102">\(issue)</udt:DateTimeString>
    </ram:IssueDateTime>
    <ram:RequestedResponseTypeCode>\(escape(order.requestedResponseTypeCode))</ram:RequestedResponseTypeCode>
\(notesXML(order))  </rsm:ExchangedDocument>
  <rsm:SupplyChainTradeTransaction>
\(xmlLines)\(indented(agreement))\(indented(delivery))\(indented(settlement))  </rsm:SupplyChainTradeTransaction>
</rsm:SCRDMCCBDACIOMessageStructure>
"""
        guard let data = xml.data(using: .utf8) else { throw OrderCIOXMLError.invalidAmount }
        return data
    }

    /// BASIC n'admet ni description d'article (TradeProductType : identifiants et nom) ni TVA de
    /// ligne (LineTradeSettlementType : montant seul) ; COMFORT et EXTENDED admettent les deux.
    private func xmlLine(_ line: InvoiceLine, index: Int, profile: OrderXProfile) -> String {
        let detailed = profile != .basic
        let lineID = String(index + 1)
        let qty = String(format: "%.4f", line.quantity)
        let price = String(format: "%.4f", line.unitPrice)
        let total = String(format: "%.2f", line.lineTotal)
        let rate = formatRate(line.vatRate)
        let category = line.vatCategory.rawValue
        let unitCode = line.unit.trimmingCharacters(in: .whitespaces).isEmpty ? "C62" : line.unit
        let desc = line.description.map { """
            <ram:Description>\(escape($0))</ram:Description>
""" } ?? ""
        let tax = """
            <ram:ApplicableTradeTax>
              <ram:TypeCode>VAT</ram:TypeCode>
              <ram:CategoryCode>\(category)</ram:CategoryCode>
              <ram:RateApplicablePercent>\(rate)</ram:RateApplicablePercent>
            </ram:ApplicableTradeTax>

"""
        return """
        <ram:IncludedSupplyChainTradeLineItem>
          <ram:AssociatedDocumentLineDocument><ram:LineID>\(lineID)</ram:LineID></ram:AssociatedDocumentLineDocument>
          <ram:SpecifiedTradeProduct>
            <ram:Name>\(escape(line.name))</ram:Name>\(detailed ? desc : "")
          </ram:SpecifiedTradeProduct>
          <ram:SpecifiedLineTradeAgreement>
            <ram:NetPriceProductTradePrice>
              <ram:ChargeAmount>\(price)</ram:ChargeAmount>
            </ram:NetPriceProductTradePrice>
          </ram:SpecifiedLineTradeAgreement>
          <ram:SpecifiedLineTradeDelivery>
            <ram:RequestedQuantity unitCode="\(unitCode)">\(qty)</ram:RequestedQuantity>
          </ram:SpecifiedLineTradeDelivery>
          <ram:SpecifiedLineTradeSettlement>
\(detailed ? tax : "")            <ram:SpecifiedTradeSettlementLineMonetarySummation>
              <ram:LineTotalAmount>\(total)</ram:LineTotalAmount>
            </ram:SpecifiedTradeSettlementLineMonetarySummation>
          </ram:SpecifiedLineTradeSettlement>
        </ram:IncludedSupplyChainTradeLineItem>
"""
    }

    private enum PartyRole { case seller, buyer }

    private func xmlParty(_ party: InvoiceParty, role: PartyRole) -> String {
        let tag = role == .seller ? "SellerTradeParty" : "BuyerTradeParty"
        let legalOrg = party.siren.map { siren -> String in
            """
        <ram:SpecifiedLegalOrganization>
          <ram:ID schemeID="\(party.legalSchemeID)">\(escape(siren))</ram:ID>
        </ram:SpecifiedLegalOrganization>
"""
        } ?? ""

        let endpointIDValue = trimmedNonEmpty(party.endpointID)
        let sirenValue = trimmedNonEmpty(party.siren)
        let effectiveEndpointID = endpointIDValue ?? sirenValue
        let effectiveSchemeID: String
        if endpointIDValue != nil {
            let raw = party.endpointSchemeID.trimmingCharacters(in: .whitespaces)
            if raw.isEmpty || raw == "FR:SIRENE" || raw == "0183" {
                effectiveSchemeID = "0225"
            } else {
                effectiveSchemeID = raw
            }
        } else {
            effectiveSchemeID = "0225"
        }
        let endpoint = effectiveEndpointID.map { id -> String in
            """
          <ram:URIUniversalCommunication>
            <ram:URIID schemeID="\(effectiveSchemeID)">\(escape(id))</ram:URIID>
          </ram:URIUniversalCommunication>
"""
        } ?? ""

        let contact = xmlContact(party)

        let taxReg = party.vatNumber.map { vat -> String in
            """
        <ram:SpecifiedTaxRegistration>
          <ram:ID schemeID="VA">\(escape(vat))</ram:ID>
        </ram:SpecifiedTaxRegistration>
"""
        } ?? ""

        let body = """
        <ram:\(tag)>
          <ram:Name>\(escape(party.name))</ram:Name>\(legalOrg.isEmpty ? "" : legalOrg)\(contact.isEmpty ? "" : contact)
          <ram:PostalTradeAddress>
            <ram:PostcodeCode>\(escape(party.postcode))</ram:PostcodeCode>
            <ram:LineOne>\(escape(party.street))</ram:LineOne>
            <ram:CityName>\(escape(party.city))</ram:CityName>
            <ram:CountryID>\(escape(party.country))</ram:CountryID>
          </ram:PostalTradeAddress>\(endpoint.isEmpty ? "" : endpoint)\(taxReg.isEmpty ? "" : taxReg)
        </ram:\(tag)>
"""
        return body
    }

    private func xmlContact(_ party: InvoiceParty) -> String {
        let name = trimmedNonEmpty(party.contactName)
        let phone = trimmedNonEmpty(party.contactPhone)
        let email = trimmedNonEmpty(party.contactEmail)

        guard name != nil || phone != nil || email != nil else {
            return ""
        }

        let person = name.map { """
            <ram:PersonName>\(escape($0))</ram:PersonName>
""" } ?? ""
        let phoneXML = phone.map { """
            <ram:TelephoneUniversalCommunication>
              <ram:CompleteNumber>\(escape($0))</ram:CompleteNumber>
            </ram:TelephoneUniversalCommunication>
""" } ?? ""
        let emailXML = email.map { """
            <ram:EmailURIUniversalCommunication>
              <ram:URIID>\(escape($0))</ram:URIID>
            </ram:EmailURIUniversalCommunication>
""" } ?? ""
        return """
    <ram:DefinedTradeContact>\(person)\(phoneXML)\(emailXML)
    </ram:DefinedTradeContact>
"""
    }

    private func trimmedNonEmpty(_ s: String?) -> String? {
        guard let s = s else { return nil }
        let t = s.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : t
    }

    private func buyerReferenceXML(_ order: SalesOrder) -> String {
        guard let ref = order.buyerReference, !ref.isEmpty else { return "" }
        return """
      <ram:BuyerReference>\(escape(ref))</ram:BuyerReference>
"""
    }

    private func quotationXML(_ order: SalesOrder) -> String {
        guard let ref = order.quotationRef, !ref.isEmpty else { return "" }
        return """
      <ram:QuotationReferencedDocument>
        <ram:IssuerAssignedID>\(escape(ref))</ram:IssuerAssignedID>
      </ram:QuotationReferencedDocument>
"""
    }

    private func buyerOrderXML(_ order: SalesOrder) -> String {
        guard !order.number.trimmingCharacters(in: .whitespaces).isEmpty else { return "" }
        return """
      <ram:BuyerOrderReferencedDocument>
        <ram:IssuerAssignedID>\(escape(order.number))</ram:IssuerAssignedID>
      </ram:BuyerOrderReferencedDocument>
"""
    }

    private func contractXML(_ order: SalesOrder) -> String {
        guard let ref = order.contractRef, !ref.isEmpty else { return "" }
        return """
      <ram:ContractReferencedDocument>
        <ram:IssuerAssignedID>\(escape(ref))</ram:IssuerAssignedID>
      </ram:ContractReferencedDocument>
"""
    }

    private func blanketOrderXML(_ order: SalesOrder) -> String {
        guard let ref = order.blanketOrderRef, !ref.isEmpty else { return "" }
        return """
      <ram:BlanketOrderReferencedDocument>
        <ram:IssuerAssignedID>\(escape(ref))</ram:IssuerAssignedID>
      </ram:BlanketOrderReferencedDocument>
"""
    }

    private func previousOrderChangeXML(_ order: SalesOrder) -> String {
        guard let ref = order.previousOrderChangeRef, !ref.isEmpty else { return "" }
        return """
      <ram:PreviousOrderChangeReferencedDocument>
        <ram:IssuerAssignedID>\(escape(ref))</ram:IssuerAssignedID>
      </ram:PreviousOrderChangeReferencedDocument>
"""
    }

    private func previousOrderResponseXML(_ order: SalesOrder) -> String {
        guard let ref = order.previousOrderResponseRef, !ref.isEmpty else { return "" }
        return """
      <ram:PreviousOrderResponseReferencedDocument>
        <ram:IssuerAssignedID>\(escape(ref))</ram:IssuerAssignedID>
      </ram:PreviousOrderResponseReferencedDocument>
"""
    }

    private func notesXML(_ order: SalesOrder) -> String {
        guard let custom = order.notes, !custom.isEmpty else { return "" }
        return """
    <ram:IncludedNote>
      <ram:Content>\(escape(custom))</ram:Content>
    </ram:IncludedNote>
"""
    }

    /// Le récapitulatif de TVA d'en-tête (`ApplicableTradeTax`) n'existe qu'en EXTENDED : le XSD
    /// de COMFORT et de BASIC (HeaderTradeSettlementType) le refuse. En COMFORT, la TVA reste
    /// portée par les lignes et par TaxTotalAmount.
    private func xmlSettlement(_ order: SalesOrder) -> String {
        let tradeTax = order.vatBreakdown.map { item -> String in
            let amount = String(format: "%.2f", item.amount)
            let basis = String(format: "%.2f", item.basis)
            let rate = formatRate(item.rate)
            let category = item.category.rawValue
            let exemptionReason = item.exemptionReason.map { "\n        <ram:ExemptionReason>\(escape($0))</ram:ExemptionReason>" } ?? ""
            return """
      <ram:ApplicableTradeTax>
        <ram:CalculatedAmount>\(amount)</ram:CalculatedAmount>
        <ram:TypeCode>VAT</ram:TypeCode>\(exemptionReason)
        <ram:BasisAmount>\(basis)</ram:BasisAmount>
        <ram:CategoryCode>\(category)</ram:CategoryCode>
        <ram:RateApplicablePercent>\(rate)</ram:RateApplicablePercent>
      </ram:ApplicableTradeTax>
"""
        }.joined()

        let lineTotal = String(format: "%.2f", order.lineTotal)
        let taxBasis = String(format: "%.2f", order.lineTotal)
        let taxTotal = String(format: "%.2f", order.taxTotal)
        let grand = String(format: "%.2f", order.grandTotal)

        return """
    <ram:ApplicableHeaderTradeSettlement>
      <ram:OrderCurrencyCode>\(escape(order.currency))</ram:OrderCurrencyCode>
\(order.profile == .extended ? tradeTax : "")      <ram:SpecifiedTradeSettlementHeaderMonetarySummation>
        <ram:LineTotalAmount>\(lineTotal)</ram:LineTotalAmount>
        <ram:TaxBasisTotalAmount>\(taxBasis)</ram:TaxBasisTotalAmount>
        <ram:TaxTotalAmount currencyID="\(escape(order.currency))">\(taxTotal)</ram:TaxTotalAmount>
        <ram:GrandTotalAmount>\(grand)</ram:GrandTotalAmount>
      </ram:SpecifiedTradeSettlementHeaderMonetarySummation>
    </ram:ApplicableHeaderTradeSettlement>
"""
    }

    /// « 20 » pour un taux entier, « 5.50 » sinon. Même correctif que `CIIXMLGenerator` :
    /// `rate.rounded()` arrondissait à 2 décimales, et 5,5 % était émis « 6 ».
    private func formatRate(_ rate: Double) -> String {
        if rate.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", rate)
        }
        return String(format: "%.2f", rate)
    }

    private func indented(_ block: String) -> String {
        block.split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0) }
            .joined(separator: "\n")
    }

    private func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
