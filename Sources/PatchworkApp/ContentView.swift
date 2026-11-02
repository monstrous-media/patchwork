#if os(macOS)
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CoreMIDI
import PatchworkCore
import PatchworkMIDI

/// Sidebar entries: the synth definition's editor pages, then the app's own pages.
enum Page: Hashable {
    case editor(String)      // EditorPage.id from ActiveSynth.pages
    case drumKits            // M1 extra (Global data)
    case library
    case log

    static let first: Page = .editor(ActiveSynth.pages.first?.id ?? "")

    var title: String {
        switch self {
        case .editor(let id): return ActiveSynth.pages.first { $0.id == id }?.title ?? id
        case .drumKits: return "Drum kits"
        case .library: return "Library"
        case .log: return "MIDI log"
        }
    }
    var icon: String {
        switch self {
        case .editor(let id): return ActiveSynth.pages.first { $0.id == id }?.systemImage ?? "slider.horizontal.3"
        case .drumKits: return "square.grid.3x3"
        case .library: return "books.vertical"
        case .log: return "list.bullet.rectangle"
        }
    }
    var isEditing: Bool {
        switch self {
        case .editor, .drumKits: return true
        case .library, .log: return false
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.undoManager) private var undoManager
    @State private var page: Page? = Page.first
    @State private var mutateAmount = 0.2
    @AppStorage("appearance") private var appearance: Appearance = .dark

    var body: some View {
        NavigationSplitView {
            List(selection: $page) {
                Section {
                    ForEach(ActiveSynth.pages) { ep in
                        let p = Page.editor(ep.id)
                        Label(p.title, systemImage: p.icon).tag(p)
                    }
                } header: { GroupHeader(text: "Editor") }
                Section {
                    Label(Page.drumKits.title, systemImage: Page.drumKits.icon).tag(Page.drumKits)
                } header: { GroupHeader(text: "Instrument") }
                Section {
                    Label(Page.library.title, systemImage: Page.library.icon).tag(Page.library)
                } header: { GroupHeader(text: "Library") }
                Section {
                    Label(Page.log.title, systemImage: Page.log.icon).tag(Page.log)
                } header: { GroupHeader(text: "Diagnostics") }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.sidebar)
            .navigationSplitViewColumnWidth(min: 160, ideal: 190)
            .safeAreaInset(edge: .bottom) { generatorPanel }
        } detail: {
            VStack(spacing: 0) {
                MIDIBar()
                Rectangle().fill(Theme.line).frame(height: 1)
                detail
                if showsPlayBar {
                    Rectangle().fill(Theme.line).frame(height: 1)
                    PlayBar()
                }
                Rectangle().fill(Theme.line).frame(height: 1)
                statusBar
            }
            .background(Theme.surface)
        }
        .frame(minWidth: 880, minHeight: 600)
        .tint(Theme.accent)
        .onChange(of: appearance) { $0.apply() }
        .toolbar { toolbarItems }
        .alert("Problem", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
            appearance.apply()
            model.undoManager = undoManager
        }
        .onChange(of: undoManager) { um in model.undoManager = um }
    }

    /// The audition strip appears wherever you're shaping sound, not on the library/log pages.
    var showsPlayBar: Bool { (page ?? Page.first).isEditing }

    @ViewBuilder var detail: some View {
        switch page ?? Page.first {
        case .editor(let id):
            if let ep = ActiveSynth.pages.first(where: { $0.id == id }) {
                EditorPageView(page: ep)
            } else {
                Text("No such page").foregroundStyle(.secondary)
            }
        case .drumKits:
            DrumKitsView()
        case .library:
            LibraryView()
        case .log:
            LogView()
        }
    }

    var generatorPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            HStack {
                GroupHeader(text: "Generate")
                Spacer()
                HelpButton(section: "generators")
            }
            Button { model.randomise() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "die.face.\(model.diceFace)")
                        .rotationEffect(.degrees(Double(model.rollTurns) * 360))
                        .animation(.easeInOut(duration: 0.55), value: model.rollTurns)
                        .scaleEffect(model.rolling ? 1.3 : 1)
                        .animation(.spring(response: 0.3, dampingFraction: 0.5), value: model.rolling)
                    Text("Randomise")
                }
            }
            .disabled(model.rolling)
            .help("Roll a completely new program into the editor (edit buffer only — nothing is written to the M1)")
            HStack {
                Button { model.mutate(amount: mutateAmount) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "wand.and.stars")
                            .scaleEffect(model.mutating ? 1.35 : 1)
                            .rotationEffect(.degrees(model.mutating ? -20 : 0))
                            .animation(.spring(response: 0.25, dampingFraction: 0.45), value: model.mutating)
                        Text("Mutate")
                    }
                }
                .help("Nudge about \(Int(mutateAmount * 100))% of the parameters by a small amount; changed rows glow")
                Slider(value: $mutateAmount, in: 0.05...0.8).frame(width: 70)
                    .help("Mutation strength: \(Int(mutateAmount * 100))% of parameters")
            }
            Button { model.load(M1Program(), announce: "Init program", thenSend: model.autoSend) } label: { Label("Init", systemImage: "arrow.counterclockwise") }
                .help("Start from a neutral program: single A.Piano, filter open, Hall reverb (⌘N)")
        }
        .padding(10)
        .buttonStyle(.link)
        .background(Theme.sidebar)
    }

    /// Guide section for the current page (the ? button).
    var helpSection: String {
        switch page ?? Page.first {
        case .editor: return "editing"
        case .drumKits: return "drum-kits"
        case .library: return "library-banks-and-slots"
        case .log: return "midi-log"
        }
    }

    @ToolbarContentBuilder var toolbarItems: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { openFile() } label: { Label("Open", systemImage: "folder") }
                .help("Open a patch (.json) or a SysEx dump (.syx) into the editor")
            Button { saveFile() } label: { Label("Save", systemImage: "square.and.arrow.down") }
                .help("Save the editor patch as .json (readable) or .syx (raw SysEx)")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { model.requestProgram() } label: { Label("Request", systemImage: "arrow.down.circle") }
                .labelStyle(.titleAndIcon)
                .help("Request: pull the program the M1 is playing into the editor (⌘R)")
            Button { model.sendProgram() } label: { Label("Send", systemImage: "arrow.up.circle") }
                .labelStyle(.titleAndIcon)
                .buttonStyle(.borderedProminent)
                .help("Send: push the editor patch to the M1's edit buffer — temporary until written (⌘S)")
            HStack(spacing: 6) {
                Button { model.writeToSlot() } label: { Label("Write", systemImage: "internaldrive") }
                    .labelStyle(.titleAndIcon)
                    .help("Write: store the editor patch in the M1's slot chosen here (⌘W). Needs Memory Protect off.")
                Picker("Slot", selection: $model.writeSlot) {
                    ForEach(0..<Bank.slotCount, id: \.self) { Text(Bank.slotLabel($0)).tag($0) }
                }
                .labelsHidden()
                .frame(width: 76)
                .help("M1 slot the Write button targets (I00–I99)")
                Toggle("mirror to bank", isOn: $model.mirrorWritesToBank).toggleStyle(.checkbox)
                    .help("After the M1 confirms a Write, also store the program in that slot of the selected local bank so the bank keeps matching the synth")
            }
            HelpButton(section: helpSection)
        }
    }

    var statusBar: some View {
        HStack(spacing: 10) {
            Text(model.status).font(Theme.monoCaption).foregroundStyle(Theme.muted).lineLimit(1)
            Spacer()
            if model.dirty {
                if model.autoSend { StatusChip(text: "edited · auto-sent", tone: .good) }
                else { StatusChip(text: "edited · not sent", tone: .warn) }
            } else {
                StatusChip(text: "as received")
            }
            Text("“\(model.program.name)”").font(Theme.value).foregroundStyle(Theme.accent)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Theme.raised)
    }

    // MARK: Files

    func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.json, UTType(filenameExtension: "syx") ?? .data]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { model.importFile(url) }
    }

    func saveFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.json, UTType(filenameExtension: "syx") ?? .data]
        panel.nameFieldStringValue = model.program.name.isEmpty ? "patch.json" : model.program.name + ".json"
        panel.canSelectHiddenExtension = true
        if panel.runModal() == .OK, let url = panel.url { model.exportFile(url) }
    }
}

struct MIDIBar: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            Picker("In", selection: $model.selectedSource) {
                Text("—").tag(MIDIEndpointRef(0))
                ForEach(model.sources) { e in Text(e.name).tag(e.id) }
            }
            .frame(maxWidth: 260)
            .help("MIDI input: the interface port the M1's MIDI OUT is cabled to (needed for Request, Fetch, Verify and acknowledgements)")
            Picker("Out", selection: $model.selectedDestination) {
                Text("—").tag(MIDIEndpointRef(0))
                ForEach(model.destinations) { e in Text(e.name).tag(e.id) }
            }
            .frame(maxWidth: 260)
            .help("MIDI output: the interface port cabled to the M1's MIDI IN")
            Picker("Ch", selection: $model.channel) {
                ForEach(1...16, id: \.self) { Text("\($0)").tag($0) }
            }
            .frame(width: 80)
            .help("MIDI channel — must match the M1's Global channel (GLOBAL → 5 → Channel)")
            Toggle("Auto-send on edit", isOn: $model.autoSend).toggleStyle(.switch).fixedSize()
                .help("Send every edit to the M1's edit buffer as you make it (about 80 ms after the control stops moving)")
            Spacer()
            LinkIndicator()
            Button { model.refreshEndpoints() } label: { Image(systemName: "arrow.clockwise") }
                .help("Rescan MIDI devices after plugging something in")
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Theme.surface)
    }
}

/// Heartbeat: is anything arriving on In? The M1 sends active sensing continuously while powered and
/// cabled, so this is green when the return path works and amber when the app is talking to nobody.
struct LinkIndicator: View {
    @EnvironmentObject var model: AppModel

    private var state: (color: Color, text: String, help: String) {
        if model.selectedSource == 0 {
            return (Theme.faint, "No In", "No MIDI input selected — replies and acknowledgements from the M1 can't be seen")
        }
        if model.inputHeard {
            return (Theme.accent, "M1 heard", "Bytes are arriving on In (the M1's active sensing or replies), so the return cable works")
        }
        return (Theme.amber, "M1 silent", "Nothing has arrived on In for 2 s. A powered, cabled M1 sends active sensing continuously — check power, the M1 MIDI OUT → interface IN cable, and the In port above")
    }

    var body: some View {
        let s = state
        HStack(spacing: 6) {
            Circle().fill(s.color).frame(width: 8, height: 8)
                .shadow(color: model.inputHeard ? s.color.opacity(0.9) : .clear, radius: 4)
            Text(s.text).font(Theme.monoCaption).foregroundStyle(Theme.muted)
        }
        .help(s.help)
    }
}

/// Renders one of the synth definition's editor pages: rows of parameter sections, optionally with
/// an envelope sketch under a section.
struct EditorPageView: View {
    @EnvironmentObject var model: AppModel
    let page: EditorPage

    /// Cards flow into as many columns as fit (one on a narrow window, two or three on a wide one),
    /// in the definition's order, instead of fixed pairs that squeeze each other.
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 400, maximum: 640), spacing: 12, alignment: .top)],
                      alignment: .leading, spacing: 12) {
                ForEach(Array(page.rows.flatMap { $0 }.enumerated()), id: \.offset) { _, block in
                    blockView(block)
                }
            }
            .padding(16)
        }
        .background(Theme.surface)
    }

    @ViewBuilder
    func blockView(_ block: PageBlock) -> some View {
        switch block {
        case .section(let s):
            SectionBox(section: s)
        case .sectionWithEnvelope(let s, let e):
            SectionBox(section: s, envelope: e)
        }
    }
}

struct LibraryView: View {
    @EnvironmentObject var model: AppModel
    @State private var morphT = 0.5
    @State private var confirmRestore = false
    @State private var verifyAfterRestore = true
    @State private var confirmWriteSlot: Int?
    @State private var confirmDeleteBank = false

    var body: some View {
        HStack(spacing: 0) {
            bankList.frame(width: 230)
            Divider()
            if let i = model.selectedBankIndex {
                bankDetail(index: i)
            } else {
                VStack(spacing: 10) {
                    Text("No banks yet").font(.title3).foregroundStyle(.secondary)
                    Text("Fetch the M1's internal bank (and export it as .syx straight away — it's your only undo for Write), import a .syx, or start an empty bank.")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420)
                    Button("Fetch bank from M1") { model.fetchBankFromM1() }.disabled(model.transfer != nil)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: Bank list (left)

    var bankList: some View {
        VStack(spacing: 0) {
            List(selection: $model.selectedBankID) {
                ForEach(model.banks) { b in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(b.name)
                            Text("\(b.filledCount)/100").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .tag(Optional(b.id))
                }
            }
            Divider()
            HStack(spacing: 10) {
                Button { model.newEmptyBank() } label: { Image(systemName: "plus") }.help("New empty local bank")
                Button { importBank() } label: { Image(systemName: "folder") }.help("Import a .syx file as a new bank (more than 100 programs become several banks)")
                Button { model.duplicateSelectedBank() } label: { Image(systemName: "plus.square.on.square") }
                    .disabled(model.selectedBank == nil).help("Duplicate the selected bank")
                Button { confirmDeleteBank = true } label: { Image(systemName: "minus") }
                    .disabled(model.selectedBank == nil).help("Delete the selected local bank (asks first; the M1 is not touched)")
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(6)
            .confirmationDialog("Delete bank “\(model.selectedBank?.name ?? "")” from this Mac?", isPresented: $confirmDeleteBank) {
                Button("Delete", role: .destructive) { if let id = model.selectedBankID { model.deleteBank(id) } }
            } message: { Text("This only removes the local copy; the M1 is not touched.") }
        }
    }

    // MARK: Bank detail (right)

    func bankDetail(index i: Int) -> some View {
        VStack(spacing: 0) {
            // Bank-level controls
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField("Bank name", text: $model.banks[i].name).textFieldStyle(.roundedBorder).frame(width: 260)
                        .help("Rename this local bank")
                    Text("\(model.banks[i].filledCount) of 100 slots").foregroundStyle(.secondary)
                    Spacer()
                    Text("Morph amount").font(.caption).foregroundStyle(.secondary)
                    Slider(value: $morphT, in: 0...1).frame(width: 100)
                        .help("How far a row's ⤳ button moves the editor patch toward that slot's program")
                    Text("\(Int(morphT * 100))%").font(.caption).monospacedDigit().foregroundStyle(.secondary).frame(width: 34)
                }
                HStack(spacing: 10) {
                    Button("Fetch bank from M1") { model.fetchBankFromM1() }
                        .help("Fetch: read all 100 of the M1's slots into a NEW dated bank (about 20 s). Existing banks are never overwritten.")
                    Button("Verify against M1") { model.verifyBank(model.banks[i]) }
                        .help("Verify: re-read this bank's filled slots from the M1 and report any that differ")
                    Button("Restore to M1…") { confirmRestore = true }
                        .buttonStyle(.borderedProminent)
                        .help("Restore: write every filled slot of this bank into the M1, one slot at a time, each acknowledged. Asks first. Needs Memory Protect off.")
                    Toggle("verify after", isOn: $verifyAfterRestore).toggleStyle(.checkbox)
                        .help("After a Restore, read every written slot back and compare")
                    Button("Export .syx…") { exportBank(model.banks[i]) }
                        .help("Save this bank as a standard SysEx file (program dumps in slot order) — your backup")
                    Spacer()
                }
                .disabled(model.transfer != nil)
                if let t = model.transfer {
                    HStack {
                        ProgressView(value: t.progress).frame(width: 220)
                        Text("\(t.done)/\(t.total)").monospacedDigit()
                        Text(t.label).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        Button("Cancel") { model.cancelTransfer() }
                    }
                }
            }
            .padding(10)
            .confirmationDialog("Overwrite the M1's internal programs with “\(model.banks[i].name)”?", isPresented: $confirmRestore) {
                Button("Restore \(model.banks[i].filledCount) slots", role: .destructive) {
                    model.restoreBankToM1(model.banks[i], verify: verifyAfterRestore)
                }
            } message: {
                Text("Each filled slot replaces the program stored in that slot on the M1. Memory Protect must be OFF. Make sure you have exported the current M1 bank first.")
            }
            Divider()

            // Slot rows
            slotHeader
            List {
                ForEach(0..<Bank.slotCount, id: \.self) { n in
                    slotRow(bankIndex: i, slot: n)
                }
            }
            .confirmationDialog("Write to the M1's slot \(Bank.slotLabel(confirmWriteSlot ?? 0))?", isPresented: Binding(get: { confirmWriteSlot != nil }, set: { if !$0 { confirmWriteSlot = nil } })) {
                Button("Write", role: .destructive) {
                    if let n = confirmWriteSlot, let p = model.banks[i].programs[n] {
                        model.writeProgram(p, toM1Slot: n, verifyAgainstBank: model.banks[i].id)
                    }
                    confirmWriteSlot = nil
                }
            } message: {
                Text("This replaces whatever the M1 currently stores in that slot (Memory Protect must be OFF). The slot is read back afterwards to verify.")
            }
        }
    }

    /// Column headings so the icon buttons on every row are self-explaining.
    var slotHeader: some View {
        HStack(spacing: 10) {
            Text("Slot").frame(width: 34, alignment: .leading)
            Text("Name").frame(width: 110, alignment: .leading)
            Text("Summary")
            Spacer()
            Text("Load").frame(width: 40)
            Text("Morph").frame(width: 44)
            Text("Store").frame(width: 36)
            Text("Write").frame(width: 36)
            Text("Save").frame(width: 36)
            Text("Clear").frame(width: 36)
        }
        .lineLimit(1).fixedSize(horizontal: false, vertical: true)
        .font(Theme.groupHeader).foregroundStyle(Theme.faint)
        .padding(.horizontal, 18).padding(.vertical, 5)
        .background(Theme.raised)
        .help("Load → editor · Morph: editor toward this · Store: editor → this local slot · Write: this → the M1's slot · Save: to a file · Clear: empty the local slot")
    }

    @ViewBuilder
    func slotRow(bankIndex i: Int, slot n: Int) -> some View {
        let p = model.banks[i].programs[n]
        HStack(spacing: 10) {
            Text(Bank.slotLabel(n)).font(Theme.value).foregroundStyle(Theme.faint).frame(width: 34, alignment: .leading)
            if let p = p {
                Text(p.name).frame(width: 110, alignment: .leading)
                Text(ActiveSynth.summary(p)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Button("Load") { model.load(p, announce: "Loaded \(Bank.slotLabel(n)) “\(p.name)” from “\(model.banks[i].name)”", thenSend: model.autoSend) }
                    .frame(width: 40)
                    .help("Load “\(p.name)” into the editor (and send it to the M1 if Auto-send is on)")
                Button { model.morphToward(p, t: morphT) } label: { Text("⤳") }
                    .frame(width: 44)
                    .help("Morph the editor patch \(Int(morphT * 100))% toward “\(p.name)” (set the amount with the slider above)")
                Button { model.storeCurrent(inSlot: n) } label: { Image(systemName: "arrow.down.to.line") }
                    .frame(width: 36)
                    .help("Store: replace this local slot with the editor patch — the M1 is not touched (⌘Z undoes)")
                Button { confirmWriteSlot = n } label: { Image(systemName: "internaldrive") }
                    .frame(width: 36)
                    .disabled(model.transfer != nil)
                    .help("Write “\(p.name)” into the M1's slot \(Bank.slotLabel(n)) (asks first; verified afterwards)")
                Button { exportProgram(p, suggested: Bank.slotLabel(n) + "-" + p.name) } label: { Image(systemName: "square.and.arrow.down") }
                    .frame(width: 36)
                    .help("Save “\(p.name)” as a .syx or .json file")
                Button { model.clearSlot(n) } label: { Image(systemName: "xmark.circle") }
                    .frame(width: 36)
                    .help("Clear: empty this local slot — the M1 is not touched")
            } else {
                Text("— empty —").foregroundStyle(.tertiary)
                Spacer()
                Spacer().frame(width: 94)
                Button { model.storeCurrent(inSlot: n) } label: { Image(systemName: "arrow.down.to.line") }
                    .frame(width: 36)
                    .help("Store the editor patch in this empty slot (local only)")
                Spacer().frame(width: 128)
            }
        }
        .buttonStyle(.borderless)
    }

    // MARK: Panels

    func importBank() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "syx") ?? .data]
        if panel.runModal() == .OK, let url = panel.url { model.importBank(from: url) }
    }

    func exportBank(_ bank: Bank) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "syx") ?? .data]
        panel.nameFieldStringValue = bank.name.replacingOccurrences(of: ":", with: "-") + ".syx"
        if panel.runModal() == .OK, let url = panel.url { model.exportBank(bank, to: url) }
    }

    func exportProgram(_ p: M1Program, suggested: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "syx") ?? .data, UTType.json]
        panel.nameFieldStringValue = suggested + ".syx"
        if panel.runModal() == .OK, let url = panel.url { model.exportProgram(p, to: url) }
    }
}

struct LogView: View {
    @EnvironmentObject var model: AppModel
    static let fmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; return f }()

    /// Timestamps faint, outgoing neutral, acknowledgements green, incoming blue, warnings amber, refusals red.
    static func tone(_ e: LogEntry) -> Color {
        let t = e.text
        if e.isError {
            let refusal = t.localizedCaseInsensitiveContains("error") || t.localizedCaseInsensitiveContains("failed") || t.localizedCaseInsensitiveContains("protect")
            return refusal ? Theme.red : Theme.amber
        }
        if t.hasPrefix("Received") || t.hasPrefix("Hearing") || t.hasPrefix("Panel edit") { return Theme.blue }
        if t.hasPrefix("M1:") || t.contains("completed") || t.contains("verified") || t.contains("acknowledged") { return Theme.wellAccent }
        return Theme.wellText
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Edit a parameter on the M1's front panel to see its parameter-change (0x41) page/position here.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Clear") { model.log.removeAll() }
            }
            .padding(10)
            Divider()
            ScrollViewReader { proxy in
                List(model.log) { entry in
                    HStack(alignment: .top) {
                        Text(LogView.fmt.string(from: entry.time)).foregroundStyle(Theme.faint)
                        Text(entry.text).foregroundStyle(LogView.tone(entry)).textSelection(.enabled)
                    }
                    .font(Theme.mono)
                    .listRowBackground(Theme.well)
                    .id(entry.id)
                }
                .scrollContentBackground(.hidden)
                .background(Theme.well)
                .onChange(of: model.log.count) { _ in
                    if let last = model.log.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }
}
#endif
