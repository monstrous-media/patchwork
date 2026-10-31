import Foundation

// MARK: - The contract a synthesizer definition fulfils
//
// Everything above this line in the stack (MIDI engine, transfers, banks, generic editor, generators,
// play bar, help) is synth-agnostic. A synth is: a program byte layout + a parameter table that
// describes it + the SysEx grammar to read and write it. One file per synth, plus test vectors.

/// A stored program's raw bytes with a name — the unit the librarian and transfers move around.
public protocol ProgramData: Equatable, Hashable, Codable {
    static var byteCount: Int { get }
    var bytes: [UInt8] { get set }
    init(bytes: [UInt8]) throws
    /// A neutral starting point.
    init()
    var name: String { get set }

    // Typed accessors used by the generic editor and generators.
    func unsigned(_ index: Int) -> Int
    mutating func setUnsigned(_ index: Int, _ value: Int)
    func signed(_ index: Int) -> Int
    mutating func setSigned(_ index: Int, _ value: Int)
    func bit(_ index: Int, _ bit: Int) -> Bool
    mutating func setBit(_ index: Int, _ bit: Int, _ on: Bool)
    func field(_ index: Int, shift: Int, width: Int) -> Int
    mutating func setField(_ index: Int, shift: Int, width: Int, _ value: Int)
}

/// Messages the generic layer understands. Anything else is `.other` and left to synth-specific code.
public enum SynthMessage: Equatable {
    case programDump([UInt8])          // one program's raw bytes
    case bankDump([[UInt8]])           // a whole bank
    case loadCompleted                 // data accepted into the edit buffer / memory
    case loadError
    case writeCompleted
    case writeError
    case formatError
    case other(summary: String)

    public var isAck: Bool {
        switch self {
        case .loadCompleted, .loadError, .writeCompleted, .writeError, .formatError: return true
        default: return false
        }
    }
}

/// How the editor lays a page out: rows of blocks, each a parameter section or an envelope sketch.
public struct EnvelopeSpec: Equatable {
    public let title: String
    public let attackTime: Int, attackLevel: Int, decayTime: Int, breakPoint: Int, slopeTime: Int, sustainLevel: Int, releaseTime: Int
    public let signedLevels: Bool
    public init(title: String, attackTime: Int, attackLevel: Int, decayTime: Int, breakPoint: Int, slopeTime: Int, sustainLevel: Int, releaseTime: Int, signedLevels: Bool) {
        self.title = title; self.attackTime = attackTime; self.attackLevel = attackLevel; self.decayTime = decayTime
        self.breakPoint = breakPoint; self.slopeTime = slopeTime; self.sustainLevel = sustainLevel; self.releaseTime = releaseTime
        self.signedLevels = signedLevels
    }
}

public enum PageBlock: Equatable {
    case section(ParamSection)
    /// A section with an envelope drawing underneath it.
    case sectionWithEnvelope(ParamSection, EnvelopeSpec)
}

public struct EditorPage: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let systemImage: String
    /// Rows of blocks laid out side by side.
    public let rows: [[PageBlock]]
    public init(id: String, title: String, systemImage: String, rows: [[PageBlock]]) {
        self.id = id; self.title = title; self.systemImage = systemImage; self.rows = rows
    }
}

public protocol SynthDefinition {
    associatedtype Program: ProgramData

    // Identity
    static var id: String { get }                 // "korg-m1"
    static var displayName: String { get }        // "Korg M1"
    static var bankSize: Int { get }              // slots per bank on the instrument
    static func slotLabel(_ n: Int) -> String     // "I57"

    // Data model
    static var parameters: [ParamDef] { get }
    static var sections: [ParamSection] { get }
    static var pages: [EditorPage] { get }
    static func help(for def: ParamDef) -> String
    /// Clamp a program's bytes into documented ranges.
    static func sanitise(_ program: inout Program)
    /// One short line describing a program for lists (sources, mode…).
    static func summary(_ program: Program) -> String

    // Transport (SysEx). Channel is the instrument's device/global channel, 0-based.
    static func isMessage(_ bytes: [UInt8]) -> Bool
    static func parse(_ bytes: [UInt8]) -> (channel: UInt8, message: SynthMessage)?
    /// Messages to send before a transfer so the instrument will answer (e.g. a mode change). May be empty.
    static func prepareForTransfer(channel: UInt8) -> [[UInt8]]
    static func programDumpRequest(channel: UInt8) -> [UInt8]
    static func programDump(_ program: Program, channel: UInt8) -> [UInt8]
    /// Store the edit buffer into a slot; nil if the instrument has no such message.
    static func writeRequest(slot: Int, channel: UInt8) -> [UInt8]?
    /// Select a stored program (used to walk a bank). Default: a MIDI Program Change.
    static func selectProgram(slot: Int, channel: UInt8) -> [UInt8]
    /// Does sending a program dump land in a temporary edit buffer (true) or overwrite memory directly (false)?
    static var hasEditBuffer: Bool { get }

    // Files
    /// All programs found in a byte stream (.syx file).
    static func programs(inSyx bytes: [UInt8]) -> [Program]
    /// Human-readable JSON for a program (the Claude-authorable format), and back.
    static func json(for program: Program) throws -> Data
    static func program(fromJSON data: Data) throws -> Program
    static var jsonFormatID: String { get }
}

public extension SynthDefinition {
    static func slotLabel(_ n: Int) -> String { String(format: "%02d", n) }
    static func summary(_ program: Program) -> String { program.name }
    static func selectProgram(slot: Int, channel: UInt8) -> [UInt8] { [0xC0 | (channel & 0x0F), UInt8(max(0, min(127, slot)))] }
    static var hasEditBuffer: Bool { true }
    static func prepareForTransfer(channel: UInt8) -> [[UInt8]] { [] }
    static var sections: [ParamSection] {
        var seen: [ParamSection] = []
        for d in parameters where !seen.contains(d.section) { seen.append(d.section) }
        return seen
    }
    static func definitions(in section: ParamSection) -> [ParamDef] { parameters.filter { $0.section == section } }
}
