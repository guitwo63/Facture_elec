import Foundation

public enum CIIXMLError: Error {
    case emptyLines
    case invalidAmount
}

public struct CIIXMLGenerator {
    public init() {}

    public func generate(invoice: Invoice) throws -> Data {
        guard !invoice.lines.isEmpty else { throw CIIXMLError.emptyLines }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)

        let issue = dateFormatter.string(from: invoice.issueDate)
        let due = dateFormatter.string(from: invoice.dueDate)

        let xmlLines = invoice.lines.enumerated().map { xmlLine($0.element, index: $0.offset) }.joined()

        let seller = xmlParty(invoice.seller, role: .seller)
        let buyer = xmlParty(invoice.buyer, role: .buyer)
        let agreement = """
        <ram:ApplicableHeaderTradeAgreement>
\(buyerReferenceXML(invoice))\(purchaseOrderXML(invoice))\(seller)\(buyer)
        </ram:ApplicableHeaderTradeAgreement>
"""
        let delivery = """
        <ram:ApplicableHeaderTradeDelivery>
          <ram:ActualDeliverySupplyChainEvent>
            <ram:OccurrenceDateTime>
              <udt:DateTimeString format="102">\(issue)</udt:DateTimeString>
            </ram:OccurrenceDateTime>
          </ram:ActualDeliverySupplyChainEvent>
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
    <ram:TypeCode>\(invoice.type.rawValue)</ram:TypeCode>
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
        let category = "S"
        let desc = line.description.map { """
            <ram:Description>\(escape($0))</ram:Description>
""" } ?? ""
        return """
        <ram:IncludedSupplyChainTradeLineItem>
          <ram:AssociatedDocumentLineDocument><ram:LineID>\(lineID)</ram:LineID></ram:AssociatedDocumentLineDocument>
          <ram:SpecifiedTradeProduct>
            <ram:Name>\(escape(line.name))</ram:Name>\(desc.isEmpty ? "" : desc)
          </ram:SpecifiedTradeProduct>
          <ram:SpecifiedLineTradeAgreement>
            <ram:NetPriceProductTradePrice>
              <ram:ChargeAmount>\(price)</ram:ChargeAmount>
            </ram:NetPriceProductTradePrice>
          </ram:SpecifiedLineTradeAgreement>
          <ram:SpecifiedLineTradeDelivery>
            <ram:BilledQuantity unitCode="\(line.unit)">\(qty)</ram:BilledQuantity>
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

        let endpointIDValue = party.endpointID?.trimmingCharacters(in: .whitespaces)
        let usingSirenFallback = (endpointIDValue?.isEmpty ?? true)
        let effectiveEndpointID = usingSirenFallback ? (party.siren ?? nil) : endpointIDValue
        let effectiveSchemeID = usingSirenFallback ? "0183" : party.endpointSchemeID
        let endpoint = effectiveEndpointID.map { id -> String in
            """
          <ram:ID schemeID="\(effectiveSchemeID)">\(escape(id))</ram:ID>
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
        <ram:\(tag)>\(endpoint.isEmpty ? "" : endpoint)
          <ram:Name>\(escape(party.name))</ram:Name>\(legalOrg.isEmpty ? "" : legalOrg)\(contact.isEmpty ? "" : contact)
          <ram:PostalTradeAddress>
            <ram:PostcodeCode>\(escape(party.postcode))</ram:PostcodeCode>
            <ram:LineOne>\(escape(party.street))</ram:LineOne>
            <ram:CityName>\(escape(party.city))</ram:CityName>
            <ram:CountryID>\(escape(party.country))</ram:CountryID>
          </ram:PostalTradeAddress>\(taxReg.isEmpty ? "" : taxReg)
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
            let category = invoice.vatCategory(for: item.rate)
            return """
      <ram:ApplicableTradeTax>
        <ram:CalculatedAmount>\(amount)</ram:CalculatedAmount>
        <ram:TypeCode>VAT</ram:TypeCode>
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
        let duePay = String(format: "%.2f", invoice.grandTotal)

        return """
    <ram:ApplicableHeaderTradeSettlement>
      <ram:InvoiceCurrencyCode>\(escape(invoice.currency))</ram:InvoiceCurrencyCode>
\(paymentMeans)\(tradeTax)\(paymentTerms)      <ram:SpecifiedTradeSettlementHeaderMonetarySummation>
        <ram:LineTotalAmount>\(lineTotal)</ram:LineTotalAmount>
        <ram:TaxBasisTotalAmount>\(taxBasis)</ram:TaxBasisTotalAmount>
        <ram:TaxTotalAmount currencyID="\(escape(invoice.currency))">\(taxTotal)</ram:TaxTotalAmount>
        <ram:GrandTotalAmount>\(grand)</ram:GrandTotalAmount>
        <ram:DuePayableAmount>\(duePay)</ram:DuePayableAmount>
      </ram:SpecifiedTradeSettlementHeaderMonetarySummation>
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

    private func formatRate(_ rate: Double) -> String {
        if rate == rate.rounded() {
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
