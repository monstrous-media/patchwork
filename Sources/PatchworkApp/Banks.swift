#if os(macOS)
import Foundation
import SwiftUI
import PatchworkCore
import PatchworkMIDI

// MARK: - Local banks

/// A named bank of 100 program slots kept by the app. The M1 holds one internal bank at a time;
/// the app can hold many (a factory backup, work in progress, experiments…).
struct Bank: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var programs: [M1Program?]
    var created: Date = Date()

    static let slotCount = ActiveSynth.bankSize

    static func empty(name: String) -> Bank {
        Bank(name: name, programs: Array(repeating: nil, count: slotCount))
    }

    var filledCount: Int { programs.compactMap { $0 }.count }

    /// Slot numbers that hold a program.
    var filledSlots: [Int] { programs.indices.filter { programs[$0] != nil } }

    static func slotLabel(_ n: Int) -> String { ActiveSynth.slotLabel(n) }
}

enum BankStore {
    static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Patchwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("banks.json")
    }

    static func load() -> [Bank] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Bank].self, from: data)) ?? []
    }

    static func save(_ banks: [Bank]) {
        if let data = try? JSONEncoder().encode(banks) { try? data.write(to: url, options: .atomic) }
    }
}

// MARK: - Transfers between local banks and the M1

/// One running transfer: fetching slots from the M1, verifying slots against the M1, or writing slots to it.
struct TransferState {
    enum Kind { case fetch, verify, write }
    enum Phase { case idle, awaitingDump, awaitingLoadAck, awaitingWriteAck }

    var kind: Kind
    var label: String
    var bankID: UUID?                      // fetch/verify target
    var slots: [Int]                       // remaining slot numbers (fetch/verify)
    var writes: [(slot: Int, program: M1Program)]   // remaining (write)
    var total: Int
    var done = 0
    var phase: Phase = .idle
    var mismatches: [Int] = []
    var verifyAfter: Bool = false
    var writtenSlots: [Int] = []
    /// After the M1 acknowledges a write, also store the program in that slot of the selected local bank.
    var mirrorToSelectedBank: Bool = false

    var progress: Double { total == 0 ? 0 : Double(done) / Double(total) }
}

extension AppModel {

    // MARK: Bank bookkeeping

    var selectedBankIndex: Int? { banks.firstIndex { $0.id == selectedBankID } }
    var selectedBank: Bank? { selectedBankIndex.map { banks[$0] } }

    func bankIndex(_ id: UUID?) -> Int? { banks.firstIndex { $0.id == id } }

    @discardableResult
    func addBank(_ bank: Bank, select: Bool = true) -> Bank {
        banks.append(bank)
        if select { selectedBankID = bank.id }
        return bank
    }

    func newEmptyBank() {
        let before = banks
        addBank(Bank.empty(name: "New bank \(banks.count + 1)"))
        registerBanksUndo(before, "New Bank")
    }

    func duplicateSelectedBank() {
        guard var b = selectedBank else { return }
        let before = banks
        b.id = UUID(); b.name += " copy"; b.created = Date()
        addBank(b)
        registerBanksUndo(before, "Duplicate Bank")
    }

    func deleteBank(_ id: UUID) {
        let before = banks
        banks.removeAll { $0.id == id }
        if selectedBankID == id { selectedBankID = banks.first?.id }
        registerBanksUndo(before, "Delete Bank")
    }

    func bank(from programs: [M1Program], name: String) -> Bank {
        var b = Bank.empty(name: name)
        for (i, p) in programs.prefix(Bank.slotCount).enumerated() { b.programs[i] = p }
        return b
    }

    /// Editor patch → slot n of the selected bank (local only).
    func storeCurrent(inSlot n: Int) {
        guard let i = selectedBankIndex, n >= 0, n < Bank.slotCount else { return }
        let before = banks
        let replaced = banks[i].programs[n]
        banks[i].programs[n] = program
        registerBanksUndo(before, "Store in Slot")
        if let r = replaced {
            append("Stored “\(program.name)” in \(banks[i].name) \(Bank.slotLabel(n)), replacing “\(r.name)” (local — ⌘Z to undo)")
        } else {
            append("Stored “\(program.name)” in \(banks[i].name) \(Bank.slotLabel(n)) (local — ⌘Z to undo)")
        }
    }

    func clearSlot(_ n: Int) {
        guard let i = selectedBankIndex, n >= 0, n < Bank.slotCount else { return }
        let before = banks
        banks[i].programs[n] = nil
        registerBanksUndo(before, "Clear Slot")
        append("Cleared \(banks[i].name) \(Bank.slotLabel(n)) (local — ⌘Z to undo)")
    }

    // MARK: Files

    func importBank(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let programs = ActiveSynth.programs(inSyx: [UInt8](data))
            guard !programs.isEmpty else { throw M1Error.notM1 }
            importBanks(from: programs, baseName: url.deletingPathExtension().lastPathComponent)
        } catch {
            errorMessage = "Couldn't import \(url.lastPathComponent): \(error)"
        }
    }

    /// Split a list of programs into 100-slot banks ("name", "name (2)", …) so nothing is dropped.
    func importBanks(from programs: [M1Program], baseName: String) {
        let before = banks
        defer { registerBanksUndo(before, "Import Bank") }
        var chunkIndex = 0
        var start = 0
        while start < programs.count {
            let chunk = Array(programs[start..<min(start + Bank.slotCount, programs.count)])
            let name = chunkIndex == 0 ? baseName : "\(baseName) (\(chunkIndex + 1))"
            addBank(bank(from: chunk, name: name), select: chunkIndex == 0)
            start += Bank.slotCount
            chunkIndex += 1
        }
        if programs.count > Bank.slotCount {
            append("Imported \(programs.count) programs: a bank holds 100, so they went into \(chunkIndex) banks (“\(baseName)” … “\(baseName) (\(chunkIndex))”)")
        } else {
            append("Imported \(programs.count) programs into bank “\(baseName)”")
        }
    }

    /// Export a bank as a .syx of program dumps in slot order (empty slots are skipped).
    func exportBank(_ bank: Bank, to url: URL) {
        do {
            var bytes: [UInt8] = []
            for p in bank.programs.compactMap({ $0 }) { bytes += ActiveSynth.programDump(p, channel: midiChannel) }
            try Data(bytes).write(to: url)
            append("Exported \(bank.filledCount) programs of “\(bank.name)” to \(url.lastPathComponent)")
        } catch {
            errorMessage = "Couldn't export bank: \(error)"
        }
    }

    /// Export one program as .syx or .json.
    func exportProgram(_ p: M1Program, to url: URL) {
        do {
            if url.pathExtension.lowercased() == "syx" {
                try Data(ActiveSynth.programDump(p, channel: midiChannel)).write(to: url)
            } else {
                try ActiveSynth.json(for: p).write(to: url)
            }
            append("Saved “\(p.name)” to \(url.lastPathComponent)")
        } catch {
            errorMessage = "Couldn't save: \(error)"
        }
    }

    // MARK: Starting transfers

    /// Read every slot from the M1 into a new, dated bank.
    func fetchBankFromM1() {
        guard transfer == nil else { return }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"
        let b = addBank(Bank.empty(name: "M1 \(f.string(from: Date()))"))
        startTransfer(TransferState(kind: .fetch, label: "Fetching bank from M1", bankID: b.id,
                                    slots: Array(0..<Bank.slotCount), writes: [], total: Bank.slotCount))
    }

    /// Re-read the given slots and compare with the bank.
    func verifyBank(_ bank: Bank, slots: [Int]? = nil) {
        guard transfer == nil else { return }
        let which = slots ?? bank.filledSlots
        guard !which.isEmpty else { append("Nothing to verify — bank is empty", error: true); return }
        startTransfer(TransferState(kind: .verify, label: "Verifying “\(bank.name)” against M1", bankID: bank.id,
                                    slots: which, writes: [], total: which.count))
    }

    /// Write every filled slot of the bank to the M1 (Memory Protect must be off).
    func restoreBankToM1(_ bank: Bank, verify: Bool) {
        guard transfer == nil else { return }
        let items = bank.filledSlots.map { (slot: $0, program: bank.programs[$0]!) }
        guard !items.isEmpty else { append("Nothing to restore — bank is empty", error: true); return }
        var t = TransferState(kind: .write, label: "Restoring “\(bank.name)” to M1", bankID: bank.id,
                              slots: [], writes: items, total: items.count)
        t.verifyAfter = verify
        startTransfer(t)
    }

    /// Write one program to one M1 slot (used by library rows and the editor's Write button).
    /// With `verifyAgainstBank`, the slot is re-read afterwards and compared with that bank's slot.
    func writeProgram(_ p: M1Program, toM1Slot n: Int, verifyAgainstBank bankID: UUID? = nil, mirrorToSelectedBank: Bool = false) {
        guard transfer == nil else { append("Another transfer is running", error: true); return }
        let verifyBank = bankID ?? (mirrorToSelectedBank ? selectedBankID : nil)
        var t = TransferState(kind: .write, label: "Writing “\(p.name)” to \(Bank.slotLabel(n))", bankID: verifyBank,
                              slots: [], writes: [(slot: n, program: p)], total: 1)
        t.verifyAfter = verifyBank != nil
        t.mirrorToSelectedBank = mirrorToSelectedBank
        startTransfer(t)
    }

    func cancelTransfer() {
        guard let t = transfer else { return }
        transferGeneration += 1
        transfer = nil
        append("\(t.label): cancelled after \(t.done)/\(t.total)", error: true)
    }

    private func startTransfer(_ state: TransferState) {
        transfer = state
        transferGeneration += 1
        for m in ActiveSynth.prepareForTransfer(channel: midiChannel) { send(m, what: "Preparing \(ActiveSynth.displayName) for transfer") }
        append("\(state.label)…")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.transferStep() }
    }

    // MARK: Driving a transfer, one slot at a time, acknowledged by the M1

    private func transferStep() {
        guard var t = transfer else { return }
        let gen = transferGeneration
        switch t.kind {
        case .fetch, .verify:
            guard let n = t.slots.first else { finishTransfer(); return }
            t.phase = .awaitingDump
            transfer = t
            send(ActiveSynth.selectProgram(slot: n, channel: midiChannel), what: nil)
            after(0.12, gen) { self.send(ActiveSynth.programDumpRequest(channel: self.midiChannel), what: nil) }
            after(2.6, gen) { self.failTransfer("no dump received for \(Bank.slotLabel(n))") }
        case .write:
            guard let item = t.writes.first else { finishTransfer(); return }
            t.phase = .awaitingLoadAck
            transfer = t
            send(ActiveSynth.programDump(item.program, channel: midiChannel), what: nil)
            after(3.0, gen) {
                if self.transfer?.phase == .awaitingLoadAck { self.failTransfer("M1 did not acknowledge the program dump for \(Bank.slotLabel(item.slot))") }
            }
        }
    }

    /// Called from handleIncoming for any synth message while a transfer is running. Returns true if consumed.
    func transferHandle(_ message: SynthMessage) -> Bool {
        guard var t = transfer else { return false }
        switch (t.kind, t.phase, message) {

        case (.fetch, .awaitingDump, .programDump(let raw)):
            guard let p = try? Program(bytes: raw) else { failTransfer("malformed program dump"); return true }
            let n = t.slots.removeFirst()
            if let i = bankIndex(t.bankID) { banks[i].programs[n] = p }
            t.done += 1; t.phase = .idle
            transfer = t
            status = "\(t.label): \(Bank.slotLabel(n)) “\(p.name)” (\(t.done)/\(t.total))"
            transferGeneration += 1          // invalidates this step's timeout
            transferStep()
            return true

        case (.verify, .awaitingDump, .programDump(let raw)):
            guard let p = try? Program(bytes: raw) else { failTransfer("malformed program dump"); return true }
            let n = t.slots.removeFirst()
            let expected = bankIndex(t.bankID).flatMap { banks[$0].programs[n] }
            if expected != p { t.mismatches.append(n) }
            t.done += 1; t.phase = .idle
            transfer = t
            status = "\(t.label): \(Bank.slotLabel(n)) \(expected == p ? "✓" : "✗ differs") (\(t.done)/\(t.total))"
            transferGeneration += 1
            transferStep()
            return true

        case (.write, .awaitingLoadAck, .loadCompleted):
            guard let item = t.writes.first else { return true }
            t.phase = .awaitingWriteAck
            transfer = t
            transferGeneration += 1
            let g2 = transferGeneration
            guard let write = ActiveSynth.writeRequest(slot: item.slot, channel: midiChannel) else {
                failTransfer("\(ActiveSynth.displayName) has no write-to-slot message"); return true
            }
            send(write, what: nil)
            after(3.0, g2) {
                if self.transfer?.phase == .awaitingWriteAck { self.failTransfer("M1 did not acknowledge the write to \(Bank.slotLabel(item.slot))") }
            }
            return true

        case (.write, .awaitingWriteAck, .writeCompleted):
            let item = t.writes.removeFirst()
            t.writtenSlots.append(item.slot)
            t.done += 1; t.phase = .idle
            transfer = t
            if t.mirrorToSelectedBank, let i = selectedBankIndex {
                let before = banks
                banks[i].programs[item.slot] = item.program
                registerBanksUndo(before, "Mirror Write to Bank")
                append("Stored “\(item.program.name)” in \(banks[i].name) \(Bank.slotLabel(item.slot)) to mirror the M1")
            }
            status = "\(t.label): \(Bank.slotLabel(item.slot)) “\(item.program.name)” written (\(t.done)/\(t.total))"
            transferGeneration += 1
            transferStep()
            return true

        case (.write, _, .writeError):
            failTransfer("M1 refused the write (Memory Protect on? GLOBAL → 6 → Program = OFF)")
            return true

        case (_, _, .loadError):
            failTransfer("\(ActiveSynth.displayName) replied “data load error” — not in the right mode, or the dump was rejected")
            return true

        case (_, _, .formatError):
            failTransfer("\(ActiveSynth.displayName) replied “message format error”")
            return true

        default:
            return false
        }
    }

    private func finishTransfer() {
        guard let t = transfer else { return }
        transfer = nil
        transferGeneration += 1
        switch t.kind {
        case .fetch:
            let names = Set(bankIndex(t.bankID).map { banks[$0].programs.compactMap { $0?.name } } ?? [])
            append("Fetched \(t.done) programs from the M1 — export the bank as .syx to keep a file backup")
            if names.count == 1 && t.done > 1 {
                append("Every program has the same name — the M1 may be ignoring Program Change (Global 5+1: Combi/Prog Change = ENA)", error: true)
            }
        case .verify:
            if t.mismatches.isEmpty {
                append("Verified: all \(t.done) slots on the M1 match the bank ✓")
            } else {
                append("Verify: \(t.mismatches.count) of \(t.done) slots differ — \(t.mismatches.map { Bank.slotLabel($0) }.joined(separator: " "))", error: true)
            }
        case .write:
            append("Wrote \(t.done) program\(t.done == 1 ? "" : "s") to the M1")
            if t.verifyAfter, let id = t.bankID, let i = bankIndex(id) {
                verifyBank(banks[i], slots: t.writtenSlots)
            }
        }
    }

    private func failTransfer(_ why: String) {
        guard let t = transfer else { return }
        transfer = nil
        transferGeneration += 1
        append("\(t.label): stopped after \(t.done)/\(t.total) — \(why)", error: true)
    }

    /// Run `block` after `delay` unless the transfer generation has moved on.
    private func after(_ delay: TimeInterval, _ gen: Int, _ block: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, self.transfer != nil, self.transferGeneration == gen else { return }
            block()
        }
    }
}
#endif
