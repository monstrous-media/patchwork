#if os(macOS)
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import PatchworkCore

/// Keymap editor for the M1's four drum kits (which live in its Global data, not in programs).
struct DrumKitsView: View {
    @EnvironmentObject var model: AppModel
    @State private var sortByKey = true

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if model.globalData == nil {
                VStack(spacing: 10) {
                    Text("Drum kits live in the M1's Global data").font(.title3)
                    Text("Request it to see and edit the four kits: which drum instrument sounds on which key, with tune, level, decay and pan. Global data has no edit buffer on the M1 — whatever is sent is stored at once — so edits stay here until you press Send (or turn on Auto-send kit edits). Each Request also saves a backup .syx in the app's folder.")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 520)
                    Button("Request Global data from M1") { model.requestGlobal() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                entryHeader
                List {
                    ForEach(sortedIndices, id: \.self) { i in
                        KitEntryRow(index: i, entry: model.kitEntryBinding(index: i))
                    }
                }
            }
        }
    }

    var sortedIndices: [Int] {
        guard let g = model.globalData else { return [] }
        let all = Array(0..<M1GlobalData.entriesPerKit)
        guard sortByKey else { return all }
        return all.sorted { a, b in
            let ea = g.entry(kit: model.selectedKit, index: a), eb = g.entry(kit: model.selectedKit, index: b)
            if ea.isAssigned != eb.isAssigned { return ea.isAssigned }
            return ea.key < eb.key
        }
    }

    /// Two rows: what moves between app and M1, then which kit and how to view it.
    var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button { model.requestGlobal() } label: { Label("Request", systemImage: "arrow.down.circle") }
                    .help("Request: pull the M1's Global data (settings + the four drum kits)")
                Button { model.sendGlobal() } label: { Label("Send", systemImage: "arrow.up.circle") }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.globalData == nil || !model.globalDirty)
                    .help("Send: push the Global data (all four kits) to the M1. Unlike programs there is no edit buffer — the M1 stores it immediately.")
                Toggle("Auto-send kit edits", isOn: $model.globalAutoSend).toggleStyle(.checkbox).fixedSize()
                    .help("Off (default): edits stay in the app until you press Send. On: every edit is written into the M1 straight away.")
                Button("Revert") { model.revertGlobal() }
                    .disabled(!model.globalDirty)
                    .help("Discard local kit edits and go back to the copy last received from the M1")
                if model.globalDirty { StatusChip(text: "edited · not sent", tone: .warn) }
                Spacer()
                Button { importKit() } label: { Label("Import kit…", systemImage: "folder") }
                    .disabled(model.globalData == nil).help("Import a kit from a .json file into the selected kit (local until sent)")
                Button { exportKit() } label: { Label("Save kit…", systemImage: "square.and.arrow.down") }
                    .disabled(model.globalData == nil).help("Save the selected kit as .json")
                HelpButton(section: "drum-kits")
            }
            HStack(spacing: 12) {
                Picker("Kit", selection: $model.selectedKit) {
                    ForEach(0..<M1GlobalData.kitCount, id: \.self) { Text("Drum Kit \($0 + 1)").tag($0) }
                }
                .frame(width: 150)
                .help("Which of the four kits to edit")
                Button("Use this kit in the editor") { model.useSelectedKitInEditor() }
                    .help("Set the editor's program to Drums mode with this kit and send it, so the keyboard and phrases play the kit")
                Toggle("Sort by key", isOn: $sortByKey).toggleStyle(.checkbox).fixedSize()
                    .help("Show entries in keyboard order rather than by index")
                Spacer()
            }
        }
        .padding(10)
        .background(Theme.raised)
    }

    var entryHeader: some View {
        HStack(spacing: 8) {
            Text("#").frame(width: 26, alignment: .leading)
            Text("Instrument").frame(width: 140, alignment: .leading)
            Text("Key").frame(width: 104, alignment: .leading)
            Text("Pan").frame(width: 80, alignment: .leading)
            Text("Tune").frame(width: 84, alignment: .leading)
            Text("Level").frame(width: 84, alignment: .leading)
            Text("Decay").frame(width: 84, alignment: .leading)
            Spacer()
        }
        .font(Theme.groupHeader).foregroundStyle(Theme.faint)
        .padding(.horizontal, 18).padding(.vertical, 5)
        .background(Theme.raised)
        .help("Each entry places one drum instrument on one key. Unassigned keys next to an entry play the nearest instrument. Tune is in tenths of a semitone (±120 = one octave).")
    }

    func importKit() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.json]
        if panel.runModal() == .OK, let url = panel.url { model.importKit(from: url) }
    }

    func exportKit() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.json]
        panel.nameFieldStringValue = "drum-kit-\(model.selectedKit + 1).json"
        if panel.runModal() == .OK, let url = panel.url { model.exportKit(to: url) }
    }
}

struct KitEntryRow: View {
    @EnvironmentObject var model: AppModel
    let index: Int
    @Binding var entry: DrumKitEntry

    var body: some View {
        HStack(spacing: 8) {
            Text(index < 10 ? "0\(index)" : "\(index)").font(Theme.value).foregroundStyle(Theme.faint).frame(width: 26, alignment: .leading)
            Picker("", selection: $entry.instrument) {
                Text("Off").tag(0)
                ForEach(1..<DrumSounds.names.count, id: \.self) { i in Text("\(i)  \(DrumSounds.names[i])").tag(i) }
            }
            .labelsHidden().frame(width: 140)
            .help("Drum instrument on this key (Off = entry unused)")
            HStack(spacing: 4) {
                Stepper(value: $entry.key, in: 12...115) {
                    Text(NoteName.string(for: entry.key)).font(Theme.value).foregroundStyle(Theme.accent).frame(width: 34, alignment: .leading)
                }
                .help("Key this instrument sits on (C0–G8)")
                Button { model.tapNote(entry.key) } label: { Image(systemName: "play.fill") }
                    .buttonStyle(.borderless).disabled(!entry.isAssigned)
                    .help("Play this key on the M1 (the editor's program must be in Drums mode with this kit — use the button above)")
            }
            .frame(width: 104, alignment: .leading)
            Picker("", selection: $entry.pan) {
                ForEach(0..<DrumKitEntry.panLabels.count, id: \.self) { Text(DrumKitEntry.panLabels[$0]).tag($0) }
            }
            .labelsHidden().frame(width: 80)
            .help("Output pan: A…B is left…right of the main outputs; C, D and C+D are the individual outputs 3/4")
            SmallStepper(title: "", value: $entry.tune, range: -120...120, step: 10, width: 84)
                .help("Tune in tenths of a semitone: ±120 = one octave")
            SmallStepper(title: "", value: $entry.level, range: -50...50, step: 5, width: 84)
                .help("Level offset for this instrument")
            SmallStepper(title: "", value: $entry.decay, range: -50...50, step: 5, width: 84)
                .help("Decay offset: negative shortens, positive lengthens")
            Spacer()
        }
        .opacity(entry.isAssigned ? 1 : 0.55)
    }
}

struct SmallStepper: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let width: CGFloat

    var body: some View {
        Stepper(value: $value, in: range, step: step) {
            Text(value > 0 ? "+\(value)" : "\(value)").font(Theme.value).foregroundStyle(Theme.accent).frame(width: 40, alignment: .trailing)
        }
        .frame(width: width, alignment: .leading)
    }
}
#endif
