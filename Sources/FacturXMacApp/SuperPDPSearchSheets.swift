import SwiftUI
import FacturXCore

// MARK: - Extrait de FacturXMacApp.swift (découpage par domaine)

struct ChorusProSearchSheet: View {
    @EnvironmentObject var chorusSettings: ChorusProSettings
    @Environment(\.dismiss) private var dismiss
    @State private var query: String
    @State private var results: [ChorusProResult] = []
    @State private var searching = false
    @State private var error: String?
    let onPick: (InvoiceParty) -> Void

    init(initialQuery: String, onPick: @escaping (InvoiceParty) -> Void) {
        _query = State(initialValue: initialQuery)
        self.onPick = onPick
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Rechercher dans l'annuaire Chorus Pro").font(.headline)
                Spacer()
                Button {
                    if let url = URL(string: "https://facturation.chorus-pro.gouv.fr/annuaire/") {
                        NSWorkspace.shared.open(url)
                    }
                } label: { Label("Annuaire web", systemImage: "safari") }
                    .buttonStyle(.bordered)
                Button("Fermer") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(12)

            HStack {
                TextField("SIRET ou SIREN", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { runSearch() }
                Button { runSearch() } label: { Label("Rechercher", systemImage: "magnifyingglass") }
                    .buttonStyle(.borderedProminent)
                    .disabled(searching || query.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 12).padding(.bottom, 8)

            if !chorusSettings.credentials.isConfigured {
                Text("Identifiants PISTE non configurés. Ouvrez l'onglet Réglages.")
                    .font(.caption).foregroundStyle(.orange).padding(12)
            }

            if searching {
                HStack { Spacer(); ProgressView(); Spacer() }.padding()
            } else if let err = error {
                Text(err).font(.caption).foregroundStyle(.red).padding(12)
            } else {
                Divider()
                if results.isEmpty {
                    Text("Saisissez un SIRET et lancez la recherche.")
                        .foregroundStyle(.secondary).padding()
                } else {
                    List {
                        ForEach(results) { r in
                            Button {
                                onPick(r.toInvoiceParty())
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(r.denomination ?? "(sans dénomination)").font(.body.weight(.medium))
                                        Text(r.displaySubtitle).font(.caption).foregroundStyle(.secondary)
                                        if let addr = r.addressLine, !addr.isEmpty {
                                            Text(addr).font(.caption2).foregroundStyle(.tertiary)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(minWidth: 520, minHeight: 460)
    }

    private func runSearch() {
        guard chorusSettings.credentials.isConfigured else {
            error = "Identifiants PISTE non configurés."
            return
        }
        searching = true
        error = nil
        results = []
        Task {
            do {
                let r = try await ChorusProService().searchRecipient(
                    siretOrSiren: query,
                    credentials: chorusSettings.credentials
                )
                results = r
                if r.isEmpty { error = "Aucun résultat." }
            } catch let e as ChorusProError {
                self.error = e.errorDescription
            } catch let err {
                self.error = err.localizedDescription
            }
            searching = false
        }
    }
}

struct SuperPDPEventsSheet: View {
    let events: [SuperPDPInvoiceEvent]
    let loading: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Historique SUPER PDP").font(.headline)
                Spacer()
                Button("Fermer") { dismiss() }
            }.padding(12)
            Divider()
            if loading {
                HStack { Spacer(); ProgressView(); Spacer() }.padding(40)
            } else if events.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock.badge.questionmark").font(.largeTitle).foregroundStyle(.secondary)
                    Text("Aucun événement retourné.").font(.caption).foregroundStyle(.secondary)
                }.padding(40)
            } else {
                List {
                    ForEach(events) { ev in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Image(systemName: ev.semanticSystemImage)
                                    .foregroundStyle(Color(hex: ev.semanticHexColor))
                                Text(ev.detailLabel).font(.body.bold())
                                Spacer()
                                if let d = ev.createdAt {
                                    Text(d, format: .dateTime.day().month().year().hour().minute())
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            HStack(spacing: 6) {
                                Image(systemName: ev.direction == .sent ? "arrow.up.circle" : "arrow.down.circle")
                                Text(ev.direction == .sent ? "Envoyé" : "Reçu")
                                Text("·")
                                Text(ev.statusCode).font(.system(.caption2, design: .monospaced))
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            if let n = ev.notes, !n.isEmpty {
                                Text(n).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
        }.frame(minWidth: 480, minHeight: 360)
    }
}

struct SuperPDPValidationSheet: View {
    let report: SuperPDPValidationReport
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Rapport de validation SUPER PDP").font(.headline)
                Spacer()
                Button("Fermer") { dismiss() }
            }.padding(12)
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: report.isValid ? "checkmark.seal.fill" : "xmark.octagon.fill")
                        .foregroundStyle(report.isValid ? .green : .red).font(.title2)
                    Text(report.isValid ? "Facture valide" : "Facture non valide").font(.title3.bold())
                }
                if !report.errors.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Erreurs (\(report.errors.count))").font(.subheadline.bold()).foregroundStyle(.red)
                        ForEach(Array(report.errorEntries.enumerated()), id: \.offset) { _, e in
                            Text("• \(report.displayText(for: e))").font(.caption).foregroundStyle(.red)
                        }
                    }
                }
                if !report.warnings.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Avertissements (\(report.warnings.count))").font(.subheadline.bold()).foregroundStyle(.orange)
                        ForEach(Array(report.warningEntries.enumerated()), id: \.offset) { _, w in
                            Text("• \(report.displayText(for: w))").font(.caption).foregroundStyle(.orange)
                        }
                    }
                }
                if report.isValid && report.errors.isEmpty && report.warnings.isEmpty {
                    Text("Aucune erreur ni avertissement. La facture est conforme.").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(16)
            Spacer()
        }.frame(minWidth: 480, minHeight: 360)
    }
}

struct SuperPDPFrenchDirectorySheet: View {
    @EnvironmentObject var superPDPSettings: SuperPDPSettings
    @Environment(\.dismiss) private var dismiss
    let onPick: (InvoiceParty) -> Void
    @State private var query = ""
    @State private var results: [SuperPDPFrenchCompany] = []
    @State private var searching = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Annuaire français des entreprises").font(.headline)
                Spacer()
                Button("Fermer") { dismiss() }
            }.padding(12)
            Divider()
            HStack {
                TextField("SIREN, SIRET ou raison sociale…", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { runSearch() }
                Button { runSearch() } label: { Label("Rechercher", systemImage: "magnifyingglass") }
                    .disabled(searching || query.trimmingCharacters(in: .whitespaces).isEmpty)
            }.padding(12)
            if !superPDPSettings.credentials.isConfigured {
                Text("Identifiants SUPER PDP non configurés. Ouvrez l'onglet Réglages.")
                    .font(.caption).foregroundStyle(.orange).padding(12)
            }
            if searching {
                HStack { Spacer(); ProgressView(); Spacer() }.padding()
            } else if let err = error {
                Text(err).font(.caption).foregroundStyle(.red).padding(12)
            } else {
                List(results) { c in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(c.name ?? "(sans nom)").font(.body.bold())
                        Text(c.displaySubtitle).font(.caption).foregroundStyle(.secondary)
                        if let addr = c.addressLine, !addr.isEmpty {
                            Text([addr, c.postcode, c.city].compactMap { $0 }.joined(separator: " ")).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onPick(c.toInvoiceParty())
                        dismiss()
                    }
                }
            }
        }.frame(minWidth: 520, minHeight: 420).onAppear { if results.isEmpty { query = "" } }
    }

    private func runSearch() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        searching = true
        error = nil
        Task {
            do {
                let service = SuperPDPService()
                results = try await service.searchFrenchDirectory(sirenOrName: q, credentials: superPDPSettings.credentials)
            } catch let e as SuperPDPError {
                error = e.localizedDescription
                results = []
            } catch let err {
                error = "\(err)"
                results = []
            }
            searching = false
        }
    }
}

struct SuperPDPSearchSheet: View {
    @EnvironmentObject var superPDPSettings: SuperPDPSettings
    @Environment(\.dismiss) private var dismiss
    @State private var query: String
    @State private var results: [SuperPDPDirectoryEntry] = []
    @State private var searching = false
    @State private var error: String?
    let onPick: (InvoiceParty) -> Void
    init(initialQuery: String, onPick: @escaping (InvoiceParty) -> Void) {
        _query = State(initialValue: initialQuery)
        self.onPick = onPick
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Rechercher un destinataire (SUPER PDP)").font(.headline)
                Spacer()
                Button { dismiss() } label: { Text("Fermer") }.keyboardShortcut(.cancelAction)
            }.padding(12)
            HStack {
                TextField("SIRET ou SIREN", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { runSearch() }
                Button { runSearch() } label: { Label("Rechercher", systemImage: "magnifyingglass") }
                    .buttonStyle(.borderedProminent)
                    .disabled(searching || query.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 12).padding(.bottom, 8)
            if !superPDPSettings.credentials.isConfigured {
                Text("Identifiants SUPER PDP non configurés. Ouvrez l'onglet Réglages.")
                    .font(.caption).foregroundStyle(.orange).padding(12)
            }
            if searching {
                HStack { Spacer(); ProgressView(); Spacer() }.padding()
            } else if let err = error {
                Text(err).font(.caption).foregroundStyle(.red).padding(12)
            } else {
                Divider()
                if results.isEmpty {
                    Text("Saisissez un SIREN/SIRET et lancez la recherche.")
                        .foregroundStyle(.secondary).padding()
                } else {
                    List {
                        ForEach(results) { r in
                            Button {
                                onPick(r.toInvoiceParty())
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(r.name ?? "(sans dénomination)").font(.body.weight(.medium))
                                        Text(r.displaySubtitle).font(.caption).foregroundStyle(.secondary)
                                        if let addr = r.addressLine, !addr.isEmpty {
                                            Text(addr).font(.caption2).foregroundStyle(.tertiary)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(minWidth: 520, minHeight: 460)
    }
    private func runSearch() {
        guard superPDPSettings.credentials.isConfigured else {
            error = "Identifiants SUPER PDP non configurés."
            return
        }
        searching = true
        error = nil
        results = []
        Task {
            do {
                let r = try await SuperPDPService().searchRecipient(
                    siretOrSiren: query,
                    credentials: superPDPSettings.credentials
                )
                results = Self.deduplicated(r)
                if r.isEmpty { error = "Aucun résultat." }
            } catch let e as SuperPDPError {
                self.error = e.errorDescription
            } catch let err {
                self.error = err.localizedDescription
            }
            searching = false
        }
    }

    /// SUPER PDP peut renvoyer plusieurs enregistrements techniques distincts
    /// (facturation/e-reporting/commandes…) pour la même société, avec des
    /// champs affichés strictement identiques — on ne garde qu'une occurrence
    /// par combinaison nom/SIREN/SIRET/adresse pour éviter des lignes qui
    /// semblent être de purs doublons.
    private static func deduplicated(_ entries: [SuperPDPDirectoryEntry]) -> [SuperPDPDirectoryEntry] {
        var seen = Set<String>()
        var unique: [SuperPDPDirectoryEntry] = []
        for e in entries {
            let key = [e.name ?? "", e.siren ?? "", e.siret ?? "", e.addressLine ?? "", e.city ?? ""].joined(separator: "|")
            if seen.insert(key).inserted {
                unique.append(e)
            }
        }
        return unique
    }
}
