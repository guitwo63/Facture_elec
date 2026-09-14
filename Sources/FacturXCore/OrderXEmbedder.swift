import Foundation

public enum OrderXEmbedError: Error {
    case invalidPDF
    case invalidXML
    case malformedPDF
}

/// Embarque le XML Order-X (CIO) dans un PDF/A-3 sous le nom `order-x.xml`
/// avec /AFRelationship /Alternative, plus les métadonnées XMP Order-X
/// (fx:DocumentType = ORDER, namespace urn:factur-x:pdfa:CrossIndustryDocument:1p0#).
public struct OrderXEmbedder {
    public init() {}

    public func embed(pdfData: Data, xml: Data, order: SalesOrder) throws -> Data {
        guard !pdfData.isEmpty else { throw OrderXEmbedError.invalidPDF }
        guard !xml.isEmpty else { throw OrderXEmbedError.invalidXML }

        let parser = PDFParser(data: pdfData)
        let info = try parser.parse()

        var pdf = pdfData
        var newObjects: [PDFObject] = []
        let base = info.maxObjectNumber

        let xmlStream = PDFObject(
            num: base,
            gen: 0,
            content: makeEmbeddedFileStream(xml: xml)
        )
        newObjects.append(xmlStream)

        let filespec = PDFObject(
            num: base + 1,
            gen: 0,
            content: makeFilespec(filename: "order-x.xml", embeddedRef: "\(base) 0 R", desc: "Order-X order XML")
        )
        newObjects.append(filespec)

        let names = PDFObject(
            num: base + 2,
            gen: 0,
            content: makeEmbeddedFileNames(filename: "order-x.xml", filespecRef: "\(base + 1) 0 R")
        )
        newObjects.append(names)

        let xmpStream = PDFObject(
            num: base + 3,
            gen: 0,
            content: makeMetadataStream(xmp: makeXMP(order: order))
        )
        newObjects.append(xmpStream)

        let originalRootDict = info.rootDictionary
        let newRootDict = augmentRootDictionary(
            original: originalRootDict,
            namesRef: "\(base + 2) 0 R",
            filespecRef: "\(base + 1) 0 R",
            metadataRef: "\(base + 3) 0 R"
        )
        let newRoot = PDFObject(
            num: base + 4,
            gen: 0,
            content: newRootDict.data(using: .isoLatin1) ?? Data()
        )
        newObjects.append(newRoot)

        var appended = Data()
        appended.append(0x0A)
        var offsets: [Int: Int] = [:]
        for obj in newObjects {
            let pos = pdf.count + appended.count
            offsets[obj.num] = pos
            appended.append("\(obj.num) \(obj.gen) obj\n".data(using: .ascii)!)
            appended.append(obj.content)
            appended.append("\nendobj\n".data(using: .ascii)!)
        }
        pdf.append(appended)

        let xrefStart = pdf.count
        let totalCount = base + newObjects.count
        var xref = "xref\n0 \(totalCount)\n"
        xref += String(format: "%010d 65535 f \r\n", 0)
        for num in 1..<base {
            let off = info.offset(for: num)
            xref += String(format: "%010d 00000 n \r\n", off)
        }
        for obj in newObjects {
            xref += String(format: "%010d 00000 n \r\n", offsets[obj.num]!)
        }

        var trailer = "trailer\n"
        trailer += "<< /Size \(totalCount) /Root \(newRoot.num) 0 R"
        if let infoRef = info.infoRef {
            trailer += " /Info \(infoRef)"
        }
        let id = makeID()
        trailer += " /ID [ <\(id)> <\(id)> ] >>\n"
        trailer += "startxref\n\(xrefStart)\n%%EOF"

        pdf.append(xref.data(using: .ascii)!)
        pdf.append(trailer.data(using: .ascii)!)
        return pdf
    }

    private func makeEmbeddedFileStream(xml: Data) -> Data {
        var d = "<< /Type /EmbeddedFile /Subtype /text#2fxml /Length \(xml.count) >>\nstream\n".data(using: .ascii)!
        d.append(xml)
        d.append("\nendstream".data(using: .ascii)!)
        return d
    }

    private func makeFilespec(filename: String, embeddedRef: String, desc: String) -> Data {
        let escapedName = filename.replacingOccurrences(of: "(", with: #"\("#).replacingOccurrences(of: ")", with: #"\)"#)
        let escapedDesc = desc.replacingOccurrences(of: "(", with: #"\("#).replacingOccurrences(of: ")", with: #"\)"#)
        let hexName = filename.map { String(format: "%02x", $0.asciiValue ?? 0) }.joined()
        let body = "<< /Type /Filespec /F (\(escapedName)) /UF <\(hexName)> /AFRelationship /Alternative /Desc (\(escapedDesc)) /EF << /F \(embeddedRef) /UF \(embeddedRef) >> >>"
        return body.data(using: .ascii)!
    }

    private func makeEmbeddedFileNames(filename: String, filespecRef: String) -> Data {
        let hexName = filename.map { String(format: "%02x", $0.asciiValue ?? 0) }.joined()
        let body = "<< /EmbeddedFiles << /Names [ <\(hexName)> \(filespecRef) ] >> >>"
        return body.data(using: .ascii)!
    }

    private func makeMetadataStream(xmp: String) -> Data {
        let xmpData = xmp.data(using: .utf8) ?? Data()
        var d = "<< /Type /Metadata /Subtype /XML /Length \(xmpData.count) >>\nstream\n".data(using: .ascii)!
        d.append(xmpData)
        d.append("\nendstream".data(using: .ascii)!)
        return d
    }

    private func augmentRootDictionary(
        original: String,
        namesRef: String,
        filespecRef: String,
        metadataRef: String
    ) -> String {
        var dict = original
        if let r = dict.range(of: "<<") {
            dict.insert(contentsOf: " /AF [\(filespecRef)]", at: r.upperBound)
        }
        if let r = dict.range(of: "<<") {
            dict.insert(contentsOf: " /Names \(namesRef)", at: r.upperBound)
        }
        if let r = dict.range(of: "<<") {
            dict.insert(contentsOf: " /Metadata \(metadataRef)", at: r.upperBound)
        }
        return dict
    }

    private func makeXMP(order: SalesOrder) -> String {
        let created = isoNow()
        let buyerName = escapeXML(order.buyer.name)
        let number = escapeXML(order.number)
        let date = isoDate(order.issueDate)
        let title = "\(buyerName): Order \(number)"
        let desc = "Order \(number) dated \(date) issued by \(buyerName)"
        let conformance = order.profile.conformanceLevel

        return """
<?xpacket begin="\u{FEFF}" id="W5M0MpCehiHzreSzNTczkc9d"?>
<x:xmpmeta xmlns:x="adobe:ns:meta/">
  <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
    <rdf:Description xmlns:pdfaid="http://www.aiim.org/pdfa/ns/id/" rdf:about="">
      <pdfaid:part>3</pdfaid:part>
      <pdfaid:conformance>B</pdfaid:conformance>
    </rdf:Description>
    <rdf:Description xmlns:dc="http://purl.org/dc/elements/1.1/" rdf:about="">
      <dc:title>
        <rdf:Alt>
          <rdf:li xml:lang="x-default">\(title)</rdf:li>
        </rdf:Alt>
      </dc:title>
      <dc:creator>
        <rdf:Seq>
          <rdf:li>\(buyerName)</rdf:li>
        </rdf:Seq>
      </dc:creator>
      <dc:description>
        <rdf:Alt>
          <rdf:li xml:lang="x-default">\(desc)</rdf:li>
        </rdf:Alt>
      </dc:description>
    </rdf:Description>
    <rdf:Description xmlns:pdf="http://ns.adobe.com/pdf/1.3/" rdf:about="">
      <pdf:Producer>FacturXMacApp</pdf:Producer>
    </rdf:Description>
    <rdf:Description xmlns:xmp="http://ns.adobe.com/xap/1.0/" rdf:about="">
      <xmp:CreatorTool>FacturXMacApp</xmp:CreatorTool>
      <xmp:CreateDate>\(created)</xmp:CreateDate>
      <xmp:ModifyDate>\(created)</xmp:ModifyDate>
    </rdf:Description>
    <rdf:Description xmlns:pdfaExtension="http://www.aiim.org/pdfa/ns/extension/" xmlns:pdfaSchema="http://www.aiim.org/pdfa/ns/schema#" xmlns:pdfaProperty="http://www.aiim.org/pdfa/ns/property#" rdf:about="">
      <pdfaExtension:schemas>
        <rdf:Bag>
          <rdf:li rdf:parseType="Resource">
            <pdfaSchema:schema>Factur-X PDFA Extension Schema</pdfaSchema:schema>
            <pdfaSchema:namespaceURI>urn:factur-x:pdfa:CrossIndustryDocument:1p0#</pdfaSchema:namespaceURI>
            <pdfaSchema:prefix>fx</pdfaSchema:prefix>
            <pdfaSchema:property>
              <rdf:Seq>
                <rdf:li rdf:parseType="Resource">
                  <pdfaProperty:name>DocumentFileName</pdfaProperty:name>
                  <pdfaProperty:valueType>Text</pdfaProperty:valueType>
                  <pdfaProperty:category>external</pdfaProperty:category>
                  <pdfaProperty:description>The name of the embedded XML document</pdfaProperty:description>
                </rdf:li>
                <rdf:li rdf:parseType="Resource">
                  <pdfaProperty:name>DocumentType</pdfaProperty:name>
                  <pdfaProperty:valueType>Text</pdfaProperty:valueType>
                  <pdfaProperty:category>external</pdfaProperty:category>
                  <pdfaProperty:description>The type of the hybrid document in capital letters, e.g. INVOICE or ORDER</pdfaProperty:description>
                </rdf:li>
                <rdf:li rdf:parseType="Resource">
                  <pdfaProperty:name>Version</pdfaProperty:name>
                  <pdfaProperty:valueType>Text</pdfaProperty:valueType>
                  <pdfaProperty:category>external</pdfaProperty:category>
                  <pdfaProperty:description>The actual version of the standard applying to the embedded XML document</pdfaProperty:description>
                </rdf:li>
                <rdf:li rdf:parseType="Resource">
                  <pdfaProperty:name>ConformanceLevel</pdfaProperty:name>
                  <pdfaProperty:valueType>Text</pdfaProperty:valueType>
                  <pdfaProperty:category>external</pdfaProperty:category>
                  <pdfaProperty:description>The conformance level of the embedded XML document</pdfaProperty:description>
                </rdf:li>
              </rdf:Seq>
            </pdfaSchema:property>
          </rdf:li>
        </rdf:Bag>
      </pdfaExtension:schemas>
    </rdf:Description>
    <rdf:Description xmlns:fx="urn:factur-x:pdfa:CrossIndustryDocument:1p0#" rdf:about="">
      <fx:DocumentType>ORDER</fx:DocumentType>
      <fx:DocumentFileName>order-x.xml</fx:DocumentFileName>
      <fx:Version>1.0</fx:Version>
      <fx:ConformanceLevel>\(conformance)</fx:ConformanceLevel>
    </rdf:Description>
  </rdf:RDF>
</x:xmpmeta>
<?xpacket end="w"?>
"""
    }

    private func makeID() -> String {
        let bytes = (0..<16).map { _ in UInt8.random(in: 0...255) }
        return bytes.map { String(format: "%02X", $0) }.joined()
    }

    private func isoNow() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: Date())
    }

    private func isoDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f.string(from: d)
    }

    private func escapeXML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
