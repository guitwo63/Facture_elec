import AppKit
import SwiftUI
import XCTest
import FacturXCore
@testable import FacturXMacApp

/// `lockable(_:)` verrouille une section au clavier comme à la souris.
///
/// Jusqu'au 2026-09-24, le modificateur ne faisait que `allowsHitTesting(false)` : la souris
/// était arrêtée, pas le clavier. Tab amenait le focus dans un champ d'une section verrouillée,
/// et la frappe le modifiait, y compris sur une facture émise, déposée ou payée. Un simple Tab
/// à travers la section réécrivait déjà ses champs, sans aucune frappe.
///
/// Les vues tournent dans une vraie fenêtre AppKit, hors écran. Les touches passent par la file
/// d'événements, comme dans l'app : `NSApp.currentEvent` est la touche en cours de traitement.
/// La frappe est insérée dans l'éditeur de champ qui a le focus, s'il y en a un.
@MainActor
final class LockableKeyboardTests: XCTestCase {
    private var window: LockableTestWindow!

    // MARK: - Section verrouillée d'une vue minimale

    func testTabJumpsOverLockedSections() {
        let model = LockableTestModel()
        show(LockableTestView(model: model))
        focus(textField(showing: "avant"))

        pressTab()

        XCTAssertIdentical(focusedControl, textField(showing: "après"), "le focus enjambe les deux sections verrouillées")
        type("x")
        XCTAssertEqual(model.after, "x")
        XCTAssertEqual(model.lockedValues, LockableTestModel().lockedValues)
        XCTAssertEqual(model.lockedWrites, [], "le focus n'a fait qu'effleurer les champs verrouillés : rien à réécrire")
    }

    func testShiftTabJumpsOverLockedSectionsBackward() {
        let model = LockableTestModel()
        show(LockableTestView(model: model))
        focus(textField(showing: "après"))

        pressShiftTab()

        XCTAssertIdentical(focusedControl, textField(showing: "avant"))
        type("x")
        XCTAssertEqual(model.lockedValues, LockableTestModel().lockedValues)
        XCTAssertEqual(model.lockedWrites, [])
    }

    /// Focus donné autrement que par Tab (par programme, par l'accessibilité) : il est retiré.
    func testLockedSectionRefusesFocusGivenByProgram() {
        let model = LockableTestModel()
        show(LockableTestView(model: model))

        focus(textField(showing: "verrouillé"))
        XCTAssertNil(focusedControl, "aucun champ n'a le focus")
        type("x")

        focus(datePicker())
        XCTAssertNil(focusedControl)
        pressArrowUp()

        XCTAssertEqual(model.lockedValues, LockableTestModel().lockedValues)
        XCTAssertEqual(model.lockedWrites, [])
    }

    /// Facture passée à un statut verrouillant pendant une saisie : la saisie s'arrête.
    func testLockingDuringTypingEndsTheEdit() {
        let model = LockableTestModel()
        model.locked = false
        show(LockableTestView(model: model))
        focus(textField(showing: "verrouillé"))
        type("a")
        XCTAssertEqual(model.lockedText, "a")

        model.locked = true
        spin(until: { focusedControl == nil })

        XCTAssertNil(focusedControl)
        type("b")
        XCTAssertEqual(model.lockedText, "a")
    }

    /// Déverrouillée (« Modifier quand même »…), la section reprend Tab et la frappe.
    func testUnlockingGivesTabAndTypingBack() {
        let model = LockableTestModel()
        show(LockableTestView(model: model))
        focus(textField(showing: "avant"))
        pressTab()
        XCTAssertIdentical(focusedControl, textField(showing: "après"))

        model.locked = false
        spin()
        focus(textField(showing: "avant"))
        pressTab()

        XCTAssertIdentical(focusedControl, textField(showing: "verrouillé"))
        type("x")
        XCTAssertEqual(model.lockedText, "x")
        focus(datePicker())
        XCTAssertIdentical(focusedControl, datePicker())
        pressArrowUp()
        XCTAssertNotEqual(model.lockedDate, LockableTestModel().lockedDate)
    }

    // MARK: - Éditeur de facture réel

    /// Facture émise : ni Tab ni un focus donné à chacun de ses champs ne la modifient au clavier.
    func testIssuedInvoiceEditorRefusesTheKeyboard() throws {
        try assertIsolatedPersistence()
        let box = LockableInvoiceBox(invoice: Self.sampleInvoice(status: .issued))
        show(LockableInvoiceEditorHost(box: box, stores: LockableAppStores()))
        let search = try XCTUnwrap(textField(showing: LockableInvoiceEditorHost.searchText))
        let original = box.invoice

        focus(search)
        pressTab()
        XCTAssertIdentical(focusedControl, search, "Tab enjambe toute la facture verrouillée")
        pressShiftTab()
        XCTAssertIdentical(focusedControl, search)

        let fields = allViews(of: NSTextField.self).filter { $0.isEditable && $0 !== search }
        XCTAssertTrue(fields.contains { $0.stringValue == original.number }, "le champ Numéro est bien rendu")
        for field in fields {
            focus(field)
            XCTAssertNil(focusedControl, "champ « \(field.stringValue) »")
            type("9")
        }
        let datePickers = allViews(of: NSDatePicker.self)
        XCTAssertFalse(datePickers.isEmpty)
        for picker in datePickers {
            focus(picker)
            XCTAssertNil(focusedControl)
            pressArrowUp()
        }

        XCTAssertEqual(box.invoice, original)
        XCTAssertEqual(box.writes, 0, "chaque écriture est un upsert de la facture, journalisé « invoice_updated »")
    }

    /// Brouillon : l'éditeur réel reste modifiable au clavier.
    func testDraftInvoiceEditorTakesTheKeyboard() throws {
        try assertIsolatedPersistence()
        let box = LockableInvoiceBox(invoice: Self.sampleInvoice(status: .draft))
        show(LockableInvoiceEditorHost(box: box, stores: LockableAppStores()))
        focus(textField(showing: LockableInvoiceEditorHost.searchText))

        pressTab()

        XCTAssertIdentical(focusedControl, textField(showing: box.invoice.number), "Tab entre dans le champ Numéro")
        type("F-2026-0043")
        XCTAssertEqual(box.invoice.number, "F-2026-0043")
    }

    /// Brouillon émis pendant la saisie de son numéro (bouton de statut, dépôt PDP…).
    func testInvoiceLockedWhileTypingStopsTakingKeys() throws {
        try assertIsolatedPersistence()
        let box = LockableInvoiceBox(invoice: Self.sampleInvoice(status: .draft))
        show(LockableInvoiceEditorHost(box: box, stores: LockableAppStores()))
        focus(textField(showing: box.invoice.number))
        type("F-2026-0043")
        XCTAssertEqual(box.invoice.number, "F-2026-0043")

        box.invoice.status = .issued
        spin(until: { focusedControl == nil })

        XCTAssertNil(focusedControl)
        type("9")
        XCTAssertEqual(box.invoice.number, "F-2026-0043")
    }

    // MARK: - Outils

    private static func sampleInvoice(status: InvoiceStatus) -> Invoice {
        Invoice(
            number: "F-2026-0042",
            status: status,
            issueDate: Date(timeIntervalSince1970: 1_790_000_000),
            dueDate: Date(timeIntervalSince1970: 1_792_592_000),
            seller: InvoiceParty(name: "Arverneo", street: "1 rue du Test", postcode: "63000", city: "Clermont-Ferrand", siren: "123456789"),
            buyer: InvoiceParty(name: "Client Essai", street: "2 avenue de l'Essai", postcode: "75001", city: "Paris", siren: "987654321"),
            lines: [InvoiceLine(name: "Prestation de conseil", quantity: 2, unitPrice: 450)],
            paymentTerms: "Paiement à 30 jours"
        )
    }

    /// Les stores de l'éditeur réel écrivent dans la suite UserDefaults et le service du Trousseau
    /// du processus de tests, jamais dans ceux de l'app.
    private func assertIsolatedPersistence() throws {
        XCTAssertFalse(AppPersistence.defaults === UserDefaults.standard)
        XCTAssertTrue(AppPersistence.keychainService.hasPrefix("fr.arverneo.facturxmacapp.tests."))
        guard AppPersistence.defaults !== UserDefaults.standard else {
            throw XCTSkip("persistance non isolée : l'éditeur réel n'est pas instancié")
        }
    }

    private func show<Content: View>(_ view: Content) {
        _ = NSApplication.shared
        let window = LockableTestWindow(
            contentRect: NSRect(x: -5000, y: -5000, width: 1000, height: 1400),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = NSHostingView(rootView: view)
        window.orderFront(nil)
        self.window = window
        addTeardownBlock { [unowned self] in
            forgetLastKey()
            window.close()
        }
        spin(0.5)
    }

    private func spin(_ seconds: TimeInterval = 0.1) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    /// Le verrouillage retire le focus juste après la mise à jour SwiftUI, qui peut dépasser
    /// 0,1 s sur l'éditeur de facture complet.
    private func spin(until condition: () -> Bool, timeout: TimeInterval = 2) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline { spin(0.05) }
    }

    /// Focus donné par programme, hors de toute frappe.
    private func focus(_ view: NSView?) {
        guard let view else { return }
        forgetLastKey()
        window.makeFirstResponder(view)
        spin()
    }

    /// `NSApp.currentEvent` reste la dernière touche lue tant qu'aucun autre événement n'est
    /// lu. Dans l'app, la boucle d'événements en lit sans cesse ; ici, un Tab d'une étape
    /// précédente ferait passer le focus suivant pour un Tab.
    private func forgetLastKey() {
        let event = NSEvent.otherEvent(
            with: .applicationDefined, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, subtype: 0, data1: 0, data2: 0
        )!
        NSApp.postEvent(event, atStart: true)
        _ = NSApp.nextEvent(matching: .applicationDefined, until: .distantPast, inMode: .default, dequeue: true)
    }

    /// Le contrôle qui a le focus. En saisie, le premier répondeur est l'éditeur de champ de la
    /// fenêtre, dont le délégué est le champ. `nil` : la fenêtre elle-même, aucun contrôle.
    private var focusedControl: NSView? {
        if let editor = window.firstResponder as? NSText, editor.isFieldEditor {
            return editor.delegate as? NSView
        }
        return window.firstResponder as? NSView
    }

    private func type(_ text: String) {
        guard let editor = window.firstResponder as? NSTextView else { return }
        editor.insertText(text, replacementRange: editor.selectedRange())
        spin()
    }

    private func pressTab() { press(keyCode: 48, characters: "\t") }
    private func pressShiftTab() { press(keyCode: 48, characters: "\u{19}", modifiers: .shift) }
    private func pressArrowUp() {
        press(keyCode: 126, characters: String(Character(UnicodeScalar(NSUpArrowFunctionKey)!)), modifiers: [.numericPad, .function])
    }

    private func press(keyCode: UInt16, characters: String, modifiers: NSEvent.ModifierFlags = []) {
        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers,
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: false, keyCode: keyCode
        )!
        NSApp.postEvent(event, atStart: true)
        guard let dequeued = NSApp.nextEvent(matching: .keyDown, until: .distantPast, inMode: .default, dequeue: true) else {
            return XCTFail("touche perdue dans la file d'événements")
        }
        window.sendEvent(dequeued)
        spin()
    }

    private func allViews<T: NSView>(of type: T.Type) -> [T] {
        var found: [T] = []
        var pending = window.contentView.map { [$0] } ?? []
        while let view = pending.popLast() {
            if let match = view as? T { found.append(match) }
            pending.append(contentsOf: view.subviews)
        }
        return found
    }

    private func textField(showing text: String, file: StaticString = #filePath, line: UInt = #line) -> NSTextField? {
        let field = allViews(of: NSTextField.self).first { $0.isEditable && $0.stringValue == text }
        if field == nil { XCTFail("aucun champ n'affiche « \(text) »", file: file, line: line) }
        return field
    }

    private func datePicker(file: StaticString = #filePath, line: UInt = #line) -> NSDatePicker? {
        let picker = allViews(of: NSDatePicker.self).first
        if picker == nil { XCTFail("aucun sélecteur de date", file: file, line: line) }
        return picker
    }
}

private final class LockableTestWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Vue minimale : un champ, deux sections verrouillables d'affilée, un champ

private final class LockableTestModel: ObservableObject {
    @Published var locked = true
    @Published var before = "avant"
    @Published var lockedText = "verrouillé"
    @Published var lockedAmount = 12.5
    @Published var lockedDate = Date(timeIntervalSince1970: 1_790_000_000)
    @Published var lockedNote = "note"
    @Published var after = "après"
    /// Écritures des champs des sections, tapées ou non.
    var lockedWrites: [String] = []

    var lockedValues: [String] {
        [lockedText, "\(lockedAmount)", "\(lockedDate.timeIntervalSince1970)", lockedNote]
    }
}

private struct LockableTestView: View {
    @ObservedObject var model: LockableTestModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Avant", text: $model.before)
            GroupBox("Section 1") {
                VStack(alignment: .leading) {
                    TextField("Texte", text: logged(\.lockedText, "texte"))
                    TextField("Montant", value: logged(\.lockedAmount, "montant"), format: .decimalInput)
                }
                .padding(8)
            }
            .lockable(model.locked)
            GroupBox("Section 2") {
                VStack(alignment: .leading) {
                    DatePicker("Date", selection: logged(\.lockedDate, "date"), displayedComponents: .date)
                    TextField("Note", text: logged(\.lockedNote, "note"))
                }
                .padding(8)
            }
            .lockable(model.locked)
            TextField("Après", text: $model.after)
        }
        .padding(20)
        .frame(width: 420, alignment: .topLeading)
    }

    private func logged<Value>(_ keyPath: ReferenceWritableKeyPath<LockableTestModel, Value>, _ name: String) -> Binding<Value> {
        Binding(
            get: { model[keyPath: keyPath] },
            set: {
                model.lockedWrites.append(name)
                model[keyPath: keyPath] = $0
            }
        )
    }
}

// MARK: - Éditeur de facture réel

/// La facture de l'éditeur. Dans l'app, chaque écriture du binding est un `InvoiceStore.upsert`.
private final class LockableInvoiceBox: ObservableObject {
    @Published var invoice: Invoice
    var writes = 0

    init(invoice: Invoice) { self.invoice = invoice }
}

/// Stores neufs, dans la persistance isolée du processus de tests (voir `AppPersistence`).
private struct LockableAppStores {
    let invoices = InvoiceStore()
    let auth = AuthStore()
    let superPDP = SuperPDPSettings()
    let invoiceStatuses = InvoiceStatusStore()
    let smtp = SMTPSettings()
    let emailTemplates = EmailTemplateStore()
    let paymentTerms = PaymentTermsPresetStore()
    let auditActionLabels = AuditActionLabelStore()
    let directory = PartyDirectory()
    let tags = TagStore()
    let kindColors = KindColorStore()
}

/// L'éditeur réel, sous un champ qui tient lieu de la recherche de la liste des factures :
/// dans l'app, Tab passe de cette recherche au premier champ de la facture.
private struct LockableInvoiceEditorHost: View {
    static let searchText = "recherche"

    @ObservedObject var box: LockableInvoiceBox
    let stores: LockableAppStores
    @State private var search = Self.searchText

    var body: some View {
        VStack(spacing: 0) {
            TextField("Rechercher", text: $search)
            InvoiceEditorView(invoice: Binding(
                get: { box.invoice },
                set: {
                    box.writes += 1
                    box.invoice = $0
                }
            ))
        }
        .environmentObject(stores.invoices)
        .environmentObject(stores.auth)
        .environmentObject(stores.superPDP)
        .environmentObject(stores.invoiceStatuses)
        .environmentObject(stores.smtp)
        .environmentObject(stores.emailTemplates)
        .environmentObject(stores.paymentTerms)
        .environmentObject(stores.auditActionLabels)
        .environmentObject(stores.directory)
        .environmentObject(stores.tags)
        .environmentObject(stores.kindColors)
    }
}
