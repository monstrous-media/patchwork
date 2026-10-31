import Foundation

/// One entry of an M1 drum kit: which drum instrument sounds on which key, and how.
/// (A keymap entry, in sampler terms: the M1's kits are one-instrument-per-key maps of its 44 drum samples.)
public struct DrumKitEntry: Equatable, Codable {
    /// 0 = off / no assign, 1…44 = internal drum instrument (see DrumSounds.names), 45+ = PCM card.
    public var instrument: Int
    /// MIDI note number the instrument is placed on (C0 = 12 … G8 = 115).
    public var key: Int
    /// 0 = A (10:0) … 5 = centre … 10 = B (0:10); 11 = C, 12 = C+D, 13 = D (the individual outputs).
    public var pan: Int
    /// −120…+120 — tune in tenths of a semitone (±1 octave).
    public var tune: Int
    /// −50…+50 level offset.
    public var level: Int
    /// −50…+50 decay offset.
    public var decay: Int

    public init(instrument: Int = 0, key: Int = 60, pan: Int = 5, tune: Int = 0, level: Int = 0, decay: Int = 0) {
        self.instrument = instrument; self.key = key; self.pan = pan; self.tune = tune; self.level = level; self.decay = decay
    }

    public var isAssigned: Bool { instrument != 0 }

    public var instrumentName: String {
        if instrument == 0 { return "Off" }
        if instrument < DrumSounds.names.count { return DrumSounds.names[instrument] }
        return "card:\(instrument - DrumSounds.names.count + 1)"
    }

    public static let panLabels = ["A", "9:1", "8:2", "7:3", "6:4", "5:5", "4:6", "3:7", "2:8", "1:9", "B", "C", "C+D", "D"]
    public var panLabel: String { (0..<DrumKitEntry.panLabels.count).contains(pan) ? DrumKitEntry.panLabels[pan] : "?" }
}

/// The M1's Global data as carried by the Global Data Dump (function 0x51):
/// 21 bytes of global settings followed by 4 drum kits × 30 entries × 7 bytes = 861 bytes.
/// Extra bytes (newer OS versions) are kept untouched so a dump round-trips exactly.
public struct M1GlobalData: Equatable {
    public static let settingsLength = 21
    public static let kitCount = 4
    public static let entriesPerKit = 30
    public static let entryLength = 7
    public static let minimumByteCount = settingsLength + kitCount * entriesPerKit * entryLength   // 861

    public var bytes: [UInt8]

    public init(bytes: [UInt8]) throws {
        guard bytes.count >= M1GlobalData.minimumByteCount else {
            throw M1Error.badUnpackedSize(expected: M1GlobalData.minimumByteCount, got: bytes.count)
        }
        self.bytes = bytes
    }

    // Global settings (indices from the manual's Table 3)
    public enum G {
        public static let masterTune = 0        // −50…+50
        public static let keyTranspose = 1      // −12…+12
        public static let damperPolarity = 2    // 0 up / 1 down
        public static let pedal1 = 3            // 0–9
        public static let pedal2 = 4
        public static let scaleType = 5         // 0 equal 1, 1 equal 2, 2 pure major, 3 pure minor, 4 user
        public static let pureKey = 6           // 0–11
        public static let userScale = 7         // 7…18, one per semitone, −50…+50 cents
    }

    public static let pedalFunctions = ["Prog/Combi up", "Prog/Combi down", "Seq start/stop", "Effect 1 on/off", "Effect 2 on/off",
                                        "Volume", "VDF cutoff", "Effect 1 control", "Effect 2 control", "Data entry"]
    public static let scaleTypes = ["Equal temperament 1", "Equal temperament 2", "Pure major", "Pure minor", "User"]

    public func signed(_ i: Int) -> Int { Int(Int8(bitPattern: bytes[i])) }
    public mutating func setSigned(_ i: Int, _ v: Int) { bytes[i] = UInt8(bitPattern: Int8(max(-128, min(127, v)))) }

    // Drum kits

    public static func entryOffset(kit: Int, index: Int) -> Int {
        settingsLength + (kit * entriesPerKit + index) * entryLength
    }

    public func entry(kit: Int, index: Int) -> DrumKitEntry {
        let o = M1GlobalData.entryOffset(kit: kit, index: index)
        return DrumKitEntry(instrument: Int(bytes[o]), key: Int(bytes[o + 1]), pan: Int(bytes[o + 2]),
                            tune: signed(o + 3), level: signed(o + 4), decay: signed(o + 5))
    }

    public mutating func setEntry(_ e: DrumKitEntry, kit: Int, index: Int) {
        let o = M1GlobalData.entryOffset(kit: kit, index: index)
        bytes[o] = UInt8(max(0, min(255, e.instrument)))
        bytes[o + 1] = UInt8(max(0, min(127, e.key)))
        bytes[o + 2] = UInt8(max(0, min(13, e.pan)))
        setSigned(o + 3, max(-120, min(120, e.tune)))
        setSigned(o + 4, max(-50, min(50, e.level)))
        setSigned(o + 5, max(-50, min(50, e.decay)))
        bytes[o + 6] = 0
    }

    public func kit(_ k: Int) -> [DrumKitEntry] {
        (0..<M1GlobalData.entriesPerKit).map { entry(kit: k, index: $0) }
    }

    public mutating func setKit(_ k: Int, _ entries: [DrumKitEntry]) {
        for (i, e) in entries.prefix(M1GlobalData.entriesPerKit).enumerated() { setEntry(e, kit: k, index: i) }
    }

    /// Human summary of one kit, key order.
    public func kitSummary(_ k: Int) -> [String] {
        func pad(_ s: String, _ n: Int) -> String { s.count >= n ? s : s + String(repeating: " ", count: n - s.count) }
        func signed(_ v: Int) -> String { v >= 0 ? "+\(v)" : "\(v)" }
        return kit(k).enumerated().filter { $0.element.isAssigned }.sorted { $0.element.key < $1.element.key }.map { pair in
            let (i, e) = pair
            let idx = i < 10 ? "0\(i)" : "\(i)"
            return "#\(idx)  \(pad(NoteName.string(for: e.key), 5)) \(pad(e.instrumentName, 11)) pan \(pad(e.panLabel, 4)) tune \(signed(e.tune))  level \(signed(e.level))  decay \(signed(e.decay))"
        }
    }
}

/// JSON form of a kit for files and for Claude: just the assigned entries.
public struct DrumKitPatch: Codable, Equatable {
    public static let formatID = "korg-m1-drumkit/1"
    public var format: String? = DrumKitPatch.formatID
    public var kit: Int                 // 1–4
    public var entries: [Entry]

    public struct Entry: Codable, Equatable {
        public var instrument: String   // drum instrument name, "off", or number 1–44
        public var key: String          // note name, e.g. "C2"
        public var pan: String          // "A", "5:5", "B", "C", "C+D", "D"
        public var tune: Int
        public var level: Int
        public var decay: Int
    }

    public init(kit k: Int, entries: [DrumKitEntry]) {
        kit = k + 1
        self.entries = entries.filter { $0.isAssigned }.map {
            Entry(instrument: $0.instrumentName, key: NoteName.string(for: $0.key), pan: $0.panLabel, tune: $0.tune, level: $0.level, decay: $0.decay)
        }
    }

    public func toEntries() throws -> [DrumKitEntry] {
        guard entries.count <= M1GlobalData.entriesPerKit else {
            throw M1Error.invalidValue(field: "entries", reason: "a kit holds at most \(M1GlobalData.entriesPerKit) entries")
        }
        var out: [DrumKitEntry] = []
        for (i, e) in entries.enumerated() {
            let f = "entries[\(i)]"
            let inst: Int
            let s = e.instrument.trimmingCharacters(in: .whitespaces).lowercased()
            if s == "off" || s == "none" { inst = 0 }
            else if let n = Int(s), (0...255).contains(n) { inst = n }
            else if let idx = DrumSounds.names.firstIndex(where: { $0.lowercased() == s }) { inst = idx }
            else { throw M1Error.invalidValue(field: f + ".instrument", reason: "unknown drum instrument “\(e.instrument)”") }
            guard let key = NoteName.value(for: e.key) else { throw M1Error.invalidValue(field: f + ".key", reason: "“\(e.key)” is not a note name") }
            guard let pan = DrumKitEntry.panLabels.firstIndex(where: { $0.lowercased() == e.pan.lowercased() }) else {
                throw M1Error.invalidValue(field: f + ".pan", reason: "pan must be one of \(DrumKitEntry.panLabels.joined(separator: ", "))")
            }
            guard (-120...120).contains(e.tune) else { throw M1Error.invalidValue(field: f + ".tune", reason: "\(e.tune) is outside -120…+120") }
            guard (-50...50).contains(e.level) else { throw M1Error.invalidValue(field: f + ".level", reason: "\(e.level) is outside -50…+50") }
            guard (-50...50).contains(e.decay) else { throw M1Error.invalidValue(field: f + ".decay", reason: "\(e.decay) is outside -50…+50") }
            out.append(DrumKitEntry(instrument: inst, key: key, pan: pan, tune: e.tune, level: e.level, decay: e.decay))
        }
        while out.count < M1GlobalData.entriesPerKit { out.append(DrumKitEntry(instrument: 0, key: 0)) }
        return out
    }
}
