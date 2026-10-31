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
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                Text("\(model.program.name.count)/10").foregroundStyle(.secondary).font(.caption)
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
                HStack(spacing: 14) {
                    ForEach(fields, id: \.name) { f in
                        if f.width == 1 {
                            Toggle(f.name, isOn: model.bitBinding(def.index, bit: f.shift)).toggleStyle(.checkbox)
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
                    Text(NoteName.string(for: b.wrappedValue)).monospacedDigit().frame(width: 40, alignment: .leading)
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

struct LabeledRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        HStack {
            Text(title).frame(width: 190, alignment: .leading).foregroundStyle(.secondary)
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
            Text(title).frame(width: 190, alignment: .leading).foregroundStyle(.secondary)
            Slider(value: Binding(get: { Double(value) }, set: { value = Int($0.rounded()) }),
                   in: Double(range.lowerBound)...Double(range.upperBound), step: 1)
            Stepper(value: $value, in: range) {
                Text(value > 0 && range.lowerBound < 0 ? "+\(value)" : "\(value)")
                    .monospacedDigit().frame(width: 36, alignment: .trailing)
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
            Text(title).frame(width: 190, alignment: .leading).foregroundStyle(.secondary)
            Toggle("On", isOn: Binding(get: { value != 0 }, set: { value = $0 ? 51 : 0 })).toggleStyle(.checkbox)
            if value != 0 {
                Text("R").font(.caption)
                Slider(value: Binding(get: { Double(value - 1) }, set: { value = Int($0.rounded()) + 1 }), in: 0...100, step: 1)
                    .frame(maxWidth: 200)
                Text("L").font(.caption)
                Text("\(100 - (value - 1)):\(value - 1)").monospacedDigit().font(.caption).frame(width: 50)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 24)
    }
}

/// A titled group of parameter rows. Rows a generator just changed glow briefly.
struct SectionBox: View {
    let section: ParamSection
    @EnvironmentObject var model: AppModel

    var body: some View {
        GroupBox(section.rawValue) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(ActiveSynth.definitions(in: section)) { def in
                    ParamRow(def: def)
                        .help(ActiveSynth.help(for: def))
                        .padding(.horizontal, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.accentColor.opacity(model.highlighted.contains(def.index) ? 0.22 : 0))
                        )
                        .animation(.easeOut(duration: 0.6), value: model.highlighted)
                }
            }
            .padding(6)
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
            .stroke(Color.accentColor, lineWidth: 1.5)
        }
        .frame(height: 48)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(4)
    }
}
#endif
