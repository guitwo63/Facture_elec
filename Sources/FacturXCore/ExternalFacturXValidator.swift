import Foundation

// MARK: - Erreurs

public enum ExternalValidatorError: Error, LocalizedError {
    case pythonNotFound
    case scriptNotFound
    case timeout
    case invalidOutput(String)

    public var errorDescription: String? {
        switch self {
        case .pythonNotFound:
            return "Python 3 est introuvable. Installez-le avec : brew install python3"
        case .scriptNotFound:
            return "Le script de validation ref/validate_facturx.py est introuvable."
        case .timeout:
            return "La validation a expiré (délai dépassé)."
        case .invalidOutput(let raw):
            return "Réponse illisible du validateur : \(raw)"
        }
    }
}

// MARK: - Résultat de validation

public struct ExternalValidationResult {
    public let isValid: Bool
    public let errors: [String]
    public let warnings: [String]

    public init(isValid: Bool, errors: [String] = [], warnings: [String] = []) {
        self.isValid = isValid
        self.errors = errors
        self.warnings = warnings
    }
}

// MARK: - Validateur externe (factur-x Python)

/// Valide le XML CII généré par `CIIXMLGenerator` contre les XSD et Schematron
/// EN 16931 officiels via la librairie Python `factur-x`.
///
/// Prérequis :
///   1. Python 3 installé (`brew install python3`)
///   2. Librairie factur-x installée (`pip3 install factur-x lxml`)
///   3. Le script `ref/validate_facturx.py` présent à la racine du projet.
public struct ExternalFacturXValidator {

    /// Délai d'attente maximal en secondes.
    public var timeout: TimeInterval = 30

    public init() {}

    // MARK: - Méthode publique

    /// Valide un XML CII (Data) contre XSD + Schematron EN 16931.
    public func validate(xmlData: Data) throws -> ExternalValidationResult {
        let scriptPath = try resolveScriptPath()

        // 1. Écrire le XML dans un fichier temporaire
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("facturx_\(UUID().uuidString).xml")
        try xmlData.write(to: tmpURL)
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        // 2. Lancer le script Python
        let output = try runPython(scriptPath: scriptPath, xmlPath: tmpURL.path)

        // 3. Parser la sortie JSON
        return try parseOutput(output)
    }

    /// Valide une facture complète : génère le XML puis le valide.
    public func validate(invoice: Invoice) throws -> ExternalValidationResult {
        let xml = try CIIXMLGenerator().generate(invoice: invoice)
        return try validate(xmlData: xml)
    }

    // MARK: - Internes

    private func resolveScriptPath() throws -> String {
        // Cherche ref/validate_facturx.py dans le répertoire du package Swift.
        let candidates: [String] = [
            "ref/validate_facturx.py",
            "../ref/validate_facturx.py",
            FileManager.default.currentDirectoryPath + "/ref/validate_facturx.py",
        ]

        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        // Tente aussi via le chemin du bundle (si compilé en .app)
        if let bundlePath = Bundle.main.path(forResource: "validate_facturx", ofType: "py", inDirectory: "ref") {
            return bundlePath
        }

        throw ExternalValidatorError.scriptNotFound
    }

    private func runPython(scriptPath: String, xmlPath: String) throws -> String {
        let process = Process()

        // Trouve python3
        let pythonCandidates = ["/usr/bin/python3", "/usr/local/bin/python3", "/opt/homebrew/bin/python3"]
        var pythonURL: URL?
        for p in pythonCandidates {
            if FileManager.default.isExecutableFile(atPath: p) {
                pythonURL = URL(fileURLWithPath: p)
                break
            }
        }
        guard let py = pythonURL else {
            throw ExternalValidatorError.pythonNotFound
        }

        process.executableURL = py
        process.arguments = [scriptPath, xmlPath]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()

        // Timeout
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        if process.isRunning {
            process.terminate()
            throw ExternalValidatorError.timeout
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func parseOutput(_ output: String) throws -> ExternalValidationResult {
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ExternalValidatorError.invalidOutput(output)
        }

        let valid = json["valid"] as? Bool ?? false
        let errors = json["errors"] as? [String] ?? []
        let warnings = json["warnings"] as? [String] ?? []

        return ExternalValidationResult(isValid: valid, errors: errors, warnings: warnings)
    }
}
