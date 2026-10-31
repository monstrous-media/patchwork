import Foundation

/// One explanation per parameter: the M1's meaning, the general synthesis idea, and the musical effect.
/// Used for tooltips in the editor, the generated "Parameter reference" in the guide, and `patchwork params`.
public enum ParameterHelp {

    public static func text(for def: ParamDef) -> String {
        let n = def.name
        switch def.section {
        case .general:
            switch n {
            case "Name": return "Up to 10 printable ASCII characters, as shown on the M1's display."
            case "Oscillator mode": return "Single = one oscillator (OSC1), 16-note polyphony. Double = OSC1 and OSC2 layered, 8 notes. Drums = OSC1 plays a drum kit (per-key sounds defined in Global mode)."
            case "Assign / Hold": return "Poly plays chords; Mono is one note at a time (last-note priority, good for bass and leads). Hold keeps notes sounding after key-up — for drums and one-shot effects."
            default: break
            }
        case .oscillators:
            if n.hasSuffix("multisound") { return "The sampled waveform this oscillator plays — the M1's raw material. In Drums mode OSC1 selects Drum Kit 1–4 instead. Names ending NT are the attack transient only (no loop), useful layered under a sustained sound." }
            if n.hasSuffix("octave") { return "Transposes the oscillator by an octave: 16' = down, 8' = as sampled, 4' = up." }
            switch n {
            case "OSC2 interval (semitones)": return "Tunes OSC2 relative to OSC1 in semitones: 7 = a fifth, 12 = an octave, 0 = unison."
            case "OSC2 detune (cents)": return "Fine-tunes OSC2 in cents. A few cents (±4…8) against OSC1 gives chorus-like width; 0 = exact unison."
            case "OSC2 delay start": return "Delays OSC2's note-on so the second layer blooms after the first (0 = together)."
            default: break
            }
        case .pitchMG, .vdfMG:
            let what = def.section == .pitchMG ? "vibrato (pitch)" : "filter-cutoff wobble (wah / sweep)"
            switch n {
            case "Pitch MG", "VDF MG": return "The modulation generator (LFO) for \(what): waveform, which oscillators it affects, and key sync (restart the LFO on each key press)."
            case "Frequency": return "LFO speed. Around 35–45 is a natural vibrato rate; 99 is very fast."
            case "Delay": return "Fade-in time before the LFO takes effect after a key press — delayed vibrato."
            case "Intensity": return "LFO depth. 0 = off. For \(what), 3–8 is subtle."
            default: break
            }
        case .aftertouch:
            switch n {
            case "Pitch (semitones)": return "Pressing harder after the key is down bends pitch by up to this many semitones."
            case "Pitch MG": return "Aftertouch adds vibrato depth."
            case "VDF cutoff": return "Aftertouch opens (+) or closes (−) the filter — expressive brightness."
            case "VDF MG": return "Aftertouch adds filter-LFO depth."
            case "VDA amplitude": return "Aftertouch raises (+) or lowers (−) the level — swells."
            default: break
            }
        case .joystick:
            switch n {
            case "Pitch bend (semitones)": return "Joystick left/right bend range in semitones. 2 is the conventional default."
            case "VDF sweep": return "Joystick left/right also sweeps the filter cutoff by this much."
            case "Pitch MG intensity (+Y)": return "Pushing the joystick forward (+Y) adds this much vibrato depth."
            case "Pitch MG frequency (+Y)": return "LFO speed used for +Y vibrato (0–3)."
            case "VDF MG intensity (-Y)": return "Pulling the joystick back (−Y) adds this much filter-LFO depth."
            case "VDF MG frequency (-Y)": return "LFO speed used for −Y filter modulation (0–3)."
            default: break
            }
        case .effects:
            switch def.kind {
            case .effectType: return "Effect type for this slot. Reverbs (Hall, Room…), delays, modulation (chorus, flanger, phaser, tremolo, symphonic), EQ, overdrive/distortion, exciter, rotary speaker, and dual Delay/… effects. Thru = bypass."
            case .effectParam: return "One of the eight raw parameter bytes for this effect; its meaning depends on the effect type (shown in the label). Exact encodings are undocumented — values from a real program are safe, invented ones may be odd."
            case .pan: return "Pan of the signal sent to this individual output jack (3 or 4): off, or right…left. Only matters if you use outputs 3/4."
            default: break
            }
            switch n {
            case "Effect routing": return "Which channels (L/R) of each effect are active, and whether Effect 1 feeds Effect 2 in series (serial) or both sit side by side (parallel)."
            default:
                if n.contains("balance") { return "Dry/wet balance for this channel: 0 = dry, 100 = effect only. Reverb 30–50, chorus 40–50, overdrive 15–30 are typical." }
            }
        case .v1PitchEG, .v2PitchEG:
            switch n {
            case "Start level": return "Pitch offset at note-on (−99…+99): negative starts flat and rises to pitch — a brass-like scoop."
            case "Attack time": return "Time to move from the start level to the attack level."
            case "Attack level": return "Pitch offset reached after the attack; 0 = in tune."
            case "Decay time": return "Time to return from the attack level to normal pitch."
            case "Release time": return "Time after key-up to reach the release level."
            case "Release level": return "Pitch offset after key-up: a downward droop or upward tail."
            case "Time velocity sens": return "Velocity shortens (+) or lengthens (−) the pitch-envelope times."
            case "Level velocity sens": return "Velocity increases (+) or decreases (−) the pitch-envelope depth."
            default: break
            }
        case .v1VDF, .v2VDF:
            switch n {
            case "Cutoff": return "Low-pass filter cutoff: 99 = fully open (the raw sample), 30–55 = warm, below 25 = dark. The main tone control."
            case "Kbd track center": return "The key where keyboard tracking has no effect; tracking applies above and below it."
            case "Cutoff kbd track": return "How cutoff follows the keyboard: positive = higher notes brighter (keeps high notes from dulling), negative = the reverse."
            case "EG intensity": return "How far the filter envelope (below) moves the cutoff. 0 = static filter; 60–80 gives a strong pluck or sweep."
            case "EG time kbd track": return "Amount by which keyboard position shortens/lengthens the filter envelope's segments (which ones: the EG time switches)."
            case "EG time velocity sens": return "Amount by which velocity shortens/lengthens the filter envelope's segments."
            case "EG intensity velocity sens": return "Velocity scales the envelope's effect on cutoff: positive = harder playing opens the filter more — classic velocity brightness."
            default: break
            }
        case .v1VDFEG, .v2VDFEG:
            switch n {
            case "Attack time": return "Time to reach the attack level after note-on. 0 = instant."
            case "Attack level": return "Filter-envelope level at the end of the attack (−99…+99: positive opens above the cutoff, negative closes)."
            case "Decay time": return "Time from the attack level to the break point."
            case "Break point": return "Intermediate level between decay and slope — the M1's extra envelope stage, for two-stage decays."
            case "Slope time": return "Time from the break point to the sustain level."
            case "Sustain level": return "Level held while the key is down (bipolar for the filter)."
            case "Release time": return "Time after key-up to reach the release level."
            case "Release level": return "Where the filter envelope ends after key-up."
            default: break
            }
        case .v1VDA, .v2VDA:
            switch n {
            case "Oscillator level": return "Volume of this oscillator. 99 is normal; lower it to balance layers in Double mode."
            case "Kbd track center": return "The key where keyboard level tracking has no effect."
            case "Kbd track intensity": return "Level change across the keyboard: positive = higher notes louder, negative = quieter."
            case "Velocity sens": return "How much velocity affects level: positive = louder with harder playing (20–50 feels natural), negative = the reverse."
            case "EG time kbd track": return "Amount by which keyboard position shortens/lengthens the amp envelope's segments (chosen with the EG time switches)."
            case "EG time velocity sens": return "Amount by which velocity shortens/lengthens the amp envelope's segments."
            default: break
            }
        case .v1VDAEG, .v2VDAEG:
            switch n {
            case "Attack time": return "Time to reach full level. 0 = percussive, 30–60 = pad swell, 99 = very slow."
            case "Attack level": return "Level at the end of the attack; usually 99."
            case "Decay time": return "Time from the attack level down to the break point."
            case "Break point": return "Intermediate level between decay and slope — lets a sound fall quickly then settle slowly."
            case "Slope time": return "Time from the break point to the sustain level."
            case "Sustain level": return "Level while the key is held: 0 for plucks and drums, 99 for organs and pads."
            case "Release time": return "Fade-out after key-up: ~10 short, ~40 pad-like, 99 very long."
            default: break
            }
        case .v1Switches, .v2Switches:
            return "Which envelope segments (attack, decay, slope, release) the keyboard-tracking or velocity time amount applies to, and its polarity: + = higher keys / harder playing shorten the segment, − = lengthen it."
        default:
            break
        }
        return "M1 program parameter “\(n)”."
    }

    /// Markdown for the guide and the static site: every section, every parameter, with its range and help.
    public static func markdownReference() -> String {
        var out = "## Parameter reference\n\nEvery M1 program parameter the editor exposes, grouped as the editor groups them. Ranges are the M1's own.\n"
        for section in ParamSection.allCases {
            let defs = ParameterMap.definitions(in: section)
            guard !defs.isEmpty else { continue }
            // OSC2 sections mirror OSC1; say so once instead of repeating 40 rows.
            if section.rawValue.hasPrefix("OSC2 ·") {
                if section == .v2PitchEG { out += "\n### OSC2 · Pitch EG, VDF, VDF EG, VDA, VDA EG, EG time switches\n\nIdentical to the OSC1 sections above, applied to the second oscillator (Double mode only).\n" }
                continue
            }
            out += "\n### \(section.rawValue)\n\n| Parameter | Range | Meaning |\n|---|---|---|\n"
            for def in defs {
                out += "| \(def.name) | \(rangeText(def)) | \(text(for: def).replacingOccurrences(of: "|", with: "／")) |\n"
            }
        }
        return out
    }

    public static func rangeText(_ def: ParamDef) -> String {
        switch def.kind {
        case .ascii: return "10 characters"
        case .unsigned(let mx): return "0…\(mx)"
        case .signed(let mn, let mx): return "\(mn)…+\(mx)"
        case .choice(let labels): return labels.joined(separator: " / ")
        case .bits(let fields): return fields.map { $0.width == 1 ? $0.name : "\($0.name): \($0.labels.joined(separator: "/"))" }.joined(separator: ", ")
        case .note: return "C-1…G9"
        case .multisound: return "0…99 (or Drum Kit 1–4 in Drums mode)"
        case .octave: return "16' / 8' / 4'"
        case .pan: return "off, R…L"
        case .effectType: return "1–33 or Thru"
        case .effectParam: return "0…255 (raw)"
        }
    }
}
