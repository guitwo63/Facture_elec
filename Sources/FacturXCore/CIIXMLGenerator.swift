import Foundation

public enum CIIXMLError: Error {
    case emptyLines
    case invalidAmount
}

public struct CIIXMLGenerator {
    public init() {}

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    /// Date telle qu'écrite dans le XML (format 102 = AAAAMMJJ, en UTC). `EN16931BusinessRules`
    /// compare ces mêmes chaînes pour BR-FR-CO-07, comme le Schematron France CTC : la règle
    /// ne peut pas diverger de ce que la PDP reçoit.
    static func xmlDate(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }

    public func generate(invoice: Invoice) throws -> Data {
        guard !invoice.lines.isEmpty else { throw CIIXMLError.emptyLines }

        let issue = Self.xmlDate(invoice.issueDate)
        let due = Self.xmlDate(invoice.dueDate)

        let xmlLines = invoice.lines.enumerated().map { xmlLine($0.element, index: $0.offset) }.joined()

        let seller = xmlParty(invoice.seller, role: .seller)
        let buyer = xmlParty(invoice.buyer, role: .buyer)
        let projectRef = projectReferenceXML(invoice)
        let agreement = """
        <ram:ApplicableHeaderTradeAgreement>
\(buyerReferenceXML(invoice))\(seller)\(buyer)\(purchaseOrderXML(invoice))\(contractXML(invoice))\(tenderXML(invoice))\(projectRef.isEmpty ? "" : projectRef)
        </ram:ApplicableHeaderTradeAgreement>
"""
        // Le XSD impose l'avis d'expédition (BT-16) AVANT l'avis de réception (BT-15) : l'ordre
        // inverse, utilisé jusqu'ici, rendait le XML invalide dès que les deux étaient saisis.
        let delivery = """
        <ram:ApplicableHeaderTradeDelivery>
          <ram:ActualDeliverySupplyChainEvent>
            <ram:OccurrenceDateTime>
              <udt:DateTimeString format="102">\(issue)</udt:DateTimeString>
            </ram:OccurrenceDateTime>
          </ram:ActualDeliverySupplyChainEvent>
\(despatchAdviceXML(invoice))\(receivingAdviceXML(invoice))
        </ram:ApplicableHeaderTradeDelivery>
"""
        let settlement = xmlSettlement(invoice, issue: issue, due: due)

        let xml = """
<?xml version="1.0" encoding="UTF-8"?>
<rsm:CrossIndustryInvoice xmlns:rsm="urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100" xmlns:ram="urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100" xmlns:qdt="urn:un:unece:uncefact:data:standard:QualifiedDataType:100" xmlns:udt="urn:un:unece:uncefact:data:standard:UnqualifiedDataType:100">
  <rsm:ExchangedDocumentContext>
    <ram:BusinessProcessSpecifiedDocumentContextParameter>
      <ram:ID>\(invoice.billingMode.rawValue)</ram:ID>
    </ram:BusinessProcessSpecifiedDocumentContextParameter>
    <ram:GuidelineSpecifiedDocumentContextParameter>
      <ram:ID>\(invoice.profile.urn)</ram:ID>
    </ram:GuidelineSpecifiedDocumentContextParameter>
  </rsm:ExchangedDocumentContext>
  <rsm:ExchangedDocument>
    <ram:ID>\(escape(invoice.number))</ram:ID>
    <ram:TypeCode>\(xmlTypeCode(for: invoice.type))</ram:TypeCode>
    <ram:IssueDateTime>
      <udt:DateTimeString format="102">\(issue)</udt:DateTimeString>
    </ram:IssueDateTime>
\(notesXML(invoice))  </rsm:ExchangedDocument>
  <rsm:SupplyChainTradeTransaction>
\(xmlLines)\(indented(agreement))\(indented(delivery))\(indented(settlement))  </rsm:SupplyChainTradeTransaction>
</rsm:CrossIndustryInvoice>
"""
        guard let data = xml.data(using: .utf8) else { throw CIIXMLError.invalidAmount }
        return data
    }

    private func xmlLine(_ line: InvoiceLine, index: Int) -> String {
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
        // Identifiants de l'article, dans l'ordre du XSD (TradeProductType) : GTIN (BT-157,
        // dont le schemeID est exigé par BR-64), vendeur (BT-155), acheteur (BT-156).
        var productIDs = ""
        if let v = optionalValue(line.optionalFields, "ram:GlobalID") {
            productIDs += """
            <ram:GlobalID schemeID="0160">\(escape(v))</ram:GlobalID>
"""
        }
        if let v = optionalValue(line.optionalFields, "ram:SellerAssignedID") {
            productIDs += """
            <ram:SellerAssignedID>\(escape(v))</ram:SellerAssignedID>
"""
        }
        if let v = optionalValue(line.optionalFields, "ram:BuyerAssignedID") {
            productIDs += """
            <ram:BuyerAssignedID>\(escape(v))</ram:BuyerAssignedID>
"""
        }
        // BT-132 : au niveau de la ligne, le profil EN16931 n'admet dans la référence de
        // commande que le numéro de ligne (LineID) — ni IssuerAssignedID (signalé hors profil
        // par le Schematron) ni ContractReferencedDocument (rejeté par le XSD), que les
        // anciennes balises de ligne émettaient.
        var lineRefs = ""
        if let v = optionalValue(line.optionalFields, "ram:BuyerOrderReferencedDocument/ram:LineID") {
            lineRefs += """
            <ram:BuyerOrderReferencedDocument>
              <ram:LineID>\(escape(v))</ram:LineID>
            </ram:BuyerOrderReferencedDocument>
"""
        }
        return """
        <ram:IncludedSupplyChainTradeLineItem>
          <ram:AssociatedDocumentLineDocument><ram:LineID>\(lineID)</ram:LineID></ram:AssociatedDocumentLineDocument>
          <ram:SpecifiedTradeProduct>\(productIDs.isEmpty ? "" : productIDs)
            <ram:Name>\(escape(line.name))</ram:Name>\(desc.isEmpty ? "" : desc)
          </ram:SpecifiedTradeProduct>
          <ram:SpecifiedLineTradeAgreement>\(lineRefs.isEmpty ? "" : lineRefs)
            <ram:NetPriceProductTradePrice>
              <ram:ChargeAmount>\(price)</ram:ChargeAmount>
            </ram:NetPriceProductTradePrice>
          </ram:SpecifiedLineTradeAgreement>
          <ram:SpecifiedLineTradeDelivery>
            <ram:BilledQuantity unitCode="\(unitCode)">\(qty)</ram:BilledQuantity>
          </ram:SpecifiedLineTradeDelivery>
          <ram:SpecifiedLineTradeSettlement>
            <ram:ApplicableTradeTax>
              <ram:TypeCode>VAT</ram:TypeCode>
              <ram:CategoryCode>\(category)</ram:CategoryCode>
              <ram:RateApplicablePercent>\(rate)</ram:RateApplicablePercent>
            </ram:ApplicableTradeTax>
            <ram:SpecifiedTradeSettlementLineMonetarySummation>
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

    private func optionalValue(_ fields: [OptionalField], _ tagName: String) -> String? {
        trimmedNonEmpty(fields.first(where: { $0.tagName == tagName && trimmedNonEmpty($0.value) != nil })?.value)
    }

    private func buyerReferenceXML(_ invoice: Invoice) -> String {
        guard let ref = invoice.buyerReference, !ref.isEmpty else { return "" }
        return """
      <ram:BuyerReference>\(escape(ref))</ram:BuyerReference>
"""
    }

    private func purchaseOrderXML(_ invoice: Invoice) -> String {
        guard let ref = invoice.purchaseOrderRef, !ref.isEmpty else { return "" }
        return """
      <ram:BuyerOrderReferencedDocument>
        <ram:IssuerAssignedID>\(escape(ref))</ram:IssuerAssignedID>
      </ram:BuyerOrderReferencedDocument>
"""
    }
    private func contractXML(_ invoice: Invoice) -> String {
        guard let ref = invoice.contractRef, !ref.isEmpty else { return "" }
        return """
      <ram:ContractReferencedDocument>
        <ram:IssuerAssignedID>\(escape(ref))</ram:IssuerAssignedID>
      </ram:ContractReferencedDocument>
"""
    }
    /// BT-17 (appel d'offres ou lot) : `AdditionalReferencedDocument` de code type 50, placé
    /// après le contrat et avant le projet comme l'impose le XSD.
    private func tenderXML(_ invoice: Invoice) -> String {
        guard let ref = invoice.tenderRef, !ref.isEmpty else { return "" }
        return """
      <ram:AdditionalReferencedDocument>
        <ram:IssuerAssignedID>\(escape(ref))</ram:IssuerAssignedID>
        <ram:TypeCode>50</ram:TypeCode>
      </ram:AdditionalReferencedDocument>
"""
    }
    private func receivingAdviceXML(_ invoice: Invoice) -> String {
        guard let ref = invoice.receivingAdviceRef, !ref.isEmpty else { return "" }
        return """
      <ram:ReceivingAdviceReferencedDocument>
        <ram:IssuerAssignedID>\(escape(ref))</ram:IssuerAssignedID>
      </ram:ReceivingAdviceReferencedDocument>
"""
    }
    private func despatchAdviceXML(_ invoice: Invoice) -> String {
        guard let ref = invoice.despatchAdviceRef, !ref.isEmpty else { return "" }
        return """
      <ram:DespatchAdviceReferencedDocument>
        <ram:IssuerAssignedID>\(escape(ref))</ram:IssuerAssignedID>
      </ram:DespatchAdviceReferencedDocument>
"""
    }

    private func notesXML(_ invoice: Invoice) -> String {
        var notes: [String] = []

        if let custom = invoice.notes, !custom.isEmpty {
            notes.append("""
    <ram:IncludedNote>
      <ram:Content>\(escape(custom))</ram:Content>
    </ram:IncludedNote>
""")
        }

        if !invoice.legalNotePMT.isEmpty {
            notes.append("""
    <ram:IncludedNote>
      <ram:Content>\(escape(invoice.legalNotePMT))</ram:Content>
      <ram:SubjectCode>PMT</ram:SubjectCode>
    </ram:IncludedNote>
""")
        }
        if !invoice.legalNotePMD.isEmpty {
            notes.append("""
    <ram:IncludedNote>
      <ram:Content>\(escape(invoice.legalNotePMD))</ram:Content>
      <ram:SubjectCode>PMD</ram:SubjectCode>
    </ram:IncludedNote>
""")
        }
        if !invoice.legalNoteAAB.isEmpty {
            notes.append("""
    <ram:IncludedNote>
      <ram:Content>\(escape(invoice.legalNoteAAB))</ram:Content>
      <ram:SubjectCode>AAB</ram:SubjectCode>
    </ram:IncludedNote>
""")
        }

        return notes.joined()
    }

    private func xmlSettlement(_ invoice: Invoice, issue: String, due: String) -> String {
        let tradeTax = invoice.vatBreakdown.map { item -> String in
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

        let paymentMeans = xmlPaymentMeans(invoice)
        let paymentTerms = xmlPaymentTerms(invoice, due: due)

        let lineTotal = String(format: "%.2f", invoice.lineTotal)
        let taxBasis = String(format: "%.2f", invoice.lineTotal)
        let taxTotal = String(format: "%.2f", invoice.taxTotal)
        let grand = String(format: "%.2f", invoice.grandTotal)
        let duePay = String(format: "%.2f", invoice.netToPay)
        // En cadre « déjà payée » (B2/S2/M2), BR-FR-CO-09 compare BT-113 au total TTC : il
        // doit être présent même à zéro (facture d'un montant nul), sinon la règle échoue.
        let prepaidLine = invoice.prepaidAmount > 0 || invoice.billingMode.isAlreadyPaid
            ? "        <ram:TotalPrepaidAmount>\(String(format: "%.2f", invoice.prepaidAmount))</ram:TotalPrepaidAmount>\n"
            : ""

        return """
    <ram:ApplicableHeaderTradeSettlement>
      <ram:InvoiceCurrencyCode>\(escape(invoice.currency))</ram:InvoiceCurrencyCode>
\(paymentMeans)\(tradeTax)\(paymentTerms)      <ram:SpecifiedTradeSettlementHeaderMonetarySummation>
        <ram:LineTotalAmount>\(lineTotal)</ram:LineTotalAmount>
        <ram:TaxBasisTotalAmount>\(taxBasis)</ram:TaxBasisTotalAmount>
        <ram:TaxTotalAmount currencyID="\(escape(invoice.currency))">\(taxTotal)</ram:TaxTotalAmount>
        <ram:GrandTotalAmount>\(grand)</ram:GrandTotalAmount>
\(prepaidLine)        <ram:DuePayableAmount>\(duePay)</ram:DuePayableAmount>
      </ram:SpecifiedTradeSettlementHeaderMonetarySummation>\(invoiceReferencedXML(invoice))
    </ram:ApplicableHeaderTradeSettlement>
"""
    }

    private func xmlPaymentMeans(_ invoice: Invoice) -> String {
        guard let iban = invoice.paymentIBAN, !iban.isEmpty else { return "" }
        let ibanLine = """
        <ram:PayeePartyCreditorFinancialAccount>
          <ram:IBANID>\(escape(iban))</ram:IBANID>
        </ram:PayeePartyCreditorFinancialAccount>
"""
        let bic = invoice.paymentBIC.map { bic -> String in
            """
        <ram:PayeeSpecifiedCreditorFinancialInstitution>
          <ram:BICID>\(escape(bic))</ram:BICID>
        </ram:PayeeSpecifiedCreditorFinancialInstitution>
"""
        } ?? ""
        return """
      <ram:SpecifiedTradeSettlementPaymentMeans>
        <ram:TypeCode>58</ram:TypeCode>
        <ram:Information>SEPA</ram:Information>\(ibanLine)\(bic)
      </ram:SpecifiedTradeSettlementPaymentMeans>
"""
    }

    private func xmlPaymentTerms(_ invoice: Invoice, due: String) -> String {
        if let terms = invoice.paymentTerms, !terms.isEmpty {
            return """
      <ram:SpecifiedTradePaymentTerms>
        <ram:Description>\(escape(terms))</ram:Description>
        <ram:DueDateDateTime>
          <udt:DateTimeString format="102">\(due)</udt:DateTimeString>
        </ram:DueDateDateTime>
      </ram:SpecifiedTradePaymentTerms>
"""
        }
        return """
      <ram:SpecifiedTradePaymentTerms>
        <ram:DueDateDateTime>
          <udt:DateTimeString format="102">\(due)</udt:DateTimeString>
        </ram:DueDateDateTime>
      </ram:SpecifiedTradePaymentTerms>
"""
    }

    private func invoiceReferencedXML(_ invoice: Invoice) -> String {
        guard let ref = invoice.precedingInvoiceRef, !ref.isEmpty else { return "" }
        let dateStr = Self.xmlDate(invoice.precedingInvoiceDate ?? invoice.issueDate)
        return """
      <ram:InvoiceReferencedDocument>
        <ram:IssuerAssignedID>\(escape(ref))</ram:IssuerAssignedID>
        <ram:FormattedIssueDateTime>
          <qdt:DateTimeString format="102">\(dateStr)</qdt:DateTimeString>
        </ram:FormattedIssueDateTime>
      </ram:InvoiceReferencedDocument>
"""
    }
    private func formatRate(_ rate: Double) -> String {
        if rate == rate.rounded() {
            return String(format: "%.0f", rate)
        }
        return String(format: "%.2f", rate)
    }

    private func xmlTypeCode(for type: InvoiceTypeCode) -> String {
        // Codes acceptés par le flux FR EN16931 : 380, 389, 393, 501, 386, 500, 384,
        // 471, 472, 473, 261, 262, 381, 396, 502, 503. Les acomptes (386) sont admis,
        // mais le solde (387) ne l'est pas : on l'émet en 380 (facture commerciale)
        // avec TotalPrepaidAmount renseigné pour les acomptes déjà payés.
        switch type {
        case .finalSettlement:
            return InvoiceTypeCode.commercialInvoice.rawValue
        case .internalCreditNote:
            return InvoiceTypeCode.creditNote.rawValue
        default:
            return type.rawValue
        }
    }

    private func indented(_ block: String) -> String {
        block.split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0) }
            .joined(separator: "\n")
    }

    /// BT-11 : la syntaxe CII d'EN16931 ne porte que l'identifiant du projet, mais le XSD
    /// exige aussi un nom — rempli avec la valeur conventionnelle « Project reference ».
    private func projectReferenceXML(_ invoice: Invoice) -> String {
        guard let v = optionalValue(invoice.optionalFields, "ram:SpecifiedProcuringProject/ram:ID") else { return "" }
        return """
      <ram:SpecifiedProcuringProject>
        <ram:ID>\(escape(v))</ram:ID>
        <ram:Name>Project reference</ram:Name>
      </ram:SpecifiedProcuringProject>
"""
    }

    private func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
