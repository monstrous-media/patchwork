import Foundation

/// One step of a test phrase: a set of notes played together (empty = rest), for `durationMs`,
/// followed by `gapMs` of silence.
public struct PhraseStep: Codable, Equatable, Identifiable {
    public var id: UUID
    public var notes: [Int]
    public var velocity: Int
    public var durationMs: Int
    public var gapMs: Int

    public init(id: UUID = UUID(), notes: [Int], velocity: Int = 100, durationMs: Int = 500, gapMs: Int = 60) {
        self.id = id
        self.notes = notes
        self.velocity = velocity
        self.durationMs = durationMs
        self.gapMs = gapMs
    }

    /// "C4 E4 G4" form of the notes.
    public var notesText: String { notes.map { NoteName.string(for: $0) }.joined(separator: " ") }
}

/// A short, programmable MIDI phrase used to audition a patch while editing it.
public struct TestPhrase: Codable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var steps: [PhraseStep]
    public var loop: Bool

    public init(id: UUID = UUID(), name: String, steps: [PhraseStep], loop: Bool = false) {
        self.id = id
        self.name = name
        self.steps = steps
        self.loop = loop
    }

    public var totalMs: Int { steps.reduce(0) { $0 + $1.durationMs + $1.gapMs } }

    /// Parse "C4 E4 G4" / "c2, g2" / "60 64 67". Empty text is a rest. Returns nil on any bad token.
    public static func parseNotes(_ text: String) -> [Int]? {
        let tokens = text.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\t" }).map(String.init)
        var out: [Int] = []
        for t in tokens {
            guard let n = NoteName.value(for: t) else { return nil }
            out.append(n)
        }
        return out
    }

    // MARK: Presets

    static func step(_ notes: String, vel: Int = 100, gate: Int = 500, gap: Int = 60) -> PhraseStep {
        PhraseStep(notes: parseNotes(notes) ?? [], velocity: vel, durationMs: gate, gapMs: gap)
    }

    public static let presets: [TestPhrase] = [
        TestPhrase(name: "Single note C4", steps: [step("C4", vel: 100, gate: 900, gap: 200)]),
        TestPhrase(name: "Held chord", steps: [step("C4 E4 G4 B4", vel: 90, gate: 2500, gap: 300)]),
        TestPhrase(name: "Pad swell", steps: [step("C3 G3 D4 A4", vel: 70, gate: 4000, gap: 600)]),
        TestPhrase(name: "Staccato", steps: (0..<4).map { _ in step("C4", vel: 110, gate: 80, gap: 170) }, loop: true),
        TestPhrase(name: "Arpeggio", steps: ["C4", "E4", "G4", "B4", "D5", "B4", "G4", "E4"].map { step($0, vel: 100, gate: 150, gap: 25) }, loop: true),
        TestPhrase(name: "Bass riff", steps: [
            step("C2", vel: 120, gate: 200, gap: 40), step("C2", vel: 85, gate: 200, gap: 40),
            step("G1", vel: 110, gate: 200, gap: 40), step("Bb1", vel: 100, gate: 420, gap: 140),
        ], loop: true),
        TestPhrase(name: "Velocity ramp", steps: [30, 60, 90, 120].map { step("C4", vel: $0, gate: 420, gap: 80) }),
        TestPhrase(name: "Octaves", steps: ["C2", "C3", "C4", "C5", "C6"].map { step($0, vel: 100, gate: 450, gap: 60) }),
        TestPhrase(name: "Fifths low/high", steps: [step("C2 G2", vel: 100, gate: 1200, gap: 100), step("C5 G5", vel: 100, gate: 1200, gap: 100)]),
    ]
}
