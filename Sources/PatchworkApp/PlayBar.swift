#if os(macOS)
import SwiftUI
import PatchworkCore

/// Audition strip shown under the editor pages: phrase picker, play/stop, transpose,
/// retrigger-on-edit, and a two-octave clickable keyboard.
struct PlayBar: View {
    @EnvironmentObject var model: AppModel
    @State private var showEditor = false

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                Button { model.togglePlay() } label: {
                    Label(model.isPlaying ? "Stop" : "Play", systemImage: model.isPlaying ? "stop.fill" : "play.fill")
                        .frame(width: 60)
                }
                .help("Play or stop the selected phrase on the M1 (⌘↩)")

                Picker("Phrase", selection: $model.selectedPhraseID) {
                    ForEach(model.phrases) { p in
                        Text(p.loop ? "\(p.name) ↻" : p.name).tag(Optional(p.id))
                    }
                }
                .frame(maxWidth: 230)
                .help("Test phrase to audition with; ↻ marks phrases that loop until stopped")

                Button("Edit…") { showEditor = true }
                    .help("Edit phrases: notes per step, velocity, gate, gap, loop")

                Stepper(value: $model.transpose, in: -24...24) {
                    Text("Transpose \(model.transpose >= 0 ? "+" : "")\(model.transpose)").monospacedDigit().frame(width: 100, alignment: .leading)
                }
                .help("Shift the phrase and keyboard in semitones (−12 for bass sounds)")

                Toggle("Retrigger on change", isOn: $model.retriggerOnEdit)
                    .help("Play the phrase again after every change: edits, Randomise, Mutate, Morph, Init, loading or requesting a program")

                Spacer()

                Stepper(value: $model.keyboardOctave, in: 0...7) {
                    Text("Keys from C\(model.keyboardOctave)").frame(width: 90, alignment: .leading)
                }
                .help("Lowest octave of the on-screen keyboard")
                HelpButton(section: "auditioning-the-play-bar")
            }
            MiniKeyboard(baseNote: (model.keyboardOctave + 1) * 12, octaves: 2)
                .help("Click and hold to play the M1")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .sheet(isPresented: $showEditor) {
            PhraseEditor().environmentObject(model)
        }
    }
}

// MARK: - Mini keyboard

struct MiniKeyboard: View {
    let baseNote: Int
    let octaves: Int

    static let whiteOffsets = [0, 2, 4, 5, 7, 9, 11]
    /// Semitone offset of the black key that follows white key i within an octave (nil = none).
    static let blackAfterWhite: [Int?] = [1, 3, nil, 6, 8, 10, nil]

    var body: some View {
        GeometryReader { geo in
            let whiteCount = 7 * octaves
            let w = geo.size.width / CGFloat(whiteCount)
            let h = geo.size.height
            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    ForEach(0..<whiteCount, id: \.self) { i in
                        KeyView(note: baseNote + MiniKeyboard.whiteOffsets[i % 7] + 12 * (i / 7), isBlack: false)
                            .frame(width: w, height: h)
                    }
                }
                ForEach(0..<whiteCount, id: \.self) { i in
                    if let off = MiniKeyboard.blackAfterWhite[i % 7] {
                        KeyView(note: baseNote + off + 12 * (i / 7), isBlack: true)
                            .frame(width: w * 0.6, height: h * 0.58)
                            .offset(x: CGFloat(i + 1) * w - w * 0.3, y: 0)
                    }
                }
            }
        }
        .frame(height: 56)
    }
}

struct KeyView: View {
    @EnvironmentObject var model: AppModel
    let note: Int
    let isBlack: Bool
    @State private var pressed = false

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(pressed ? Color.accentColor : (isBlack ? Color(white: 0.15) : Color(white: 0.97)))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.gray.opacity(0.7), lineWidth: 1))
            .overlay(alignment: .bottom) {
                if !isBlack && note % 12 == 0 {
                    Text(NoteName.string(for: note)).font(.caption2).foregroundColor(.gray).padding(.bottom, 2)
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !pressed { pressed = true; model.keyDown(note) }
                    }
                    .onEnded { _ in
                        pressed = false
                        model.keyUp(note)
                    }
            )
    }
}

// MARK: - Phrase editor sheet

struct PhraseEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                phraseList.frame(width: 220)
                Divider()
                if let i = model.phrases.firstIndex(where: { $0.id == model.selectedPhraseID }) {
                    stepEditor(index: i)
                } else {
                    Text("Select a phrase").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            Divider()
            HStack {
                Button("Reset to presets") { model.resetPhrasesToPresets() }
                Spacer()
                Button(model.isPlaying ? "Stop" : "Play") { model.togglePlay() }
                Button("Done") { model.savePhrases(); dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(10)
        }
        .frame(width: 820, height: 460)
    }

    var phraseList: some View {
        VStack(spacing: 0) {
            List(selection: $model.selectedPhraseID) {
                ForEach(model.phrases) { p in
                    HStack {
                        Text(p.name)
                        Spacer()
                        if p.loop { Image(systemName: "repeat").foregroundStyle(.secondary) }
                    }
                    .tag(Optional(p.id))
                }
            }
            Divider()
            HStack {
                Button { model.addPhrase() } label: { Image(systemName: "plus") }
                Button { model.duplicateSelectedPhrase() } label: { Image(systemName: "plus.square.on.square") }
                    .disabled(model.selectedPhraseID == nil)
                Button {
                    if let id = model.selectedPhraseID { model.deletePhrase(id) }
                } label: { Image(systemName: "minus") }
                    .disabled(model.selectedPhraseID == nil || model.phrases.count <= 1)
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(6)
        }
    }

    func stepEditor(index i: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Name", text: $model.phrases[i].name).frame(width: 220)
                Toggle("Loop", isOn: $model.phrases[i].loop)
                Spacer()
                Text("\(model.phrases[i].totalMs) ms").foregroundStyle(.secondary).monospacedDigit()
            }
            Text("Notes as names (C4 E4 G4) or numbers; leave blank for a rest. Gate = how long the keys are held, Gap = silence after.")
                .font(.caption).foregroundStyle(.secondary)
            List {
                ForEach($model.phrases[i].steps) { $step in
                    StepRow(step: $step)
                }
                .onDelete { model.phrases[i].steps.remove(atOffsets: $0) }
                .onMove { model.phrases[i].steps.move(fromOffsets: $0, toOffset: $1) }
            }
            HStack {
                Button {
                    let last = model.phrases[i].steps.last
                    model.phrases[i].steps.append(PhraseStep(notes: last?.notes ?? [60], velocity: last?.velocity ?? 100,
                                                             durationMs: last?.durationMs ?? 400, gapMs: last?.gapMs ?? 60))
                } label: { Label("Add step", systemImage: "plus") }
                Button {
                    if !model.phrases[i].steps.isEmpty { model.phrases[i].steps.removeLast() }
                } label: { Label("Remove last", systemImage: "minus") }
                    .disabled(model.phrases[i].steps.count <= 1)
            }
        }
        .padding(10)
    }
}

struct StepRow: View {
    @Binding var step: PhraseStep
    @State private var text = ""
    @State private var valid = true

    var body: some View {
        HStack(spacing: 12) {
            TextField("C4 E4 G4", text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
                .foregroundColor(valid ? .primary : .red)
            Stepper(value: $step.velocity, in: 1...127, step: 5) {
                Text("Vel \(step.velocity)").monospacedDigit().frame(width: 60, alignment: .leading)
            }
            Stepper(value: $step.durationMs, in: 20...8000, step: 20) {
                Text("Gate \(step.durationMs) ms").monospacedDigit().frame(width: 100, alignment: .leading)
            }
            Stepper(value: $step.gapMs, in: 0...4000, step: 20) {
                Text("Gap \(step.gapMs) ms").monospacedDigit().frame(width: 90, alignment: .leading)
            }
            Spacer()
        }
        .onAppear { text = step.notesText }
        .onChange(of: text) { newValue in
            if let notes = TestPhrase.parseNotes(newValue) {
                step.notes = notes
                valid = true
            } else {
                valid = false
            }
        }
    }
}
#endif
