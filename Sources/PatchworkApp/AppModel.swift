#if os(macOS)
import Foundation
import SwiftUI
import CoreMIDI
import PatchworkCore
import PatchworkMIDI

struct LogEntry: Identifiable {
    let id = UUID()
    let time = Date()
    let text: String
    let isError: Bool
}

/// All mutation happens on the main queue (CoreMIDI callbacks are hopped over with DispatchQueue.main).
final class AppModel: ObservableObject {

    // Editor state
    @Published var program = M1Program() {
        didSet { if !suppressAutoSend { scheduleAutoSend() } }
    }
    @Published var dirty = false

    // MIDI
    @Published var sources: [MIDIEngine.Endpoint] = []
    @Published var destinations: [MIDIEngine.Endpoint] = []
    @Published var selectedSource: MIDIEndpointRef = 0 { didSet { connectSource() } }
    @Published var selectedDestination: MIDIEndpointRef = 0
    @Published var channel: Int = 1              // 1–16 as shown on the M1
    @Published var autoSend = true
    @Published var writeSlot = 0
    @Published var mirrorWritesToBank = true   // after a toolbar Write, also store the program in the selected bank's slot
    @Published var status = "Starting…"
    @Published var lastAck: String?

    // Link health. A Send only proves the bytes reached the interface, so the app also watches In:
    // the M1 transmits active sensing (FE) about three times a second whenever it is powered and
    // cabled, and acknowledges every dump with load completed / load error.
    @Published var inputHeard = false            // anything received on In within the last 2 s
    private var lastHeard: Date?
    private var linkTimer: Timer?
    private var awaitingAck: DispatchWorkItem?
    private var lastSendWasQuiet = false
    private var lastNoAckWarning: Date?

    // Banks (local, persisted) and transfers to/from the M1 — see Banks.swift
    @Published var banks: [Bank] = BankStore.load() { didSet { BankStore.save(banks) } }
    @Published var selectedBankID: UUID?
    @Published var transfer: TransferState?
    var transferGeneration = 0

    // Global data (settings + 4 drum kits) — see DrumKitsView
    @Published var globalData: M1GlobalData? {
        didSet {
            // Edits to an already-loaded Global block are auto-sent like program edits; receiving one is not.
            if !suppressGlobalAutoSend, oldValue != nil, globalData != nil, globalData != oldValue { scheduleGlobalSend() }
        }
    }
    @Published var selectedKit = 0            // 0–3
    @Published var globalDirty = false
    @Published var globalAutoSend = false      // kits have no edit buffer on the M1, so default to explicit Send
    private var globalAsReceived: M1GlobalData?
    private var pendingGlobalSend: DispatchWorkItem?
    private var suppressGlobalAutoSend = false
    private var pendingGlobalRequest = false

    // Undo (⌘Z) for local changes: library slots/banks and kit edits. Set by ContentView from the environment.
    weak var undoManager: UndoManager?

    /// Record an undoable change of the whole bank list (simple and safe: banks are small).
    func registerBanksUndo(_ before: [Bank], _ actionName: String) {
        undoManager?.registerUndo(withTarget: self) { m in
            let now = m.banks
            m.banks = before
            m.registerBanksUndo(now, actionName)
        }
        undoManager?.setActionName(actionName)
    }

    /// Record an undoable change of the Global data (kits).
    func registerGlobalUndo(_ before: M1GlobalData?, _ actionName: String) {
        undoManager?.registerUndo(withTarget: self) { m in
            let now = m.globalData
            m.suppressGlobalAutoSend = true
            m.globalData = before
            m.suppressGlobalAutoSend = false
            m.globalDirty = before != m.globalAsReceived
            m.registerGlobalUndo(now, actionName)
        }
        undoManager?.setActionName(actionName)
    }

    // Log
    @Published var log: [LogEntry] = []
    @Published var errorMessage: String?

    // Test phrases / audition
    @Published var phrases: [TestPhrase] = AppModel.loadPhrases()
    @Published var selectedPhraseID: UUID?
    @Published var isPlaying = false
    @Published var transpose = 0
    @Published var retriggerOnEdit = false
    @Published var keyboardOctave = 3          // mini keyboard starts at C3 (MIDI 48) and spans two octaves
    private var playGeneration = 0
    private var activeNotes = Set<UInt8>()

    var engine: MIDIEngine?
    private var pendingSend: DispatchWorkItem?
    private var suppressAutoSend = false
    private var pendingDumpRequest = false
    private var pendingAllDumpRequest = false

    var midiChannel: UInt8 { UInt8(max(0, min(15, channel - 1))) }

    init() {
        selectedPhraseID = phrases.first?.id
        selectedBankID = banks.first?.id
        do {
            let e = try MIDIEngine(name: "Patchwork")
            e.onSysEx = { [weak self] bytes in
                DispatchQueue.main.async { self?.handleIncoming(bytes) }
            }
            e.onSetupChanged = { [weak self] in
                DispatchQueue.main.async { self?.refreshEndpoints() }
            }
            e.onRawBytes = { [weak self] _ in
                DispatchQueue.main.async { self?.lastHeard = Date() }
            }
            engine = e
            refreshEndpoints()
            linkTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.updateLink() }
        } catch {
            status = "CoreMIDI unavailable: \(error)"
            append("CoreMIDI init failed: \(error)", error: true)
        }
    }

    // MARK: Endpoints

    func refreshEndpoints() {
        sources = MIDIEngine.sources()
        destinations = MIDIEngine.destinations()
        func prefer(_ list: [MIDIEngine.Endpoint]) -> MIDIEndpointRef {
            if let k = list.first(where: { $0.name.lowercased().contains("komplete") }) { return k.id }
            return list.first?.id ?? 0
        }
        if !sources.contains(where: { $0.id == selectedSource }) { selectedSource = prefer(sources) }
        if !destinations.contains(where: { $0.id == selectedDestination }) { selectedDestination = prefer(destinations) }
        status = destinations.isEmpty ? "No MIDI interface found" : "Ready"
    }

    private func connectSource() {
        guard let engine = engine, selectedSource != 0 else { return }
        do { try engine.connect(source: selectedSource) }
        catch { append("Connect input failed: \(error)", error: true) }
    }

    // MARK: Sending

    private func scheduleAutoSend() {
        dirty = true
        guard autoSend else { return }
        pendingSend?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.sendProgram(quiet: true)
            self.retriggerIfWanted(after: 0.1)   // give the M1 a moment to load the edit buffer
        }
        pendingSend = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }

    func sendProgram(quiet: Bool = false) {
        pendingSend?.cancel()
        send(ActiveSynth.programDump(program, channel: midiChannel), what: quiet ? nil : "Sent “\(program.name)” to edit buffer", expectAck: true)
    }

    // MARK: Link health

    private func updateLink() {
        let heard = lastHeard.map { Date().timeIntervalSince($0) < 2 } ?? false
        guard heard != inputHeard else { return }
        inputHeard = heard
        if heard { append("Hearing the M1 on In") }
        else if lastHeard != nil { append("Nothing on In for 2 s — the M1 has gone quiet (powered off, or its MIDI OUT unplugged?)", error: true) }
    }

    /// Expect a load completed / load error within 0.7 s of a dump; otherwise say so, at most once per 15 s.
    private func armAckTimeout(quiet: Bool) {
        awaitingAck?.cancel()
        lastSendWasQuiet = quiet
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.awaitingAck = nil
            self.noteMissingAck()
        }
        awaitingAck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
    }

    private func noteMissingAck() {
        if let t = lastNoAckWarning, Date().timeIntervalSince(t) < 15 { return }
        lastNoAckWarning = Date()
        let out = destinations.first { $0.id == selectedDestination }?.name ?? "the output"
        if inputHeard {
            append("Sent to \(out) but the M1 didn't acknowledge within 0.7 s. It is alive on In, so check Global channel = \(channel) and GLOBAL → 5 → Exclusive = ENA", error: true)
        } else {
            append("Sent to \(out) but nothing came back on In — is the M1 powered on, cabled both ways, and on channel \(channel)? A connected M1 sends active sensing continuously", error: true)
        }
    }

    /// Called for every acknowledgement; returns true when the log line for it should be skipped
    /// (a routine load-completed for a quiet auto-send, which would otherwise flood the log).
    private func acknowledged(_ m: M1SysEx.Message) -> Bool {
        awaitingAck?.cancel()
        awaitingAck = nil
        lastNoAckWarning = nil
        if case .loadCompleted = m, lastSendWasQuiet { lastSendWasQuiet = false; return true }
        return false
    }

    /// Editor patch → M1 internal slot `writeSlot` (ack-driven; see Banks.swift).
    func writeToSlot() {
        writeProgram(program, toM1Slot: writeSlot, mirrorToSelectedBank: mirrorWritesToBank && selectedBankID != nil)
    }

    // MARK: Global data / drum kits

    func requestGlobal() {
        pendingGlobalRequest = true
        send(M1SysEx.globalDumpRequest(channel: midiChannel), what: "Requested Global data (settings + drum kits)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self = self, self.pendingGlobalRequest else { return }
            self.pendingGlobalRequest = false
            self.append("No Global data within 4 s — Exclusive = ENA? Some interfaces drop the ~1 KB message; try again", error: true)
        }
    }

    func sendGlobal(quiet: Bool = false) {
        pendingGlobalSend?.cancel()
        guard let g = globalData else { append("No Global data loaded — Request it first", error: true); return }
        send(M1SysEx.globalDump(g, channel: midiChannel), what: quiet ? nil : "Sent Global data (drum kits) to the M1 — stored there immediately", expectAck: true)
        globalDirty = false
        globalAsReceived = g
    }

    /// Throw away local kit edits; back to what the M1 last sent us.
    func revertGlobal() {
        guard let g = globalAsReceived else { return }
        suppressGlobalAutoSend = true
        globalData = g
        suppressGlobalAutoSend = false
        globalDirty = false
        append("Reverted kit edits to the M1's copy")
    }

    /// Every received Global dump is written to Application Support as a dated .syx — the undo for kit edits.
    private func backupGlobal(_ bytes: [UInt8]) {
        let dir = BankStore.url.deletingLastPathComponent().appendingPathComponent("global-backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd-HHmmss"
        let url = dir.appendingPathComponent("global-\(f.string(from: Date())).syx")
        if (try? Data(bytes).write(to: url)) != nil { append("Global data backed up to \(url.path)") }
    }

    private func scheduleGlobalSend() {
        globalDirty = true
        guard globalAutoSend else { return }
        pendingGlobalSend?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.sendGlobal(quiet: true) }
        pendingGlobalSend = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    func kitEntryBinding(index: Int) -> Binding<DrumKitEntry> {
        Binding(
            get: { self.globalData?.entry(kit: self.selectedKit, index: index) ?? DrumKitEntry() },
            set: { e in
                guard var g = self.globalData else { return }
                let before = self.globalData
                g.setEntry(e, kit: self.selectedKit, index: index)
                self.globalData = g
                self.registerGlobalUndo(before, "Edit Kit Entry")
            })
    }

    /// Point the editor's program at the selected kit (Drums mode) and send it, so the keyboard plays the kit.
    func useSelectedKitInEditor() {
        var p = program
        p.setUnsigned(P.oscMode, 2)
        p.setUnsigned(P.osc1Multisound, selectedKit)
        if !p.name.lowercased().contains("kit") { p.name = "Kit \(selectedKit + 1)" }
        load(p, announce: "Editor program set to Drums mode, Drum Kit \(selectedKit + 1)", thenSend: true)
    }

    /// Short note for auditioning one kit key.
    func tapNote(_ note: Int, durationMs: Int = 250) {
        let n = UInt8(max(0, min(127, note)))
        noteOn(n, velocity: 110)
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(durationMs) / 1000) { [weak self] in self?.noteOff(n) }
    }

    func importKit(from url: URL) {
        do {
            let patch = try JSONDecoder().decode(DrumKitPatch.self, from: Data(contentsOf: url))
            guard var g = globalData else { throw M1Error.invalidValue(field: "global", reason: "Request Global data from the M1 first") }
            guard (1...4).contains(patch.kit) else { throw M1Error.invalidValue(field: "kit", reason: "kit must be 1…4") }
            let before = globalData
            g.setKit(patch.kit - 1, try patch.toEntries())
            registerGlobalUndo(before, "Import Kit")
            selectedKit = patch.kit - 1
            globalData = g
            append("Imported kit \(patch.kit) from \(url.lastPathComponent) (\(patch.entries.count) entries)")
        } catch {
            errorMessage = "Couldn't import kit: \(error)"
        }
    }

    func exportKit(to url: URL) {
        guard let g = globalData else { return }
        do {
            let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try enc.encode(DrumKitPatch(kit: selectedKit, entries: g.kit(selectedKit))).write(to: url)
            append("Saved Drum Kit \(selectedKit + 1) to \(url.lastPathComponent)")
        } catch {
            errorMessage = "Couldn't save kit: \(error)"
        }
    }

    /// The M1 only answers program dump requests (and accepts program dumps) in Program mode.
    func switchToProgramMode() {
        send(M1SysEx.modeChange(.program, channel: midiChannel), what: "Mode change → Program")
    }

    func requestMode() {
        send(M1SysEx.modeRequest(channel: midiChannel), what: "Mode request")
    }

    func requestProgram() {
        switchToProgramMode()
        pendingDumpRequest = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.send(ActiveSynth.programDumpRequest(channel: self?.midiChannel ?? 0), what: "Requested current program")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.3) { [weak self] in
            guard let self = self, self.pendingDumpRequest else { return }
            self.pendingDumpRequest = false
            self.append("No reply to dump request — check Exclusive = ENA (Global 5 → Page+, H), the Ch picker matches the M1's global channel, and its MIDI OUT reaches the interface", error: true)
        }
    }

    func requestAllPrograms() {
        pendingAllDumpRequest = true
        switchToProgramMode()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self else { return }
            self.send(M1SysEx.allProgramDumpRequest(channel: self.midiChannel), what: "Requested all 100 programs as one 16 KB dump (some interfaces drop this — use Fetch bank instead)")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self = self, self.pendingAllDumpRequest else { return }
            self.pendingAllDumpRequest = false
            self.append("No all-program dump within 8 s — try single Request instead; some USB interfaces drop 16 KB messages", error: true)
        }
    }

    func send(_ bytes: [UInt8], what: String?, expectAck: Bool = false) {
        guard let engine = engine, selectedDestination != 0 else {
            append("No MIDI output selected", error: true); return
        }
        do {
            try engine.send(bytes, to: selectedDestination)
            if let w = what { append(w) }
            if expectAck { armAckTimeout(quiet: what == nil) }
        } catch {
            append("Send failed: \(error)", error: true)
        }
    }

    // MARK: Receiving

    private func handleIncoming(_ bytes: [UInt8]) {
        guard ActiveSynth.isMessage(bytes) else {
            append("Other SysEx (\(bytes.count) bytes) \(hex(Array(bytes.prefix(8))))…")
            return
        }
        do {
            // Generic first: transfers only need the synth-agnostic message kinds.
            if transfer != nil, let generic = ActiveSynth.parse(bytes), transferHandle(generic.message) { return }
            // Then the M1's own extras (mode data, Global data, panel parameter changes).
            let parsed = try M1SysEx.parse(bytes)
            if parsed.message.isAck, acknowledged(parsed.message) { return }
            switch parsed.message {
            case .programDump(let p):
                pendingDumpRequest = false
                load(p, announce: "Received “\(p.name)” from M1")
            case .globalDump(let g):
                pendingGlobalRequest = false
                suppressGlobalAutoSend = true
                globalData = g
                suppressGlobalAutoSend = false
                globalDirty = false
                globalAsReceived = g
                append("Received Global data from the M1 (\(g.bytes.count) bytes): 4 drum kits ready to edit")
                backupGlobal(bytes)
            case .allProgramDump(let ps):
                pendingAllDumpRequest = false
                let b = addBank(bank(from: ps, name: "M1 bank (single dump)"))
                append("Received \(ps.count) programs into bank “\(b.name)”")
            case .parameterChange(let pg, let po, let v):
                append("Panel edit: page \(pg) pos \(po) = \(v)   [\(hex(bytes))]")
            case .loadError:
                lastAck = parsed.message.summary
                append("M1: Data load error — it is probably not in Program mode (use M1 → Switch to Program mode, or Request, which switches first)", error: true)
            default:
                lastAck = parsed.message.summary
                append("M1: \(parsed.message.summary)", error: !isGood(parsed.message))
            }
        } catch {
            append("Could not parse M1 message: \(error)  \(hex(Array(bytes.prefix(12))))", error: true)
        }
    }

    private func isGood(_ m: M1SysEx.Message) -> Bool {
        switch m {
        case .writeError, .loadError, .formatError: return false
        default: return true
        }
    }

    /// Replace the editor contents without echoing them straight back to the M1 (unless `thenSend`).
    /// Any change of contents counts for "Retrigger on change", so the new sound is heard immediately.
    func load(_ p: M1Program, announce: String? = nil, thenSend: Bool = false) {
        suppressAutoSend = true
        program = p
        suppressAutoSend = false
        dirty = false
        if let a = announce { append(a) }
        if thenSend { sendProgram() }
        retriggerIfWanted(after: thenSend ? 0.15 : 0)
    }

    /// Re-play the selected phrase if the toggle is on and a looping phrase isn't already sounding.
    private func retriggerIfWanted(after delay: TimeInterval) {
        guard retriggerOnEdit, let phrase = selectedPhrase, !(phrase.loop && isPlaying) else { return }
        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.play() }
        } else {
            play()
        }
    }

    // MARK: Generators (with a little visual feedback)

    /// Parameter indices that just changed via a generator; the rows glow briefly.
    @Published var highlighted: Set<Int> = []
    /// Die face shown on the Randomise button; cycles during a roll.
    @Published var diceFace = 5
    /// Completed rolls — drives the die's spin animation.
    @Published var rollTurns = 0
    @Published var rolling = false
    @Published var mutating = false
    private var highlightClear: DispatchWorkItem?

    func randomise() {
        guard !rolling else { return }
        let seed = UInt64(Date().timeIntervalSince1970 * 1000) % 1_000_000
        var target = ActiveSynth.randomise(base: program, seed: seed)
        target.name = "RND \(seed % 10000)"
        let before = program

        rolling = true
        rollTurns += 1
        // Tumble through a few throwaway programs so the controls visibly roll, then land on the real one.
        let steps = 7
        let interval = 0.07
        for i in 0..<steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * interval) { [weak self] in
                guard let self = self, self.rolling else { return }
                self.diceFace = Int.random(in: 1...6)
                var p = ActiveSynth.randomise(base: before, seed: seed &+ UInt64(i + 1))
                p.name = target.name
                self.suppressAutoSend = true
                self.program = p
                self.suppressAutoSend = false
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(steps) * interval) { [weak self] in
            guard let self = self else { return }
            self.rolling = false
            self.diceFace = Int(seed % 6) + 1
            self.flash(changedBetween: before, and: target)
            self.load(target, announce: "Randomised (seed \(seed))", thenSend: self.autoSend)
        }
    }

    func mutate(amount: Double) {
        let seed = UInt64(Date().timeIntervalSince1970 * 1000) % 1_000_000
        let before = program
        let after = ActiveSynth.mutate(program, amount: amount, seed: seed)
        mutating = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.mutating = false }
        flash(changedBetween: before, and: after)
        load(after, announce: "Mutated \(Int(amount * 100))% — \(changedCount(before, after)) parameters (seed \(seed))", thenSend: autoSend)
        dirty = true
    }

    func morphToward(_ other: M1Program, t: Double) {
        let before = program
        let after = ActiveSynth.morph(program, other, t: t)
        flash(changedBetween: before, and: after)
        load(after, announce: "Morphed \(Int(t * 100))% toward “\(other.name)”", thenSend: autoSend)
        dirty = true
    }

    private func changedCount(_ a: M1Program, _ b: M1Program) -> Int {
        zip(a.bytes, b.bytes).filter { $0 != $1 }.count
    }

    /// Light up the rows whose bytes differ, then fade them out.
    private func flash(changedBetween a: M1Program, and b: M1Program) {
        var set = Set<Int>()
        for (i, pair) in zip(a.bytes, b.bytes).enumerated() where pair.0 != pair.1 {
            set.insert(i < M1Program.nameLength ? P.nameStart : i)   // name bytes map to the single Name row
        }
        highlighted = set
        highlightClear?.cancel()
        let work = DispatchWorkItem { [weak self] in
            withAnimation(.easeOut(duration: 0.9)) { self?.highlighted = [] }
        }
        highlightClear = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    // MARK: Files

    func importFile(_ url: URL) {
        do {
            let data = try Data(contentsOf: url)
            if url.pathExtension.lowercased() == "syx" || data.first == 0xF0 {
                let programs = ActiveSynth.programs(inSyx: [UInt8](data))
                guard let first = programs.first else { throw M1Error.notM1 }
                if programs.count > 1 {
                    importBanks(from: programs, baseName: url.deletingPathExtension().lastPathComponent)
                }
                load(first, announce: "Opened “\(first.name)” from \(url.lastPathComponent)", thenSend: autoSend)
            } else {
                let p = try ActiveSynth.program(fromJSON: data)
                load(p, announce: "Opened “\(p.name)” from \(url.lastPathComponent)", thenSend: autoSend)
            }
        } catch {
            errorMessage = "Couldn't open \(url.lastPathComponent): \(error)"
        }
    }

    func exportFile(_ url: URL) {
        do {
            if url.pathExtension.lowercased() == "syx" {
                try Data(ActiveSynth.programDump(program, channel: midiChannel)).write(to: url)
            } else {
                try ActiveSynth.json(for: program).write(to: url)
            }
            dirty = false
            append("Saved \(url.lastPathComponent)")
        } catch {
            errorMessage = "Couldn't save: \(error)"
        }
    }

    // MARK: Test phrases

    var selectedPhrase: TestPhrase? {
        phrases.first { $0.id == selectedPhraseID }
    }

    /// Play the selected phrase (or `override`) once, or until stopped if it loops.
    func play(_ specific: TestPhrase? = nil) {
        guard let phrase = specific ?? selectedPhrase, !phrase.steps.isEmpty else { return }
        playGeneration += 1
        let gen = playGeneration
        releaseAllNotes()
        isPlaying = true
        var t: Double = 0
        for step in phrase.steps {
            let notes = step.notes.map { UInt8(max(0, min(127, $0 + transpose))) }
            let velocity = UInt8(max(1, min(127, step.velocity)))
            DispatchQueue.main.asyncAfter(deadline: .now() + t) { [weak self] in
                guard let self = self, self.playGeneration == gen else { return }
                for n in notes { self.noteOn(n, velocity: velocity) }
            }
            t += Double(step.durationMs) / 1000
            DispatchQueue.main.asyncAfter(deadline: .now() + t) { [weak self] in
                guard let self = self, self.playGeneration == gen else { return }
                for n in notes { self.noteOff(n) }
            }
            t += Double(step.gapMs) / 1000
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + t) { [weak self] in
            guard let self = self, self.playGeneration == gen else { return }
            if phrase.loop { self.play(phrase) } else { self.isPlaying = false }
        }
    }

    func stop() {
        playGeneration += 1
        releaseAllNotes()
        isPlaying = false
    }

    func togglePlay() {
        if isPlaying { stop() } else { play() }
    }

    /// Mini-keyboard press/release.
    func keyDown(_ note: Int) { noteOn(UInt8(max(0, min(127, note + transpose))), velocity: 100) }
    func keyUp(_ note: Int) { noteOff(UInt8(max(0, min(127, note + transpose)))) }

    private func noteOn(_ note: UInt8, velocity: UInt8) {
        guard let engine = engine, selectedDestination != 0 else { return }
        try? engine.noteOn(note, velocity: velocity, channel: midiChannel, to: selectedDestination)
        activeNotes.insert(note)
    }

    private func noteOff(_ note: UInt8) {
        guard let engine = engine, selectedDestination != 0 else { return }
        try? engine.noteOff(note, channel: midiChannel, to: selectedDestination)
        activeNotes.remove(note)
    }

    private func releaseAllNotes() {
        for n in activeNotes { noteOff(n) }
        activeNotes.removeAll()
        if let engine = engine, selectedDestination != 0 {
            try? engine.allNotesOff(channel: midiChannel, to: selectedDestination)
        }
    }

    // Phrase persistence (UserDefaults; presets are the starting point and can be restored).

    static let phrasesKey = "testPhrases"

    static func loadPhrases() -> [TestPhrase] {
        if let data = UserDefaults.standard.data(forKey: phrasesKey),
           let saved = try? JSONDecoder().decode([TestPhrase].self, from: data), !saved.isEmpty {
            return saved
        }
        return TestPhrase.presets
    }

    func savePhrases() {
        if let data = try? JSONEncoder().encode(phrases) {
            UserDefaults.standard.set(data, forKey: AppModel.phrasesKey)
        }
    }

    func addPhrase() {
        let p = TestPhrase(name: "New phrase", steps: [PhraseStep(notes: [60])])
        phrases.append(p)
        selectedPhraseID = p.id
        savePhrases()
    }

    func duplicateSelectedPhrase() {
        guard var p = selectedPhrase else { return }
        p.id = UUID()
        p.name += " copy"
        p.steps = p.steps.map { var s = $0; s.id = UUID(); return s }
        phrases.append(p)
        selectedPhraseID = p.id
        savePhrases()
    }

    func deletePhrase(_ id: UUID) {
        phrases.removeAll { $0.id == id }
        if selectedPhraseID == id { selectedPhraseID = phrases.first?.id }
        savePhrases()
    }

    func resetPhrasesToPresets() {
        phrases = TestPhrase.presets
        selectedPhraseID = phrases.first?.id
        savePhrases()
    }

    // MARK: Bindings for the generic parameter views

    func unsignedBinding(_ index: Int) -> Binding<Int> {
        Binding(get: { self.program.unsigned(index) }, set: { self.program.setUnsigned(index, $0) })
    }

    func signedBinding(_ index: Int) -> Binding<Int> {
        Binding(get: { self.program.signed(index) }, set: { self.program.setSigned(index, $0) })
    }

    func fieldBinding(_ index: Int, shift: Int, width: Int) -> Binding<Int> {
        Binding(get: { self.program.field(index, shift: shift, width: width) },
                set: { self.program.setField(index, shift: shift, width: width, $0) })
    }

    func bitBinding(_ index: Int, bit: Int) -> Binding<Bool> {
        Binding(get: { self.program.bit(index, bit) }, set: { self.program.setBit(index, bit, $0) })
    }

    var nameBinding: Binding<String> {
        Binding(get: { self.program.name }, set: { self.program.name = $0 })
    }

    // MARK: Log

    func append(_ text: String, error: Bool = false) {
        log.append(LogEntry(text: text, isError: error))
        if log.count > 500 { log.removeFirst(log.count - 500) }
        status = text
    }
}
#endif
