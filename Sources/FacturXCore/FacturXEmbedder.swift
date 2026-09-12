import Foundation

public enum FacturXEmbedError: Error {
    case invalidPDF
    case invalidXML
    case malformedPDF
}

/// Génère une facture Factur-X : un PDF contenant le CII XML embarqué sous
/// "factur-x.xml" avec /AFRelationship /Alternative, plus les métadonnées XMP
/// Factur-X (fx:DocumentType, fx:DocumentFileName, fx:Version,
/// fx:ConformanceLevel) et l'identifiant PDF/A-3 dans le XMP.
///
/// Note de conformité : le CII XML généré est validé contre le schéma XSD
/// officiel EN 16931 (voir FacturXCoreTests / la référence Python fournie).
/// Le conteneur PDF embarque le XML et le XMP conformément à Factur-X ;
/// la certification PDF/A-3 stricte (output intent ICC) dépend d'un profil
/// ICC sRGB — voir README pour la validation veraPDF/Mustang.
public struct FacturXEmbedder {
    public init() {}

    public func embed(pdfData: Data, xml: Data, invoice: Invoice) throws -> Data {
        guard !pdfData.isEmpty else { throw FacturXEmbedError.invalidPDF }
        guard !xml.isEmpty else { throw FacturXEmbedError.invalidXML }

        let parser = PDFParser(data: pdfData)
        let info = try parser.parse()

        var pdf = pdfData
        var newObjects: [PDFObject] = []
        let base = info.maxObjectNumber + 1

        let xmlStream = PDFObject(
            num: base,
            gen: 0,
            content: makeEmbeddedFileStream(xml: xml)
        )
        newObjects.append(xmlStream)

        let filespec = PDFObject(
            num: base + 1,
            gen: 0,
            content: makeFilespec(filename: "factur-x.xml", embeddedRef: "\(base) 0 R", desc: "Factur-X invoice XML")
        )
        newObjects.append(filespec)

        let names = PDFObject(
            num: base + 2,
            gen: 0,
            content: makeEmbeddedFilesNames(filename: "factur-x.xml", filespecRef: "\(base + 1) 0 R")
        )
        newObjects.append(names)

        let xmpStream = PDFObject(
            num: base + 3,
            gen: 0,
            content: makeMetadataStream(xmp: makeXMP(invoice: invoice))
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
            content: newRootDict.data(using: .ascii)!
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

    private func makeEmbeddedFilesNames(filename: String, filespecRef: String) -> Data {
        let hexName = filename.map { String(format: "%02x", $0.asciiValue ?? 0) }.joined()
        let body = "<< /Names << /EmbeddedFiles << /Names [ <\(hexName)> \(filespecRef) ] >> >> >>"
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

    private func makeXMP(invoice: Invoice) -> String {
        let created = isoNow()
        let sellerName = escapeXML(invoice.seller.name)
        let number = escapeXML(invoice.number)
        let date = isoDate(invoice.issueDate)
        let title = "\(sellerName): Invoice \(number)"
        let desc = "Invoice \(number) dated \(date) issued by \(sellerName)"
        let conformance = invoice.profile.conformanceLevel

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
          <rdf:li>\(sellerName)</rdf:li>
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
            <pdfaSchema:namespaceURI>urn:factur-x:pdfa:CrossIndustryDocument:invoice:1p0#</pdfaSchema:namespaceURI>
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
    <rdf:Description xmlns:fx="urn:factur-x:pdfa:CrossIndustryDocument:invoice:1p0#" rdf:about="">
      <fx:DocumentType>INVOICE</fx:DocumentType>
      <fx:DocumentFileName>factur-x.xml</fx:DocumentFileName>
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

struct PDFObject {
    let num: Int
    let gen: Int
    let content: Data
}

struct PDFParser {
    let data: Data

    struct Info {
        let maxObjectNumber: Int
        let rootRef: String
        let infoRef: String?
        let rootDictionary: String
        let offsets: [Int: Int]

        func offset(for num: Int) -> Int {
            return offsets[num] ?? 0
        }
    }

    func parse() throws -> Info {
        let startxref = findStartXref()
        guard startxref > 0 else { throw FacturXEmbedError.malformedPDF }
        let chunk = string(from: startxref, length: 4000)
        let size = intValue(after: "/Size", in: chunk) ?? 1
        let rootRef = textValue(after: "/Root", in: chunk) ?? "1 0 R"
        let infoRef = textValue(after: "/Info", in: chunk)
        let offsets = parseXrefTable(startxref: startxref)
        let rootNum = Int(rootRef.split(separator: " ").first ?? "1") ?? 1
        let rootDict = extractDictionary(at: offsets[rootNum] ?? 0)
        return Info(
            maxObjectNumber: size,
            rootRef: rootRef,
            infoRef: infoRef,
            rootDictionary: rootDict,
            offsets: offsets
        )
    }

    private func findStartXref() -> Int {
        let tail = data.suffix(1024)
        let s = String(data: tail, encoding: .isoLatin1) ?? ""
        guard let range = s.range(of: "startxref", options: .backwards) else { return 0 }
        let after = s[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine = after.split(whereSeparator: { $0.isWhitespace }).first.map(String.init)
        return firstLine.flatMap { Int($0) } ?? 0
    }

    private func parseXrefTable(startxref: Int) -> [Int: Int] {
        var offsets: [Int: Int] = [:]
        let chunk = string(from: startxref, length: 60000)
        guard let xrefRange = chunk.range(of: "xref") else { return offsets }
        let table = chunk[xrefRange.upperBound...]
        let beforeTrailer = table.split(separator: "t", maxSplits: 1, omittingEmptySubsequences: false)
        let raw = table.prefix(upTo: table.range(of: "trailer")?.lowerBound ?? table.endIndex)
        let lines = raw.split(whereSeparator: { $0.isNewline })
        guard let first = lines.first else { return offsets }
        let header = first.split(whereSeparator: { $0.isWhitespace })
        guard header.count >= 2, let startObj = Int(header[0]) else { return offsets }
        var current = startObj
        for line in lines.dropFirst() {
            let parts = line.split(whereSeparator: { $0.isWhitespace })
            if parts.count == 2, let s = Int(parts[0]), let count = Int(parts[1]) {
                current = s
                _ = count
                continue
            }
            if parts.count >= 3 {
                if let off = Int(parts[0]) {
                    offsets[current] = off
                    current += 1
                }
            }
        }
        _ = beforeTrailer
        return offsets
    }

    private func extractDictionary(at offset: Int) -> String {
        let chunk = string(from: offset, length: 4000)
        guard let start = chunk.range(of: "<<"), let end = chunk.range(of: ">>", options: .backwards) else {
            return "<< >>"
        }
        return String(chunk[start.lowerBound..<end.upperBound])
    }

    private func intValue(after key: String, in s: String) -> Int? {
        guard let range = s.range(of: key) else { return nil }
        let after = s[range.upperBound...].trimmingCharacters(in: .whitespaces)
        return after.split(whereSeparator: { $0.isWhitespace }).first.flatMap { Int($0) }
    }

    private func textValue(after key: String, in s: String) -> String? {
        guard let range = s.range(of: key) else { return nil }
        let after = s[range.upperBound...].trimmingCharacters(in: .whitespaces)
        return after.split(whereSeparator: { $0.isWhitespace }).first.map(String.init)
    }

    private func string(from offset: Int, length: Int) -> String {
        let end = min(data.count, offset + length)
        guard offset < end else { return "" }
        return String(data: data[offset..<end], encoding: .isoLatin1) ?? ""
    }
}
