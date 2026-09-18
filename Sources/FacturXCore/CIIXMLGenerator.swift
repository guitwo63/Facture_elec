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
        let projectRef = projectReferenceXML(invoice)
        let agreement = """
        <ram:ApplicableHeaderTradeAgreement>
\(buyerReferenceXML(invoice))\(seller)\(buyer)\(purchaseOrderXML(invoice))\(contractXML(invoice))\(tenderXML(invoice))\(projectRef.isEmpty ? "" : projectRef)
        </ram:ApplicableHeaderTradeAgreement>
"""
        let delivery = """
        <ram:ApplicableHeaderTradeDelivery>
          <ram:ActualDeliverySupplyChainEvent>
            <ram:OccurrenceDateTime>
              <udt:DateTimeString format="102">\(issue)</udt:DateTimeString>
            </ram:OccurrenceDateTime>
          </ram:ActualDeliverySupplyChainEvent>
\(receivingAdviceXML(invoice))\(despatchAdviceXML(invoice))
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
        let globalID = line.optionalFields.first(where: { $0.tagName == "ram:GlobalID" && !$0.value.trimmingCharacters(in: .whitespaces).isEmpty })
        let globalIDXML = globalID.map { f in
            let v = escape(f.value.trimmingCharacters(in: .whitespaces))
            return """
            <ram:GlobalID schemeID="0160">\(v)</ram:GlobalID>
"""
        } ?? ""
        let orderField = line.optionalFields.first(where: { $0.tagName == "ram:BuyerOrderReferencedDocument/ram:IssuerAssignedID" && !$0.value.trimmingCharacters(in: .whitespaces).isEmpty })
        let contractField = line.optionalFields.first(where: { $0.tagName == "ram:ContractReferencedDocument/ram:IssuerAssignedID" && !$0.value.trimmingCharacters(in: .whitespaces).isEmpty })
        var lineRefs = ""
        if let of = orderField {
            lineRefs += """
            <ram:BuyerOrderReferencedDocument>
              <ram:IssuerAssignedID>\(escape(of.value.trimmingCharacters(in: .whitespaces)))</ram:IssuerAssignedID>
            </ram:BuyerOrderReferencedDocument>
"""
        }
        if let cf = contractField {
            lineRefs += """
            <ram:ContractReferencedDocument>
              <ram:IssuerAssignedID>\(escape(cf.value.trimmingCharacters(in: .whitespaces)))</ram:IssuerAssignedID>
            </ram:ContractReferencedDocument>
"""
        }
        return """
        <ram:IncludedSupplyChainTradeLineItem>
          <ram:AssociatedDocumentLineDocument><ram:LineID>\(lineID)</ram:LineID></ram:AssociatedDocumentLineDocument>
          <ram:SpecifiedTradeProduct>\(globalIDXML.isEmpty ? "" : globalIDXML)
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
    private func tenderXML(_ invoice: Invoice) -> String {
        guard let ref = invoice.tenderRef, !ref.isEmpty else { return "" }
        return """
      <ram:TendererReferencedDocument>
        <ram:IssuerAssignedID>\(escape(ref))</ram:IssuerAssignedID>
      </ram:TendererReferencedDocument>
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
        let prepaidLine = invoice.prepaidAmount > 0
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
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(secondsFromGMT: 0)
        let dateStr: String
        if let d = invoice.precedingInvoiceDate {
            dateStr = fmt.string(from: d)
        } else {
            dateStr = fmt.string(from: invoice.issueDate)
        }
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

    private func projectReferenceXML(_ invoice: Invoice) -> String {
        guard let field = invoice.optionalFields.first(where: { $0.tagName == "ram:SpecifiedProcuringProject/ram:ID" && !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }) else { return "" }
        let v = escape(field.value.trimmingCharacters(in: .whitespaces))
        return """
      <ram:SpecifiedProcuringProject>
        <ram:ID>\(v)</ram:ID>
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
