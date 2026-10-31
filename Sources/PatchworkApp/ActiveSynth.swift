#if os(macOS)
import PatchworkCore

/// The synth this build of the editor drives. Everything in the app goes through `ActiveSynth`
/// (identity, parameter table, pages, SysEx grammar); only the Drum kits page and the MIDI log's
/// decoding of M1 extras (mode, Global data, panel parameter changes) still import M1 types directly.
typealias ActiveSynth = KorgM1
typealias Program = ActiveSynth.Program
#endif
