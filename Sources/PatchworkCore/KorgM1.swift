import Foundation

/// The Korg M1 as a `SynthDefinition`: the first (and reference) implementation.
/// Everything M1-specific that the generic app needs is reachable from here.
public enum KorgM1: SynthDefinition {
    public typealias Program = M1Program

    // MARK: Identity
    public static let id = "korg-m1"
    public static let displayName = "Korg M1"
    public static let bankSize = 100
    public static func slotLabel(_ n: Int) -> String { String(format: "I%02d", n) }

    // MARK: Data model
    public static var parameters: [ParamDef] { ParameterMap.all }
    public static var sections: [ParamSection] { ParamSection.allCases }
    public static func help(for def: ParamDef) -> String { ParameterHelp.text(for: def) }
    public static func sanitise(_ program: inout M1Program) { ParameterMap.sanitise(&program) }

    public static var pages: [EditorPage] {
        func voice(_ base: Int, _ n: Int, peg: ParamSection, vdf: ParamSection, vdfEG: ParamSection, vda: ParamSection, vdaEG: ParamSection, sw: ParamSection) -> EditorPage {
            let f = EnvelopeSpec(title: "VDF EG", attackTime: base + V.vdfEGAttackTime, attackLevel: base + V.vdfEGAttackLevel,
                                 decayTime: base + V.vdfEGDecayTime, breakPoint: base + V.vdfEGBreakPoint, slopeTime: base + V.vdfEGSlopeTime,
                                 sustainLevel: base + V.vdfEGSustainLevel, releaseTime: base + V.vdfEGReleaseTime, signedLevels: true)
            let a = EnvelopeSpec(title: "VDA EG", attackTime: base + V.vdaEGAttackTime, attackLevel: base + V.vdaEGAttackLevel,
                                 decayTime: base + V.vdaEGDecayTime, breakPoint: base + V.vdaEGBreakPoint, slopeTime: base + V.vdaEGSlopeTime,
                                 sustainLevel: base + V.vdaEGSustainLevel, releaseTime: base + V.vdaEGReleaseTime, signedLevels: false)
            return EditorPage(id: "osc\(n)", title: "OSC \(n)", systemImage: "\(n).circle", rows: [
                [.section(vdf), .sectionWithEnvelope(vdfEG, f)],
                [.section(vda), .sectionWithEnvelope(vdaEG, a)],
                [.section(peg), .section(sw)],
            ])
        }
        return [
            EditorPage(id: "program", title: "Program", systemImage: "slider.horizontal.3", rows: [
                [.section(.general)], [.section(.oscillators)],
                [.section(.pitchMG), .section(.vdfMG)],
                [.section(.aftertouch), .section(.joystick)],
            ]),
            EditorPage(id: "effects", title: "Effects", systemImage: "waveform.path.ecg", rows: [[.section(.effects)]]),
            voice(P.voice1Base, 1, peg: .v1PitchEG, vdf: .v1VDF, vdfEG: .v1VDFEG, vda: .v1VDA, vdaEG: .v1VDAEG, sw: .v1Switches),
            voice(P.voice2Base, 2, peg: .v2PitchEG, vdf: .v2VDF, vdfEG: .v2VDFEG, vda: .v2VDA, vdaEG: .v2VDAEG, sw: .v2Switches),
        ]
    }

    /// One line for lists: mode and sources.
    public static func summary(_ p: M1Program) -> String {
        let mode = p.unsigned(P.oscMode)
        if mode == 2 { return "drums · Drum Kit \(min(4, p.unsigned(P.osc1Multisound) + 1))" }
        let a = Multisounds.name(for: p.unsigned(P.osc1Multisound))
        if mode == 1 { return "double · \(a) + \(Multisounds.name(for: p.unsigned(P.osc2Multisound)))" }
        return "single · \(a)"
    }

    // MARK: Transport
    public static func isMessage(_ bytes: [UInt8]) -> Bool { M1SysEx.isM1Message(bytes) }

    public static func parse(_ bytes: [UInt8]) -> (channel: UInt8, message: SynthMessage)? {
        guard let r = try? M1SysEx.parse(bytes) else { return nil }
        let m: SynthMessage
        switch r.message {
        case .programDump(let p): m = .programDump(p.bytes)
        case .allProgramDump(let ps): m = .bankDump(ps.map { $0.bytes })
        case .loadCompleted: m = .loadCompleted
        case .loadError: m = .loadError
        case .writeCompleted: m = .writeCompleted
        case .writeError: m = .writeError
        case .formatError: m = .formatError
        default: m = .other(summary: r.message.summary)
        }
        return (r.channel, m)
    }

    /// The M1 answers program requests only in Program mode.
    public static func prepareForTransfer(channel: UInt8) -> [[UInt8]] { [M1SysEx.modeChange(.program, channel: channel)] }
    public static func programDumpRequest(channel: UInt8) -> [UInt8] { M1SysEx.programDumpRequest(channel: channel) }
    public static func programDump(_ program: M1Program, channel: UInt8) -> [UInt8] { M1SysEx.programDump(program, channel: channel) }
    public static func writeRequest(slot: Int, channel: UInt8) -> [UInt8]? { M1SysEx.programWriteRequest(slot: slot, channel: channel) }
    public static let hasEditBuffer = true

    // MARK: Files
    public static func programs(inSyx bytes: [UInt8]) -> [M1Program] { M1SysEx.programs(inSyx: bytes) }
    public static func json(for program: M1Program) throws -> Data { try M1Patch(program: program).jsonData() }
    public static func program(fromJSON data: Data) throws -> M1Program { try M1Patch.decode(json: data).toProgram() }
    public static let jsonFormatID = M1Patch.formatID

    // MARK: Generators (the generic ones, plus "keep it playable" tweaks)
    public static func randomise(base: M1Program, seed: UInt64) -> M1Program {
        Mutation.randomise(definitions: parameters, base: base, seed: seed) { p, rng in
            for b in [P.voice1Base, P.voice2Base] {
                p.setUnsigned(b + V.vdaLevel, Int.random(in: 70...99, using: &rng))
                p.setUnsigned(b + V.vdaEGAttackLevel, Int.random(in: 60...99, using: &rng))
                p.setUnsigned(b + V.vdaEGSustainLevel, Int.random(in: 0...99, using: &rng))
            }
            p.setUnsigned(P.oscMode, Int.random(in: 0...1, using: &rng))   // single or double; drums are a different beast
            p.setUnsigned(P.osc1Multisound, Int.random(in: 0...99, using: &rng))
            p.setUnsigned(P.osc2Multisound, Int.random(in: 0...99, using: &rng))
            p.setUnsigned(P.effectIO, 0x0F | (p.unsigned(P.effectIO) & 0x10))
            p.name = "RND \(String(seed % 100000))"
        }
    }
}
