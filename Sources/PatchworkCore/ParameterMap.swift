import Foundation

// Byte indices into the 143-byte Program Parameter Dump, from the M1 owner's manual
// MIDI data format "Program Parameter" table (param00–param142).

/// Global (non-voice) parameter indices.
public enum P {
    public static let nameStart = 0            // 0–9 ASCII
    public static let oscMode = 10             // 0 single, 1 double, 2 drums
    public static let assignHold = 11          // bit0 assign (0 poly / 1 mono), bit1 hold
    public static let osc1Multisound = 12      // 0–99 internal, 100+ card
    public static let osc1Octave = 13          // FF 16', 00 8', 01 4'
    public static let osc2Multisound = 14
    public static let osc2Octave = 15
    public static let osc2Interval = 16        // -12…+12
    public static let osc2Detune = 17          // -50…+50
    public static let osc2DelayStart = 18      // 0–99
    public static let pitchMGFlags = 19        // bits0-3 waveform, bit5 OSC1, bit6 OSC2, bit7 key sync
    public static let pitchMGFreq = 20
    public static let pitchMGDelay = 21
    public static let pitchMGIntensity = 22
    public static let vdfMGFlags = 23
    public static let vdfMGFreq = 24
    public static let vdfMGDelay = 25
    public static let vdfMGIntensity = 26
    public static let atPitch = 27             // -12…+12
    public static let atPitchMG = 28           // 0–99
    public static let atVDFCutoff = 29         // -99…+99
    public static let atVDFMG = 30             // 0–99
    public static let atVDAAmplitude = 31      // -99…+99
    public static let jsPitchBend = 32         // -12…+12
    public static let jsVDFSweep = 33          // -99…+99
    public static let jsPitchMGIntensity = 34  // 0–99
    public static let jsPitchMGFreq = 35       // 0–3
    public static let jsVDFMGIntensity = 36    // 0–99
    public static let jsVDFMGFreq = 37         // 0–3
    public static let effect1Type = 38         // 0x00–0x20 = effects 1–33, 0x21 = Thru
    public static let effect2Type = 39
    public static let effect1BalL = 40         // 0–100
    public static let effect1BalR = 41
    public static let effect2BalL = 42
    public static let effect2BalR = 43
    public static let output3Pan = 44          // 0 off, 1 = R … 101 = L
    public static let output4Pan = 45
    public static let effectIO = 46            // bits0-3 fx1L fx1R fx2L fx2R on/off, bit4 serial
    public static let effect1Params = 47       // 47–54
    public static let effect2Params = 55       // 55–62
    public static let voice1Base = 63          // 63–102
    public static let voice2Base = 103         // 103–142
    public static let voiceLength = 40
}

/// Per-voice parameter offsets (add `P.voice1Base` or `P.voice2Base`).
public enum V {
    // Pitch EG
    public static let pegStartLevel = 0        // s
    public static let pegAttackTime = 1
    public static let pegAttackLevel = 2       // s
    public static let pegDecayTime = 3
    public static let pegReleaseTime = 4
    public static let pegReleaseLevel = 5      // s
    public static let pegTimeVelSens = 6       // s
    public static let pegLevelVelSens = 7      // s
    // VDF
    public static let vdfCutoff = 8
    public static let vdfKbdTrackCenter = 9    // note 0–127
    public static let vdfCutoffKbdTrack = 10   // s
    public static let vdfEGIntensity = 11
    public static let vdfEGTimeKbdTrack = 12
    public static let vdfEGTimeVelSens = 13
    public static let vdfEGIntVelSens = 14     // s
    // VDF EG
    public static let vdfEGAttackTime = 15
    public static let vdfEGAttackLevel = 16    // s
    public static let vdfEGDecayTime = 17
    public static let vdfEGBreakPoint = 18     // s
    public static let vdfEGSlopeTime = 19
    public static let vdfEGSustainLevel = 20   // s
    public static let vdfEGReleaseTime = 21
    public static let vdfEGReleaseLevel = 22   // s
    // VDA
    public static let vdaLevel = 23
    public static let vdaKbdTrackCenter = 24   // note
    public static let vdaKbdTrackIntensity = 25 // s
    public static let vdaVelocitySens = 26     // s
    public static let vdaEGTimeKbdTrack = 27
    public static let vdaEGTimeVelSens = 28
    // VDA EG
    public static let vdaEGAttackTime = 29
    public static let vdaEGAttackLevel = 30
    public static let vdaEGDecayTime = 31
    public static let vdaEGBreakPoint = 32
    public static let vdaEGSlopeTime = 33
    public static let vdaEGSustainLevel = 34
    public static let vdaEGReleaseTime = 35
    // EG time modulation switches: bits0-3 attack/decay/slope/release on, bit4 polarity (1 = -)
    public static let vdfEGTimeKbdTrackSwitches = 36
    public static let vdfEGTimeVelSwitches = 37
    public static let vdaEGTimeKbdTrackSwitches = 38
    public static let vdaEGTimeVelSwitches = 39
}

// MARK: - Parameter definitions (drive the generic UI, randomiser and validation)

/// A group of parameters as the editor shows them. Synth definitions declare their own sections;
/// `rawValue` is the display title (kept for source compatibility with the enum this used to be).
public struct ParamSection: Hashable, Equatable {
    public let id: String
    public let rawValue: String
    public init(id: String, title: String) { self.id = id; self.rawValue = title }
    public var title: String { rawValue }

    // Korg M1 sections
    public static let general = ParamSection(id: "general", title: "General")
    public static let oscillators = ParamSection(id: "oscillators", title: "Oscillators")
    public static let pitchMG = ParamSection(id: "pitch-mg", title: "Pitch MG")
    public static let vdfMG = ParamSection(id: "vdf-mg", title: "VDF MG")
    public static let aftertouch = ParamSection(id: "aftertouch", title: "Aftertouch")
    public static let joystick = ParamSection(id: "joystick", title: "Joystick")
    public static let effects = ParamSection(id: "effects", title: "Effects")
    public static let v1PitchEG = ParamSection(id: "osc1-pitch-eg", title: "OSC1 · Pitch EG")
    public static let v1VDF = ParamSection(id: "osc1-vdf", title: "OSC1 · VDF")
    public static let v1VDFEG = ParamSection(id: "osc1-vdf-eg", title: "OSC1 · VDF EG")
    public static let v1VDA = ParamSection(id: "osc1-vda", title: "OSC1 · VDA")
    public static let v1VDAEG = ParamSection(id: "osc1-vda-eg", title: "OSC1 · VDA EG")
    public static let v1Switches = ParamSection(id: "osc1-switches", title: "OSC1 · EG time switches")
    public static let v2PitchEG = ParamSection(id: "osc2-pitch-eg", title: "OSC2 · Pitch EG")
    public static let v2VDF = ParamSection(id: "osc2-vdf", title: "OSC2 · VDF")
    public static let v2VDFEG = ParamSection(id: "osc2-vdf-eg", title: "OSC2 · VDF EG")
    public static let v2VDA = ParamSection(id: "osc2-vda", title: "OSC2 · VDA")
    public static let v2VDAEG = ParamSection(id: "osc2-vda-eg", title: "OSC2 · VDA EG")
    public static let v2Switches = ParamSection(id: "osc2-switches", title: "OSC2 · EG time switches")

    /// The M1's sections in editor order.
    public static let allCases: [ParamSection] = [
        .general, .oscillators, .pitchMG, .vdfMG, .aftertouch, .joystick, .effects,
        .v1PitchEG, .v1VDF, .v1VDFEG, .v1VDA, .v1VDAEG, .v1Switches,
        .v2PitchEG, .v2VDF, .v2VDFEG, .v2VDA, .v2VDAEG, .v2Switches,
    ]
}

public struct BitFieldDef: Equatable {
    public let name: String
    public let shift: Int
    public let width: Int
    /// Labels for each value when width > 1 (or ["Off","On"] style for width 1).
    public let labels: [String]
    public init(_ name: String, shift: Int, width: Int = 1, labels: [String] = ["Off", "On"]) {
        self.name = name; self.shift = shift; self.width = width; self.labels = labels
    }
}

public enum ParamKind: Equatable {
    case ascii
    case unsigned(max: Int)
    case signed(min: Int, max: Int)
    case choice([String])
    case bits([BitFieldDef])
    case note
    case multisound
    case octave
    case pan
    case effectType
    case effectParam(effect: Int, slot: Int)
}

public struct ParamDef: Identifiable, Equatable {
    public let index: Int
    public let name: String
    public let section: ParamSection
    public let kind: ParamKind
    public var id: Int { index }

    /// Does this parameter hold a "musical" value the randomiser may vary freely?
    public var randomisable: Bool {
        switch kind {
        case .ascii, .effectParam: return false
        default: return true
        }
    }
}

public enum ParameterMap {

    public static let mgWaveforms = ["Triangle", "Saw up", "Saw down", "Square"]

    public static let all: [ParamDef] = {
        var d: [ParamDef] = []
        func add(_ i: Int, _ n: String, _ s: ParamSection, _ k: ParamKind) { d.append(ParamDef(index: i, name: n, section: s, kind: k)) }

        add(P.nameStart, "Name", .general, .ascii)
        add(P.oscMode, "Oscillator mode", .general, .choice(["Single", "Double", "Drums"]))
        add(P.assignHold, "Assign / Hold", .general, .bits([
            BitFieldDef("Assign", shift: 0, labels: ["Poly", "Mono"]),
            BitFieldDef("Hold", shift: 1),
        ]))
        add(P.osc1Multisound, "OSC1 multisound", .oscillators, .multisound)
        add(P.osc1Octave, "OSC1 octave", .oscillators, .octave)
        add(P.osc2Multisound, "OSC2 multisound", .oscillators, .multisound)
        add(P.osc2Octave, "OSC2 octave", .oscillators, .octave)
        add(P.osc2Interval, "OSC2 interval (semitones)", .oscillators, .signed(min: -12, max: 12))
        add(P.osc2Detune, "OSC2 detune (cents)", .oscillators, .signed(min: -50, max: 50))
        add(P.osc2DelayStart, "OSC2 delay start", .oscillators, .unsigned(max: 99))

        let mgBits = [
            BitFieldDef("Waveform", shift: 0, width: 2, labels: mgWaveforms),
            BitFieldDef("OSC1", shift: 5),
            BitFieldDef("OSC2", shift: 6),
            BitFieldDef("Key sync", shift: 7),
        ]
        add(P.pitchMGFlags, "Pitch MG", .pitchMG, .bits(mgBits))
        add(P.pitchMGFreq, "Frequency", .pitchMG, .unsigned(max: 99))
        add(P.pitchMGDelay, "Delay", .pitchMG, .unsigned(max: 99))
        add(P.pitchMGIntensity, "Intensity", .pitchMG, .unsigned(max: 99))
        add(P.vdfMGFlags, "VDF MG", .vdfMG, .bits(mgBits))
        add(P.vdfMGFreq, "Frequency", .vdfMG, .unsigned(max: 99))
        add(P.vdfMGDelay, "Delay", .vdfMG, .unsigned(max: 99))
        add(P.vdfMGIntensity, "Intensity", .vdfMG, .unsigned(max: 99))

        add(P.atPitch, "Pitch (semitones)", .aftertouch, .signed(min: -12, max: 12))
        add(P.atPitchMG, "Pitch MG", .aftertouch, .unsigned(max: 99))
        add(P.atVDFCutoff, "VDF cutoff", .aftertouch, .signed(min: -99, max: 99))
        add(P.atVDFMG, "VDF MG", .aftertouch, .unsigned(max: 99))
        add(P.atVDAAmplitude, "VDA amplitude", .aftertouch, .signed(min: -99, max: 99))

        add(P.jsPitchBend, "Pitch bend (semitones)", .joystick, .signed(min: -12, max: 12))
        add(P.jsVDFSweep, "VDF sweep", .joystick, .signed(min: -99, max: 99))
        add(P.jsPitchMGIntensity, "Pitch MG intensity (+Y)", .joystick, .unsigned(max: 99))
        add(P.jsPitchMGFreq, "Pitch MG frequency (+Y)", .joystick, .unsigned(max: 3))
        add(P.jsVDFMGIntensity, "VDF MG intensity (-Y)", .joystick, .unsigned(max: 99))
        add(P.jsVDFMGFreq, "VDF MG frequency (-Y)", .joystick, .unsigned(max: 3))

        add(P.effect1Type, "Effect 1", .effects, .effectType)
        add(P.effect2Type, "Effect 2", .effects, .effectType)
        add(P.effect1BalL, "Effect 1 L balance", .effects, .unsigned(max: 100))
        add(P.effect1BalR, "Effect 1 R balance", .effects, .unsigned(max: 100))
        add(P.effect2BalL, "Effect 2 L balance", .effects, .unsigned(max: 100))
        add(P.effect2BalR, "Effect 2 R balance", .effects, .unsigned(max: 100))
        add(P.output3Pan, "Output 3 pan", .effects, .pan)
        add(P.output4Pan, "Output 4 pan", .effects, .pan)
        add(P.effectIO, "Effect routing", .effects, .bits([
            BitFieldDef("FX1 L", shift: 0), BitFieldDef("FX1 R", shift: 1),
            BitFieldDef("FX2 L", shift: 2), BitFieldDef("FX2 R", shift: 3),
            BitFieldDef("Placement", shift: 4, labels: ["Parallel", "Serial"]),
        ]))
        for s in 0..<8 { add(P.effect1Params + s, "Effect 1 param \(s + 1)", .effects, .effectParam(effect: 1, slot: s)) }
        for s in 0..<8 { add(P.effect2Params + s, "Effect 2 param \(s + 1)", .effects, .effectParam(effect: 2, slot: s)) }

        let voices: [(Int, ParamSection, ParamSection, ParamSection, ParamSection, ParamSection, ParamSection)] = [
            (P.voice1Base, .v1PitchEG, .v1VDF, .v1VDFEG, .v1VDA, .v1VDAEG, .v1Switches),
            (P.voice2Base, .v2PitchEG, .v2VDF, .v2VDFEG, .v2VDA, .v2VDAEG, .v2Switches),
        ]
        let s99 = ParamKind.signed(min: -99, max: 99)
        let u99 = ParamKind.unsigned(max: 99)
        let swBits = [
            BitFieldDef("Attack", shift: 0), BitFieldDef("Decay", shift: 1),
            BitFieldDef("Slope", shift: 2), BitFieldDef("Release", shift: 3),
            BitFieldDef("Polarity", shift: 4, labels: ["+", "−"]),
        ]
        for (b, peg, vdf, vdfeg, vda, vdaeg, sw) in voices {
            add(b + V.pegStartLevel, "Start level", peg, s99)
            add(b + V.pegAttackTime, "Attack time", peg, u99)
            add(b + V.pegAttackLevel, "Attack level", peg, s99)
            add(b + V.pegDecayTime, "Decay time", peg, u99)
            add(b + V.pegReleaseTime, "Release time", peg, u99)
            add(b + V.pegReleaseLevel, "Release level", peg, s99)
            add(b + V.pegTimeVelSens, "Time velocity sens", peg, s99)
            add(b + V.pegLevelVelSens, "Level velocity sens", peg, s99)

            add(b + V.vdfCutoff, "Cutoff", vdf, u99)
            add(b + V.vdfKbdTrackCenter, "Kbd track center", vdf, .note)
            add(b + V.vdfCutoffKbdTrack, "Cutoff kbd track", vdf, s99)
            add(b + V.vdfEGIntensity, "EG intensity", vdf, u99)
            add(b + V.vdfEGTimeKbdTrack, "EG time kbd track", vdf, u99)
            add(b + V.vdfEGTimeVelSens, "EG time velocity sens", vdf, u99)
            add(b + V.vdfEGIntVelSens, "EG intensity velocity sens", vdf, s99)

            add(b + V.vdfEGAttackTime, "Attack time", vdfeg, u99)
            add(b + V.vdfEGAttackLevel, "Attack level", vdfeg, s99)
            add(b + V.vdfEGDecayTime, "Decay time", vdfeg, u99)
            add(b + V.vdfEGBreakPoint, "Break point", vdfeg, s99)
            add(b + V.vdfEGSlopeTime, "Slope time", vdfeg, u99)
            add(b + V.vdfEGSustainLevel, "Sustain level", vdfeg, s99)
            add(b + V.vdfEGReleaseTime, "Release time", vdfeg, u99)
            add(b + V.vdfEGReleaseLevel, "Release level", vdfeg, s99)

            add(b + V.vdaLevel, "Oscillator level", vda, u99)
            add(b + V.vdaKbdTrackCenter, "Kbd track center", vda, .note)
            add(b + V.vdaKbdTrackIntensity, "Kbd track intensity", vda, s99)
            add(b + V.vdaVelocitySens, "Velocity sens", vda, s99)
            add(b + V.vdaEGTimeKbdTrack, "EG time kbd track", vda, u99)
            add(b + V.vdaEGTimeVelSens, "EG time velocity sens", vda, u99)

            add(b + V.vdaEGAttackTime, "Attack time", vdaeg, u99)
            add(b + V.vdaEGAttackLevel, "Attack level", vdaeg, u99)
            add(b + V.vdaEGDecayTime, "Decay time", vdaeg, u99)
            add(b + V.vdaEGBreakPoint, "Break point", vdaeg, u99)
            add(b + V.vdaEGSlopeTime, "Slope time", vdaeg, u99)
            add(b + V.vdaEGSustainLevel, "Sustain level", vdaeg, u99)
            add(b + V.vdaEGReleaseTime, "Release time", vdaeg, u99)

            add(b + V.vdfEGTimeKbdTrackSwitches, "VDF EG time · kbd track", sw, .bits(swBits))
            add(b + V.vdfEGTimeVelSwitches, "VDF EG time · velocity", sw, .bits(swBits))
            add(b + V.vdaEGTimeKbdTrackSwitches, "VDA EG time · kbd track", sw, .bits(swBits))
            add(b + V.vdaEGTimeVelSwitches, "VDA EG time · velocity", sw, .bits(swBits))
        }
        return d
    }()

    public static let byIndex: [Int: ParamDef] = Dictionary(uniqueKeysWithValues: all.map { ($0.index, $0) })

    public static func definitions(in section: ParamSection) -> [ParamDef] {
        all.filter { $0.section == section }
    }

    /// Clamp a program's bytes into the documented ranges (leaves unknown/raw bytes alone).
    public static func sanitise(_ program: inout M1Program) {
        for def in all {
            switch def.kind {
            case .unsigned(let mx):
                program.setUnsigned(def.index, min(program.unsigned(def.index), mx))
            case .signed(let mn, let mx):
                program.setSigned(def.index, max(mn, min(mx, program.signed(def.index))))
            case .choice(let labels):
                program.setUnsigned(def.index, min(program.unsigned(def.index), labels.count - 1))
            case .note:
                program.setUnsigned(def.index, min(program.unsigned(def.index), 127))
            case .octave:
                program.setSigned(def.index, max(-1, min(1, program.signed(def.index))))
            case .pan:
                program.setUnsigned(def.index, min(program.unsigned(def.index), 101))
            case .effectType:
                program.setUnsigned(def.index, min(program.unsigned(def.index), EffectTypes.thruValue))
            case .multisound, .ascii, .bits, .effectParam:
                break
            }
        }
    }
}

// MARK: - Name tables

public enum Multisounds {
    /// Internal multisounds 0–99 (M1 owner's manual). Values ≥ 100 address a PCM card.
    public static let names: [String] = [
        "A.Piano", "E.Piano1", "E.Piano2", "Clav", "Harpsichord", "Organ1", "Organ2", "MagicOrgan", "Guitar1", "Guitar2",
        "E.Guitar", "Sitar1", "Sitar2", "A.Bass", "PickBass", "E.Bass", "Fretless", "SynthBass1", "SynthBass2", "Vibes",
        "Bell", "Tubular", "BellRing", "Karimba", "KarimbaNT", "SynMallet", "Flute", "PanFlute", "Bottles", "Voices",
        "Choir", "Strings", "Brass1", "Brass2", "TenorSax", "MuteTP", "Trumpet", "TubaFlugel", "DoubleReed", "KotoTrem",
        "BambooTrem", "Rhythm", "Lore", "LoreNT", "Flexatone", "WindBells", "Pole", "PoleNT", "Block", "BlockNT",
        "FingerSnap", "Pop", "Drop", "DropNT", "Breath", "BreathNT", "Pluck", "PluckNT", "VibeHit", "VibeHitNT",
        "Hammer", "MetalHit", "MetalHitNT", "Pick", "Distortion", "DistNT", "BassThumb", "BasThumNT1", "BasThumNT2", "Wire",
        "PanWave", "PingWave", "FvWave", "MvWave", "VoiceWave", "VoiceWvNT1", "VoiceWvNT2", "DWGS EP1", "DWGS EP2", "DWGS EP3",
        "DWGS Piano", "DWGS Clav", "DWGS Vibe1", "DWGS Bass1", "DWGS Bass2", "DWGS Bell1", "DWGS Orgn1", "DWGS Orgn2", "DWGS Voice", "SquareWave",
        "Digital1", "SawWave", "Digital2", "25% Pulse", "10% Pulse", "Digital3", "Digital4", "Digital5", "DWGS Tri", "DWGS Sine",
    ]

    public static func name(for value: Int) -> String {
        if value >= 0 && value < names.count { return names[value] }
        return "card:\(value - names.count)"
    }

    /// Accepts a name (case-insensitive), "card:N", or a decimal number.
    public static func value(for string: String) -> Int? {
        let s = string.trimmingCharacters(in: .whitespaces)
        if let n = Int(s), n >= 0, n <= 255 { return n }
        if s.lowercased().hasPrefix("card:"), let n = Int(s.dropFirst(5)), n >= 0 { return names.count + n }
        let key = s.lowercased().replacingOccurrences(of: " ", with: "")
        return names.firstIndex { $0.lowercased().replacingOccurrences(of: " ", with: "") == key }
    }
}

public enum DrumSounds {
    /// Drum instruments 1–44 (index 0 is unused/off).
    public static let names: [String] = [
        "—", "Kick1", "Kick2", "Kick3", "Snare1", "Snare2", "Snare3", "Snare4", "SideStick", "Tom1", "Tom2",
        "ClosedHH1", "OpenHH1", "ClosedHH2", "OpenHH2", "Crash", "Conga1", "Conga2", "Timbales1", "Timbales2", "Cowbell",
        "Claps", "Tambourine", "E.Tom", "Ride", "Rap", "Whip", "Shaker", "Pole", "Block", "FingerSnap",
        "Drop", "VibeHit", "Hammer", "MetalHit", "Pluck", "FlexaTone", "Wind Bell", "Tubular1", "Tubular2", "Tubular3",
        "Tubular4", "BellRing", "Metronome1", "Metronome2",
    ]
}

public enum EffectTypes {
    /// Byte value for "Thru" (no effect). Values 0…32 are effects 1…33.
    public static let thruValue = 0x21

    /// Effects 1–33. Entries 26–33 are the dual "Delay/…" effects; their order follows the
    /// manual's listing but was not printed with explicit numbers, so verify against the panel.
    public static let names: [String] = [
        "Hall", "Ensemble Hall", "Concert Hall", "Room", "Large Room", "Live Stage",
        "Early Reflection I", "Early Reflection II", "Early Reflection III",
        "Stereo Delay", "Cross Delay", "Stereo Chorus I", "Stereo Chorus II",
        "Stereo Flanger", "Cross Flanger", "Phaser I", "Phaser II",
        "Stereo Tremolo I", "Stereo Tremolo II", "Equalizer", "Overdrive", "Distortion", "Exciter",
        "Symphonic Ensemble", "Rotary Speaker",
        "Delay/Hall", "Delay/Room", "Delay/Early Reflection", "Delay/Delay",
        "Delay/Chorus", "Delay/Flanger", "Delay/Phaser", "Delay/Tremolo",
    ]

    public static func name(for value: Int) -> String {
        if value == thruValue { return "Thru" }
        if value >= 0 && value < names.count { return names[value] }
        return "Unknown(\(value))"
    }

    public static func value(for string: String) -> Int? {
        let s = string.trimmingCharacters(in: .whitespaces).lowercased()
        if s == "thru" || s == "through" || s == "off" || s == "none" { return thruValue }
        if let n = Int(s) { return (n >= 1 && n <= names.count) ? n - 1 : nil }  // 1-based as on the panel
        return names.firstIndex { $0.lowercased() == s }
    }

    /// Best-effort labels for the 8 effect parameter bytes, in the order the manual lists each
    /// effect's parameters. The exact byte encoding of each (e.g. reverb time 0.2–9.9 s) is not
    /// documented in the data-format table, so the editor exposes them as raw bytes with these labels.
    public static func parameterLabels(for value: Int) -> [String] {
        let hall = ["Reverb time", "Pre delay", "E/R level", "High damp", "EQ low", "EQ high", "Dry:Eff", "—"]
        let er = ["E/R time", "Pre delay", "EQ low", "EQ high", "Dry:Eff", "—", "—", "—"]
        let delay = ["Delay L", "Delay R", "Feedback", "High damp", "EQ low", "EQ high", "Dry:Eff", "—"]
        let chorus = ["Mod depth", "Mod speed", "Delay time", "Mod waveform", "EQ low", "EQ high", "Dry:Eff", "—"]
        let flanger = ["Mod depth", "Mod speed", "Delay time", "Feedback", "Mod waveform", "EQ low", "EQ high", "Dry:Eff"]
        let phaser = ["Manual", "Mod speed", "Mod depth", "Feedback", "Mod waveform", "Dry:Eff", "—", "—"]
        let tremolo = ["Mod depth", "Mod speed", "Mod waveform", "Shape", "EQ low", "EQ high", "Dry:Eff", "—"]
        let eq = ["Low gain", "Low cutoff", "—", "High gain", "High cutoff", "Dry:Eff", "—", "—"]
        let drive = ["Drive", "Level", "EQ low", "EQ high", "Dry:Eff", "—", "—", "—"]
        let exciter = ["Blend", "Emphatic point", "EQ low", "EQ high", "Dry:Eff", "—", "—", "—"]
        let symphonic = ["Mod depth", "EQ low", "EQ high", "Dry:Eff", "—", "—", "—", "—"]
        let rotary = ["Mod depth", "Speed ratio", "Dry:Eff", "—", "—", "—", "—", "—"]
        let dualDelay = ["Delay time", "Feedback", "High damp", "Dry:Eff"]
        switch value {
        case 0...5: return hall
        case 6...8: return er
        case 9, 10: return delay
        case 11, 12: return chorus
        case 13, 14: return flanger
        case 15, 16: return phaser
        case 17, 18: return tremolo
        case 19: return eq
        case 20, 21: return drive
        case 22: return exciter
        case 23: return symphonic
        case 24: return rotary
        case 25, 26: return dualDelay + ["Reverb time", "Pre delay", "High damp", "Dry:Eff"]
        case 27: return dualDelay + ["E/R time", "Pre delay", "Dry:Eff", "—"]
        case 28: return dualDelay + ["Delay time", "Feedback", "High damp", "Dry:Eff"]
        case 29: return dualDelay + ["Mod depth", "Mod speed", "Mod waveform", "Dry:Eff"]
        case 30...32: return dualDelay + ["Mod depth", "Mod speed", "Feedback", "Dry:Eff"]
        default: return (1...8).map { "Param \($0)" }
        }
    }
}

// MARK: - Note names

public enum NoteName {
    static let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    /// Korg convention: middle C (MIDI 60) is "C4", so 0 = "C-1" and 127 = "G9".
    public static func string(for midiNote: Int) -> String {
        let n = max(0, min(127, midiNote))
        return "\(names[n % 12])\(n / 12 - 1)"
    }

    public static func value(for string: String) -> Int? {
        let s = string.trimmingCharacters(in: .whitespaces).uppercased()
        if let n = Int(s), n >= 0, n <= 127 { return n }
        guard let first = s.first, let base = names.firstIndex(of: String(first)) else { return nil }
        var rest = s.dropFirst()
        var semis = base
        if rest.hasPrefix("#") { semis += 1; rest = rest.dropFirst() }
        else if rest.hasPrefix("B") && rest.count > 1 { semis -= 1; rest = rest.dropFirst() }  // "Db4"
        guard let octave = Int(rest) else { return nil }
        let v = (octave + 1) * 12 + semis
        return (v >= 0 && v <= 127) ? v : nil
    }
}
