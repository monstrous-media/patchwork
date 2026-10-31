import Foundation

/// Human-readable, JSON-friendly representation of an M1 program — the format Claude (or a
/// person) authors patches in. Converts losslessly to/from the 143 raw bytes for all documented
/// fields. See `schema/m1-patch.schema.json` and `skills/korg-m1-patch/SKILL.md`.
public struct M1Patch: Codable, Equatable {

    public static let formatID = "korg-m1-program/1"

    /// Always "korg-m1-program/1". Optional on decode so a missing key gives a clear error rather than a DecodingError.
    public var format: String? = M1Patch.formatID
    public var name: String
    /// "single", "double" or "drums"
    public var oscillatorMode: String
    /// "poly" or "mono"
    public var assign: String
    public var hold: Bool
    public var osc1: Oscillator
    public var osc2: Oscillator2
    public var pitchMG: MG
    public var vdfMG: MG
    public var aftertouch: Aftertouch
    public var joystick: Joystick
    public var effects: Effects
    public var voice1: Voice
    public var voice2: Voice

    public struct Oscillator: Codable, Equatable {
        /// Multisound name (e.g. "Strings"), "card:N", or number 0–99.
        public var multisound: String
        /// "16'", "8'" or "4'"
        public var octave: String
    }

    public struct Oscillator2: Codable, Equatable {
        public var multisound: String
        public var octave: String
        public var interval: Int      // -12…+12 semitones
        public var detune: Int        // -50…+50 cents
        public var delayStart: Int    // 0–99
    }

    public struct MG: Codable, Equatable {
        /// "triangle", "saw up", "saw down", "square"
        public var waveform: String
        public var frequency: Int     // 0–99
        public var delay: Int         // 0–99
        public var intensity: Int     // 0–99
        public var osc1: Bool
        public var osc2: Bool
        public var keySync: Bool
    }

    public struct Aftertouch: Codable, Equatable {
        public var pitch: Int         // -12…+12
        public var pitchMG: Int       // 0–99
        public var vdfCutoff: Int     // -99…+99
        public var vdfMG: Int         // 0–99
        public var vdaAmplitude: Int  // -99…+99
    }

    public struct Joystick: Codable, Equatable {
        public var pitchBend: Int           // -12…+12
        public var vdfSweep: Int            // -99…+99
        public var pitchMGIntensity: Int    // 0–99
        public var pitchMGFrequency: Int    // 0–3
        public var vdfMGIntensity: Int      // 0–99
        public var vdfMGFrequency: Int      // 0–3
    }

    public struct Effect: Codable, Equatable {
        /// Effect name (e.g. "Hall", "Stereo Chorus I"), 1-based number, or "thru".
        public var type: String
        public var balanceL: Int            // 0–100
        public var balanceR: Int            // 0–100
        public var leftOn: Bool
        public var rightOn: Bool
        /// The 8 raw effect parameter bytes (0–255). Meaning depends on `type`;
        /// see EffectTypes.parameterLabels. Omit to keep the init values.
        public var params: [Int]?
    }

    public struct Effects: Codable, Equatable {
        public var effect1: Effect
        public var effect2: Effect
        public var serial: Bool
        /// nil = off, otherwise 0 (fully right) … 100 (fully left)
        public var output3Pan: Int?
        public var output4Pan: Int?
    }

    public struct PitchEG: Codable, Equatable {
        public var startLevel: Int        // -99…+99
        public var attackTime: Int        // 0–99
        public var attackLevel: Int       // -99…+99
        public var decayTime: Int
        public var releaseTime: Int
        public var releaseLevel: Int      // -99…+99
        public var timeVelocitySens: Int  // -99…+99
        public var levelVelocitySens: Int // -99…+99
    }

    public struct VDFEG: Codable, Equatable {
        public var attackTime: Int
        public var attackLevel: Int   // -99…+99
        public var decayTime: Int
        public var breakPoint: Int    // -99…+99
        public var slopeTime: Int
        public var sustainLevel: Int  // -99…+99
        public var releaseTime: Int
        public var releaseLevel: Int  // -99…+99
    }

    public struct VDAEG: Codable, Equatable {
        public var attackTime: Int
        public var attackLevel: Int   // 0–99
        public var decayTime: Int
        public var breakPoint: Int    // 0–99
        public var slopeTime: Int
        public var sustainLevel: Int  // 0–99
        public var releaseTime: Int
    }

    public struct TimeSwitches: Codable, Equatable {
        public var attack: Bool
        public var decay: Bool
        public var slope: Bool
        public var release: Bool
        /// false = "+", true = "−"
        public var negative: Bool
        public init(attack: Bool = false, decay: Bool = false, slope: Bool = false, release: Bool = false, negative: Bool = false) {
            self.attack = attack; self.decay = decay; self.slope = slope; self.release = release; self.negative = negative
        }
    }

    public struct VDF: Codable, Equatable {
        public var cutoff: Int                 // 0–99
        public var kbdTrackCenter: String      // note name, e.g. "C4"
        public var cutoffKbdTrack: Int         // -99…+99
        public var egIntensity: Int            // 0–99
        public var egTimeKbdTrack: Int         // 0–99
        public var egTimeVelocitySens: Int     // 0–99
        public var egIntensityVelocitySens: Int // -99…+99
        public var eg: VDFEG
        public var egTimeKbdTrackSwitches: TimeSwitches?
        public var egTimeVelocitySwitches: TimeSwitches?
    }

    public struct VDA: Codable, Equatable {
        public var level: Int                  // 0–99
        public var kbdTrackCenter: String
        public var kbdTrackIntensity: Int      // -99…+99
        public var velocitySens: Int           // -99…+99
        public var egTimeKbdTrack: Int         // 0–99
        public var egTimeVelocitySens: Int     // 0–99
        public var eg: VDAEG
        public var egTimeKbdTrackSwitches: TimeSwitches?
        public var egTimeVelocitySwitches: TimeSwitches?
    }

    public struct Voice: Codable, Equatable {
        public var pitchEG: PitchEG
        public var vdf: VDF
        public var vda: VDA
    }

    // MARK: - From program bytes

    public init(program p: M1Program) {
        name = p.name
        oscillatorMode = ["single", "double", "drums"][min(2, p.unsigned(P.oscMode))]
        assign = p.bit(P.assignHold, 0) ? "mono" : "poly"
        hold = p.bit(P.assignHold, 1)
        let kit = p.unsigned(P.osc1Multisound)
        let drums = p.unsigned(P.oscMode) == 2 && kit < 4
        osc1 = Oscillator(multisound: drums ? "Drum Kit \(kit + 1)" : Multisounds.name(for: kit),
                          octave: M1Patch.octaveString(p.signed(P.osc1Octave)))
        osc2 = Oscillator2(multisound: Multisounds.name(for: p.unsigned(P.osc2Multisound)),
                           octave: M1Patch.octaveString(p.signed(P.osc2Octave)),
                           interval: p.signed(P.osc2Interval),
                           detune: p.signed(P.osc2Detune),
                           delayStart: p.unsigned(P.osc2DelayStart))
        pitchMG = M1Patch.mg(p, flags: P.pitchMGFlags, freq: P.pitchMGFreq, delay: P.pitchMGDelay, intensity: P.pitchMGIntensity)
        vdfMG = M1Patch.mg(p, flags: P.vdfMGFlags, freq: P.vdfMGFreq, delay: P.vdfMGDelay, intensity: P.vdfMGIntensity)
        aftertouch = Aftertouch(pitch: p.signed(P.atPitch), pitchMG: p.unsigned(P.atPitchMG),
                                vdfCutoff: p.signed(P.atVDFCutoff), vdfMG: p.unsigned(P.atVDFMG),
                                vdaAmplitude: p.signed(P.atVDAAmplitude))
        joystick = Joystick(pitchBend: p.signed(P.jsPitchBend), vdfSweep: p.signed(P.jsVDFSweep),
                            pitchMGIntensity: p.unsigned(P.jsPitchMGIntensity), pitchMGFrequency: p.unsigned(P.jsPitchMGFreq),
                            vdfMGIntensity: p.unsigned(P.jsVDFMGIntensity), vdfMGFrequency: p.unsigned(P.jsVDFMGFreq))
        effects = Effects(
            effect1: Effect(type: EffectTypes.name(for: p.unsigned(P.effect1Type)),
                            balanceL: p.unsigned(P.effect1BalL), balanceR: p.unsigned(P.effect1BalR),
                            leftOn: p.bit(P.effectIO, 0), rightOn: p.bit(P.effectIO, 1),
                            params: (0..<8).map { p.unsigned(P.effect1Params + $0) }),
            effect2: Effect(type: EffectTypes.name(for: p.unsigned(P.effect2Type)),
                            balanceL: p.unsigned(P.effect2BalL), balanceR: p.unsigned(P.effect2BalR),
                            leftOn: p.bit(P.effectIO, 2), rightOn: p.bit(P.effectIO, 3),
                            params: (0..<8).map { p.unsigned(P.effect2Params + $0) }),
            serial: p.bit(P.effectIO, 4),
            output3Pan: M1Patch.panValue(p.unsigned(P.output3Pan)),
            output4Pan: M1Patch.panValue(p.unsigned(P.output4Pan)))
        voice1 = M1Patch.voice(p, base: P.voice1Base)
        voice2 = M1Patch.voice(p, base: P.voice2Base)
    }

    static func mg(_ p: M1Program, flags: Int, freq: Int, delay: Int, intensity: Int) -> MG {
        let wf = p.field(flags, shift: 0, width: 2)
        return MG(waveform: ["triangle", "saw up", "saw down", "square"][wf],
                  frequency: p.unsigned(freq), delay: p.unsigned(delay), intensity: p.unsigned(intensity),
                  osc1: p.bit(flags, 5), osc2: p.bit(flags, 6), keySync: p.bit(flags, 7))
    }

    static func switches(_ p: M1Program, _ i: Int) -> TimeSwitches {
        TimeSwitches(attack: p.bit(i, 0), decay: p.bit(i, 1), slope: p.bit(i, 2), release: p.bit(i, 3), negative: p.bit(i, 4))
    }

    static func voice(_ p: M1Program, base b: Int) -> Voice {
        let peg = PitchEG(startLevel: p.signed(b + V.pegStartLevel), attackTime: p.unsigned(b + V.pegAttackTime),
                          attackLevel: p.signed(b + V.pegAttackLevel), decayTime: p.unsigned(b + V.pegDecayTime),
                          releaseTime: p.unsigned(b + V.pegReleaseTime), releaseLevel: p.signed(b + V.pegReleaseLevel),
                          timeVelocitySens: p.signed(b + V.pegTimeVelSens), levelVelocitySens: p.signed(b + V.pegLevelVelSens))
        let vdf = VDF(cutoff: p.unsigned(b + V.vdfCutoff),
                      kbdTrackCenter: NoteName.string(for: p.unsigned(b + V.vdfKbdTrackCenter)),
                      cutoffKbdTrack: p.signed(b + V.vdfCutoffKbdTrack),
                      egIntensity: p.unsigned(b + V.vdfEGIntensity),
                      egTimeKbdTrack: p.unsigned(b + V.vdfEGTimeKbdTrack),
                      egTimeVelocitySens: p.unsigned(b + V.vdfEGTimeVelSens),
                      egIntensityVelocitySens: p.signed(b + V.vdfEGIntVelSens),
                      eg: VDFEG(attackTime: p.unsigned(b + V.vdfEGAttackTime), attackLevel: p.signed(b + V.vdfEGAttackLevel),
                                decayTime: p.unsigned(b + V.vdfEGDecayTime), breakPoint: p.signed(b + V.vdfEGBreakPoint),
                                slopeTime: p.unsigned(b + V.vdfEGSlopeTime), sustainLevel: p.signed(b + V.vdfEGSustainLevel),
                                releaseTime: p.unsigned(b + V.vdfEGReleaseTime), releaseLevel: p.signed(b + V.vdfEGReleaseLevel)),
                      egTimeKbdTrackSwitches: switches(p, b + V.vdfEGTimeKbdTrackSwitches),
                      egTimeVelocitySwitches: switches(p, b + V.vdfEGTimeVelSwitches))
        let vda = VDA(level: p.unsigned(b + V.vdaLevel),
                      kbdTrackCenter: NoteName.string(for: p.unsigned(b + V.vdaKbdTrackCenter)),
                      kbdTrackIntensity: p.signed(b + V.vdaKbdTrackIntensity),
                      velocitySens: p.signed(b + V.vdaVelocitySens),
                      egTimeKbdTrack: p.unsigned(b + V.vdaEGTimeKbdTrack),
                      egTimeVelocitySens: p.unsigned(b + V.vdaEGTimeVelSens),
                      eg: VDAEG(attackTime: p.unsigned(b + V.vdaEGAttackTime), attackLevel: p.unsigned(b + V.vdaEGAttackLevel),
                                decayTime: p.unsigned(b + V.vdaEGDecayTime), breakPoint: p.unsigned(b + V.vdaEGBreakPoint),
                                slopeTime: p.unsigned(b + V.vdaEGSlopeTime), sustainLevel: p.unsigned(b + V.vdaEGSustainLevel),
                                releaseTime: p.unsigned(b + V.vdaEGReleaseTime)),
                      egTimeKbdTrackSwitches: switches(p, b + V.vdaEGTimeKbdTrackSwitches),
                      egTimeVelocitySwitches: switches(p, b + V.vdaEGTimeVelSwitches))
        return Voice(pitchEG: peg, vdf: vdf, vda: vda)
    }

    static func octaveString(_ v: Int) -> String {
        switch v {
        case -1: return "16'"
        case 1: return "4'"
        default: return "8'"
        }
    }

    static func panValue(_ raw: Int) -> Int? {
        if raw == 0 { return nil }
        return max(0, min(100, raw - 1))
    }

    // MARK: - To program bytes

    /// Build the 143 bytes. Throws `M1Error.invalidValue` naming the offending field.
    public func toProgram() throws -> M1Program {
        var p = M1Program()
        p.name = name

        p.setUnsigned(P.oscMode, try M1Patch.choice(oscillatorMode, ["single", "double", "drums"], field: "oscillatorMode"))
        p.setBit(P.assignHold, 0, try M1Patch.choice(assign, ["poly", "mono"], field: "assign") == 1)
        p.setBit(P.assignHold, 1, hold)

        p.setUnsigned(P.osc1Multisound, try M1Patch.multisound(osc1.multisound, field: "osc1.multisound"))
        p.setSigned(P.osc1Octave, try M1Patch.octave(osc1.octave, field: "osc1.octave"))
        p.setUnsigned(P.osc2Multisound, try M1Patch.multisound(osc2.multisound, field: "osc2.multisound"))
        p.setSigned(P.osc2Octave, try M1Patch.octave(osc2.octave, field: "osc2.octave"))
        p.setSigned(P.osc2Interval, try M1Patch.range(osc2.interval, -12, 12, "osc2.interval"))
        p.setSigned(P.osc2Detune, try M1Patch.range(osc2.detune, -50, 50, "osc2.detune"))
        p.setUnsigned(P.osc2DelayStart, try M1Patch.range(osc2.delayStart, 0, 99, "osc2.delayStart"))

        try M1Patch.apply(mg: pitchMG, to: &p, flags: P.pitchMGFlags, freq: P.pitchMGFreq, delay: P.pitchMGDelay, intensity: P.pitchMGIntensity, field: "pitchMG")
        try M1Patch.apply(mg: vdfMG, to: &p, flags: P.vdfMGFlags, freq: P.vdfMGFreq, delay: P.vdfMGDelay, intensity: P.vdfMGIntensity, field: "vdfMG")

        p.setSigned(P.atPitch, try M1Patch.range(aftertouch.pitch, -12, 12, "aftertouch.pitch"))
        p.setUnsigned(P.atPitchMG, try M1Patch.range(aftertouch.pitchMG, 0, 99, "aftertouch.pitchMG"))
        p.setSigned(P.atVDFCutoff, try M1Patch.range(aftertouch.vdfCutoff, -99, 99, "aftertouch.vdfCutoff"))
        p.setUnsigned(P.atVDFMG, try M1Patch.range(aftertouch.vdfMG, 0, 99, "aftertouch.vdfMG"))
        p.setSigned(P.atVDAAmplitude, try M1Patch.range(aftertouch.vdaAmplitude, -99, 99, "aftertouch.vdaAmplitude"))

        p.setSigned(P.jsPitchBend, try M1Patch.range(joystick.pitchBend, -12, 12, "joystick.pitchBend"))
        p.setSigned(P.jsVDFSweep, try M1Patch.range(joystick.vdfSweep, -99, 99, "joystick.vdfSweep"))
        p.setUnsigned(P.jsPitchMGIntensity, try M1Patch.range(joystick.pitchMGIntensity, 0, 99, "joystick.pitchMGIntensity"))
        p.setUnsigned(P.jsPitchMGFreq, try M1Patch.range(joystick.pitchMGFrequency, 0, 3, "joystick.pitchMGFrequency"))
        p.setUnsigned(P.jsVDFMGIntensity, try M1Patch.range(joystick.vdfMGIntensity, 0, 99, "joystick.vdfMGIntensity"))
        p.setUnsigned(P.jsVDFMGFreq, try M1Patch.range(joystick.vdfMGFrequency, 0, 3, "joystick.vdfMGFrequency"))

        try M1Patch.apply(effect: effects.effect1, to: &p, type: P.effect1Type, balL: P.effect1BalL, balR: P.effect1BalR,
                          params: P.effect1Params, ioBitL: 0, ioBitR: 1, field: "effects.effect1")
        try M1Patch.apply(effect: effects.effect2, to: &p, type: P.effect2Type, balL: P.effect2BalL, balR: P.effect2BalR,
                          params: P.effect2Params, ioBitL: 2, ioBitR: 3, field: "effects.effect2")
        p.setBit(P.effectIO, 4, effects.serial)
        p.setUnsigned(P.output3Pan, try M1Patch.pan(effects.output3Pan, field: "effects.output3Pan"))
        p.setUnsigned(P.output4Pan, try M1Patch.pan(effects.output4Pan, field: "effects.output4Pan"))

        try M1Patch.apply(voice: voice1, to: &p, base: P.voice1Base, field: "voice1")
        try M1Patch.apply(voice: voice2, to: &p, base: P.voice2Base, field: "voice2")
        return p
    }

    static func range(_ v: Int, _ lo: Int, _ hi: Int, _ field: String) throws -> Int {
        guard v >= lo && v <= hi else { throw M1Error.invalidValue(field: field, reason: "\(v) is outside \(lo)…\(hi)") }
        return v
    }

    static func choice(_ s: String, _ options: [String], field: String) throws -> Int {
        let key = s.trimmingCharacters(in: .whitespaces).lowercased()
        guard let i = options.firstIndex(of: key) else {
            throw M1Error.invalidValue(field: field, reason: "“\(s)” is not one of \(options.joined(separator: ", "))")
        }
        return i
    }

    static func multisound(_ s: String, field: String) throws -> Int {
        let k = s.lowercased().trimmingCharacters(in: .whitespaces)
        if k.hasPrefix("drum kit ") || k.hasPrefix("kit:") {
            guard let n = Int(k.replacingOccurrences(of: "drum kit ", with: "").replacingOccurrences(of: "kit:", with: "")), (1...4).contains(n) else {
                throw M1Error.invalidValue(field: field, reason: "drum kit must be 1…4")
            }
            return n - 1
        }
        guard let v = Multisounds.value(for: s), v <= 255 else {
            throw M1Error.invalidValue(field: field, reason: "unknown multisound “\(s)”")
        }
        return v
    }

    static func octave(_ s: String, field: String) throws -> Int {
        switch s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "’", with: "'") {
        case "16'", "16", "-1": return -1
        case "8'", "8", "0": return 0
        case "4'", "4", "1": return 1
        default: throw M1Error.invalidValue(field: field, reason: "“\(s)” must be 16', 8' or 4'")
        }
    }

    static func pan(_ v: Int?, field: String) throws -> Int {
        guard let v = v else { return 0 }
        return try range(v, 0, 100, field) + 1
    }

    static func note(_ s: String, field: String) throws -> Int {
        guard let v = NoteName.value(for: s) else {
            throw M1Error.invalidValue(field: field, reason: "“\(s)” is not a note name like C4 or F#2")
        }
        return v
    }

    static func apply(mg: MG, to p: inout M1Program, flags: Int, freq: Int, delay: Int, intensity: Int, field: String) throws {
        let wf = try choice(mg.waveform, ["triangle", "saw up", "saw down", "square"], field: field + ".waveform")
        p.setField(flags, shift: 0, width: 2, wf)
        p.setBit(flags, 5, mg.osc1)
        p.setBit(flags, 6, mg.osc2)
        p.setBit(flags, 7, mg.keySync)
        p.setUnsigned(freq, try range(mg.frequency, 0, 99, field + ".frequency"))
        p.setUnsigned(delay, try range(mg.delay, 0, 99, field + ".delay"))
        p.setUnsigned(intensity, try range(mg.intensity, 0, 99, field + ".intensity"))
    }

    static func apply(effect e: Effect, to p: inout M1Program, type: Int, balL: Int, balR: Int, params: Int,
                      ioBitL: Int, ioBitR: Int, field: String) throws {
        guard let t = EffectTypes.value(for: e.type) else {
            throw M1Error.invalidValue(field: field + ".type", reason: "unknown effect “\(e.type)”")
        }
        p.setUnsigned(type, t)
        p.setUnsigned(balL, try range(e.balanceL, 0, 100, field + ".balanceL"))
        p.setUnsigned(balR, try range(e.balanceR, 0, 100, field + ".balanceR"))
        p.setBit(P.effectIO, ioBitL, e.leftOn)
        p.setBit(P.effectIO, ioBitR, e.rightOn)
        if let ps = e.params {
            guard ps.count == 8 else { throw M1Error.invalidValue(field: field + ".params", reason: "needs exactly 8 values") }
            for (i, v) in ps.enumerated() {
                p.setUnsigned(params + i, try range(v, 0, 255, field + ".params[\(i)]"))
            }
        }
    }

    static func apply(switches s: TimeSwitches?, to p: inout M1Program, at i: Int) {
        let sw = s ?? TimeSwitches()
        p.setBit(i, 0, sw.attack); p.setBit(i, 1, sw.decay); p.setBit(i, 2, sw.slope); p.setBit(i, 3, sw.release)
        p.setBit(i, 4, sw.negative)
    }

    static func apply(voice v: Voice, to p: inout M1Program, base b: Int, field f: String) throws {
        let e = v.pitchEG
        p.setSigned(b + V.pegStartLevel, try range(e.startLevel, -99, 99, f + ".pitchEG.startLevel"))
        p.setUnsigned(b + V.pegAttackTime, try range(e.attackTime, 0, 99, f + ".pitchEG.attackTime"))
        p.setSigned(b + V.pegAttackLevel, try range(e.attackLevel, -99, 99, f + ".pitchEG.attackLevel"))
        p.setUnsigned(b + V.pegDecayTime, try range(e.decayTime, 0, 99, f + ".pitchEG.decayTime"))
        p.setUnsigned(b + V.pegReleaseTime, try range(e.releaseTime, 0, 99, f + ".pitchEG.releaseTime"))
        p.setSigned(b + V.pegReleaseLevel, try range(e.releaseLevel, -99, 99, f + ".pitchEG.releaseLevel"))
        p.setSigned(b + V.pegTimeVelSens, try range(e.timeVelocitySens, -99, 99, f + ".pitchEG.timeVelocitySens"))
        p.setSigned(b + V.pegLevelVelSens, try range(e.levelVelocitySens, -99, 99, f + ".pitchEG.levelVelocitySens"))

        let d = v.vdf
        p.setUnsigned(b + V.vdfCutoff, try range(d.cutoff, 0, 99, f + ".vdf.cutoff"))
        p.setUnsigned(b + V.vdfKbdTrackCenter, try note(d.kbdTrackCenter, field: f + ".vdf.kbdTrackCenter"))
        p.setSigned(b + V.vdfCutoffKbdTrack, try range(d.cutoffKbdTrack, -99, 99, f + ".vdf.cutoffKbdTrack"))
        p.setUnsigned(b + V.vdfEGIntensity, try range(d.egIntensity, 0, 99, f + ".vdf.egIntensity"))
        p.setUnsigned(b + V.vdfEGTimeKbdTrack, try range(d.egTimeKbdTrack, 0, 99, f + ".vdf.egTimeKbdTrack"))
        p.setUnsigned(b + V.vdfEGTimeVelSens, try range(d.egTimeVelocitySens, 0, 99, f + ".vdf.egTimeVelocitySens"))
        p.setSigned(b + V.vdfEGIntVelSens, try range(d.egIntensityVelocitySens, -99, 99, f + ".vdf.egIntensityVelocitySens"))
        let fe = d.eg
        p.setUnsigned(b + V.vdfEGAttackTime, try range(fe.attackTime, 0, 99, f + ".vdf.eg.attackTime"))
        p.setSigned(b + V.vdfEGAttackLevel, try range(fe.attackLevel, -99, 99, f + ".vdf.eg.attackLevel"))
        p.setUnsigned(b + V.vdfEGDecayTime, try range(fe.decayTime, 0, 99, f + ".vdf.eg.decayTime"))
        p.setSigned(b + V.vdfEGBreakPoint, try range(fe.breakPoint, -99, 99, f + ".vdf.eg.breakPoint"))
        p.setUnsigned(b + V.vdfEGSlopeTime, try range(fe.slopeTime, 0, 99, f + ".vdf.eg.slopeTime"))
        p.setSigned(b + V.vdfEGSustainLevel, try range(fe.sustainLevel, -99, 99, f + ".vdf.eg.sustainLevel"))
        p.setUnsigned(b + V.vdfEGReleaseTime, try range(fe.releaseTime, 0, 99, f + ".vdf.eg.releaseTime"))
        p.setSigned(b + V.vdfEGReleaseLevel, try range(fe.releaseLevel, -99, 99, f + ".vdf.eg.releaseLevel"))
        apply(switches: d.egTimeKbdTrackSwitches, to: &p, at: b + V.vdfEGTimeKbdTrackSwitches)
        apply(switches: d.egTimeVelocitySwitches, to: &p, at: b + V.vdfEGTimeVelSwitches)

        let a = v.vda
        p.setUnsigned(b + V.vdaLevel, try range(a.level, 0, 99, f + ".vda.level"))
        p.setUnsigned(b + V.vdaKbdTrackCenter, try note(a.kbdTrackCenter, field: f + ".vda.kbdTrackCenter"))
        p.setSigned(b + V.vdaKbdTrackIntensity, try range(a.kbdTrackIntensity, -99, 99, f + ".vda.kbdTrackIntensity"))
        p.setSigned(b + V.vdaVelocitySens, try range(a.velocitySens, -99, 99, f + ".vda.velocitySens"))
        p.setUnsigned(b + V.vdaEGTimeKbdTrack, try range(a.egTimeKbdTrack, 0, 99, f + ".vda.egTimeKbdTrack"))
        p.setUnsigned(b + V.vdaEGTimeVelSens, try range(a.egTimeVelocitySens, 0, 99, f + ".vda.egTimeVelocitySens"))
        let ae = a.eg
        p.setUnsigned(b + V.vdaEGAttackTime, try range(ae.attackTime, 0, 99, f + ".vda.eg.attackTime"))
        p.setUnsigned(b + V.vdaEGAttackLevel, try range(ae.attackLevel, 0, 99, f + ".vda.eg.attackLevel"))
        p.setUnsigned(b + V.vdaEGDecayTime, try range(ae.decayTime, 0, 99, f + ".vda.eg.decayTime"))
        p.setUnsigned(b + V.vdaEGBreakPoint, try range(ae.breakPoint, 0, 99, f + ".vda.eg.breakPoint"))
        p.setUnsigned(b + V.vdaEGSlopeTime, try range(ae.slopeTime, 0, 99, f + ".vda.eg.slopeTime"))
        p.setUnsigned(b + V.vdaEGSustainLevel, try range(ae.sustainLevel, 0, 99, f + ".vda.eg.sustainLevel"))
        p.setUnsigned(b + V.vdaEGReleaseTime, try range(ae.releaseTime, 0, 99, f + ".vda.eg.releaseTime"))
        apply(switches: a.egTimeKbdTrackSwitches, to: &p, at: b + V.vdaEGTimeKbdTrackSwitches)
        apply(switches: a.egTimeVelocitySwitches, to: &p, at: b + V.vdaEGTimeVelSwitches)
    }

    // MARK: - JSON helpers

    public static func decode(json data: Data) throws -> M1Patch {
        let decoder = JSONDecoder()
        let patch = try decoder.decode(M1Patch.self, from: data)
        guard let f = patch.format, f == formatID else {
            throw M1Error.invalidValue(field: "format", reason: "must be \"\(formatID)\"")
        }
        return patch
    }

    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}
