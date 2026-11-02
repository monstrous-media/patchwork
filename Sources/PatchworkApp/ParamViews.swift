#if os(macOS)
import SwiftUI
import PatchworkCore

/// Renders one parameter from `ParameterMap` with the right control for its kind.
struct ParamRow: View {
    let def: ParamDef
    @EnvironmentObject var model: AppModel

    var body: some View {
        switch def.kind {
        case .ascii:
            LabeledRow(title: def.name) {
                TextField("Program name", text: model.nameBinding)
                    .textFieldStyle(.plain)
                    .font(Theme.lcd)
                    .foregroundStyle(Theme.wellAccent)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: Theme.controlRadius).fill(Theme.well))
                    .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).stroke(Theme.line, lineWidth: 1))
                    .frame(maxWidth: 220)
                Text("\(model.program.name.count)/10").font(Theme.monoCaption).foregroundStyle(Theme.faint)
            }
        case .unsigned(let mx):
            SliderRow(title: def.name, value: model.unsignedBinding(def.index), range: 0...mx)
        case .signed(let mn, let mx):
            SliderRow(title: def.name, value: model.signedBinding(def.index), range: mn...mx)
        case .choice(let labels):
            LabeledRow(title: def.name) {
                Picker("", selection: model.unsignedBinding(def.index)) {
                    ForEach(0..<labels.count, id: \.self) { i in Text(labels[i]).tag(i) }
                }
                .labelsHidden().frame(maxWidth: 220)
            }
        case .bits(let fields):
            LabeledRow(title: def.name) {
                // Wraps into as many columns as fit instead of squeezing the labels off the checkboxes.
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 10, alignment: .leading)],
                          alignment: .leading, spacing: 4) {
                    ForEach(fields, id: \.name) { f in
                        if f.width == 1 {
                            Toggle(f.name, isOn: model.bitBinding(def.index, bit: f.shift)).toggleStyle(.checkbox).fixedSize()
                        } else {
                            Picker(f.name, selection: model.fieldBinding(def.index, shift: f.shift, width: f.width)) {
                                ForEach(0..<f.labels.count, id: \.self) { i in Text(f.labels[i]).tag(i) }
                            }
                            .frame(maxWidth: 200)
                        }
                    }
                }
            }
        case .note:
            LabeledRow(title: def.name) {
                let b = model.unsignedBinding(def.index)
                Stepper(value: b, in: 0...127) {
                    Text(NoteName.string(for: b.wrappedValue)).font(Theme.value).foregroundStyle(Theme.accent).frame(width: 40, alignment: .leading)
                }
                Slider(value: doubleBinding(b), in: 0...127, step: 1).frame(maxWidth: 200)
            }
        case .multisound:
            let drums = model.program.unsigned(P.oscMode) == 2 && def.index == P.osc1Multisound
            LabeledRow(title: drums ? "OSC1 drum kit" : def.name) {
                Picker("", selection: model.unsignedBinding(def.index)) {
                    if drums {
                        ForEach(0..<4, id: \.self) { i in Text("Drum Kit \(i + 1)").tag(i) }
                    } else {
                        ForEach(0..<Multisounds.names.count, id: \.self) { i in
                            Text("\(i)  \(Multisounds.names[i])").tag(i)
                        }
                        ForEach(100..<120, id: \.self) { i in Text("Card \(i - 100)").tag(i) }
                    }
                }
                .labelsHidden().frame(maxWidth: 220)
                if drums {
                    Text("per-key sounds live in the M1's Global data (kit editor: later)").font(.caption).foregroundStyle(.secondary)
                }
            }
        case .octave:
            LabeledRow(title: def.name) {
                Picker("", selection: model.signedBinding(def.index)) {
                    Text("16'").tag(-1)
                    Text("8'").tag(0)
                    Text("4'").tag(1)
                }
                .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 160)
            }
        case .pan:
            PanRow(title: def.name, value: model.unsignedBinding(def.index))
        case .effectType:
            LabeledRow(title: def.name) {
                Picker("", selection: model.unsignedBinding(def.index)) {
                    Text("Thru").tag(EffectTypes.thruValue)
                    ForEach(0..<EffectTypes.names.count, id: \.self) { i in
                        Text("\(i + 1)  \(EffectTypes.names[i])").tag(i)
                    }
                }
                .labelsHidden().frame(maxWidth: 220)
            }
        case .effectParam(let effect, let slot):
            let typeIndex = effect == 1 ? P.effect1Type : P.effect2Type
            let labels = EffectTypes.parameterLabels(for: model.program.unsigned(typeIndex))
            let label = slot < labels.count ? labels[slot] : "Param \(slot + 1)"
            if label != "—" {
                SliderRow(title: "FX\(effect) \(label)", value: model.unsignedBinding(def.index), range: 0...255)
            }
        }
    }

    func doubleBinding(_ b: Binding<Int>) -> Binding<Double> {
        Binding(get: { Double(b.wrappedValue) }, set: { b.wrappedValue = Int($0.rounded()) })
    }
}

/// Row label: fixed column so sliders line up across cards; long names shrink a little, then truncate
/// (the full name is in the row's tooltip).
struct RowLabel: View {
    let title: String
    static let width: CGFloat = 148
    var body: some View {
        Text(title).font(.system(size: 12.5)).foregroundStyle(Theme.muted)
            .lineLimit(1).minimumScaleFactor(0.85).truncationMode(.tail)
            .frame(width: RowLabel.width, alignment: .leading)
    }
}

struct LabeledRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        HStack {
            RowLabel(title: title)
            content()
            Spacer(minLength: 0)
        }
        .frame(minHeight: 24)
    }
}

struct SliderRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        HStack {
            RowLabel(title: title)
            Slider(value: Binding(get: { Double(value) }, set: { value = Int($0.rounded()) }),
                   in: Double(range.lowerBound)...Double(range.upperBound), step: 1)
                .frame(minWidth: 80)
            Stepper(value: $value, in: range) {
                Text(value > 0 && range.lowerBound < 0 ? "+\(value)" : "\(value)")
                    .font(Theme.value).foregroundStyle(Theme.accent).frame(width: 40, alignment: .trailing)
            }
        }
        .frame(minHeight: 24)
    }
}

/// Output 3/4 pan: 0 = off, 1 = fully right … 101 = fully left.
struct PanRow: View {
    let title: String
    @Binding var value: Int

    var body: some View {
        HStack {
            RowLabel(title: title)
            Toggle("On", isOn: Binding(get: { value != 0 }, set: { value = $0 ? 51 : 0 })).toggleStyle(.checkbox)
            if value != 0 {
                Text("R").font(.caption)
                Slider(value: Binding(get: { Double(value - 1) }, set: { value = Int($0.rounded()) + 1 }), in: 0...100, step: 1)
                    .frame(maxWidth: 200)
                Text("L").font(.caption)
                Text("\(100 - (value - 1)):\(value - 1)").font(Theme.value).foregroundStyle(Theme.accent).frame(width: 50)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 24)
    }
}

/// A titled group of parameter rows. Rows a generator just changed glow briefly.
struct SectionBox: View {
    let section: ParamSection
    var envelope: EnvelopeSpec? = nil
    @EnvironmentObject var model: AppModel

    /// Parameter byte range of the section, e.g. "P63–P80", so the UI and the SysEx map read alike.
    var byteRange: String? {
        let idx = ActiveSynth.definitions(in: section).map(\.index)
        guard let lo = idx.min(), let hi = idx.max() else { return nil }
        return lo == hi ? "P\(lo)" : "P\(lo)–P\(hi)"
    }

    var body: some View {
        SectionCard(title: section.rawValue, caption: byteRange) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(ActiveSynth.definitions(in: section)) { def in
                    ParamRow(def: def)
                        .help(ActiveSynth.help(for: def))
                        .padding(.horizontal, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Theme.accent.opacity(model.highlighted.contains(def.index) ? 0.22 : 0))
                        )
                        .animation(.easeOut(duration: 0.6), value: model.highlighted)
                }
                if let e = envelope {
                    EnvelopeSketch(attack: model.program.unsigned(e.attackTime),
                                   attackLevel: e.signedLevels ? model.program.signed(e.attackLevel) : model.program.unsigned(e.attackLevel),
                                   decay: model.program.unsigned(e.decayTime),
                                   breakPoint: e.signedLevels ? model.program.signed(e.breakPoint) : model.program.unsigned(e.breakPoint),
                                   slope: model.program.unsigned(e.slopeTime),
                                   sustain: e.signedLevels ? model.program.signed(e.sustainLevel) : model.program.unsigned(e.sustainLevel),
                                   release: model.program.unsigned(e.releaseTime),
                                   signedLevels: e.signedLevels)
                        .padding(.top, 6)
                }
            }
        }
    }
}

/// Tiny envelope sketch for the VDA/VDF EG groups — purely illustrative.
struct EnvelopeSketch: View {
    let attack: Int, attackLevel: Int, decay: Int, breakPoint: Int, slope: Int, sustain: Int, release: Int
    let signedLevels: Bool

    var body: some View {
        GeometryReader { geo in
            Path { path in
                let w = geo.size.width, h = geo.size.height
                func y(_ level: Int) -> CGFloat {
                    let n = signedLevels ? (Double(level) + 99) / 198 : Double(level) / 99
                    return h - CGFloat(n) * h
                }
                let total = Double(attack + decay + slope + release + 20)
                var x: CGFloat = 0
                path.move(to: CGPoint(x: 0, y: signedLevels ? h / 2 : h))
                x += w * CGFloat(Double(attack) / total); path.addLine(to: CGPoint(x: x, y: y(attackLevel)))
                x += w * CGFloat(Double(decay) / total); path.addLine(to: CGPoint(x: x, y: y(breakPoint)))
                x += w * CGFloat(Double(slope) / total); path.addLine(to: CGPoint(x: x, y: y(sustain)))
                x += w * CGFloat(20 / total); path.addLine(to: CGPoint(x: x, y: y(sustain)))
                x += w * CGFloat(Double(release) / total); path.addLine(to: CGPoint(x: x, y: signedLevels ? h / 2 : h))
            }
            .stroke(Theme.wellAccent, lineWidth: 2)
        }
        .frame(height: 56)
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: Theme.controlRadius).fill(Theme.well))
        .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).stroke(Theme.line, lineWidth: 1))
    }
}
#endif
