import Foundation

/// One Korg M1 program: the 143 raw parameter bytes of a Program Parameter Dump (function 0x40),
/// in transmission order. Typed access goes through `ParameterMap` / `M1Patch`.
public struct M1Program: ProgramData {

    public static let byteCount = 143
    public static let nameLength = 10

    public var bytes: [UInt8]

    public init() {
        bytes = M1Program.initBytes
    }

    public init(bytes: [UInt8]) throws {
        guard bytes.count == M1Program.byteCount else {
            throw M1Error.wrongProgramSize(bytes.count)
        }
        self.bytes = bytes
    }

    // MARK: Raw access

    public subscript(index: Int) -> UInt8 {
        get { bytes[index] }
        set { bytes[index] = newValue }
    }

    /// Two's-complement read of a byte (used for -99…+99 style parameters).
    public func signed(_ index: Int) -> Int {
        Int(Int8(bitPattern: bytes[index]))
    }

    public mutating func setSigned(_ index: Int, _ value: Int) {
        let clamped = max(-128, min(127, value))
        bytes[index] = UInt8(bitPattern: Int8(clamped))
    }

    public func unsigned(_ index: Int) -> Int {
        Int(bytes[index])
    }

    public mutating func setUnsigned(_ index: Int, _ value: Int) {
        bytes[index] = UInt8(max(0, min(255, value)))
    }

    public func bit(_ index: Int, _ bit: Int) -> Bool {
        (bytes[index] >> UInt8(bit)) & 1 == 1
    }

    public mutating func setBit(_ index: Int, _ bit: Int, _ on: Bool) {
        if on { bytes[index] |= UInt8(1 << bit) } else { bytes[index] &= ~UInt8(1 << bit) }
    }

    public func field(_ index: Int, shift: Int, width: Int) -> Int {
        Int((bytes[index] >> UInt8(shift)) & UInt8((1 << width) - 1))
    }

    public mutating func setField(_ index: Int, shift: Int, width: Int, _ value: Int) {
        let mask = UInt8(((1 << width) - 1) << shift)
        bytes[index] = (bytes[index] & ~mask) | (UInt8(max(0, min((1 << width) - 1, value)) << shift) & mask)
    }

    // MARK: Name

    public var name: String {
        get {
            let chars = bytes[0..<M1Program.nameLength].map { b -> Character in
                (b >= 0x20 && b < 0x7F) ? Character(UnicodeScalar(b)) : " "
            }
            return String(chars).trimmingCharacters(in: .whitespaces)
        }
        set {
            var ascii = Array(newValue.unicodeScalars.map { s -> UInt8 in
                (s.value >= 0x20 && s.value < 0x7F) ? UInt8(s.value) : 0x20
            })
            if ascii.count > M1Program.nameLength { ascii = Array(ascii.prefix(M1Program.nameLength)) }
            while ascii.count < M1Program.nameLength { ascii.append(0x20) }
            bytes.replaceSubrange(0..<M1Program.nameLength, with: ascii)
        }
    }

    // MARK: Init program

    /// A neutral starting point: single oscillator, A.Piano, filter open, VDA sustaining, Hall + Thru.
    public static let initBytes: [UInt8] = {
        var p = [UInt8](repeating: 0, count: byteCount)
        let name = Array("INIT      ".utf8)
        p.replaceSubrange(0..<10, with: name)
        p[P.oscMode] = 0
        p[P.pitchMGFlags] = 0x60      // triangle, OSC1 + OSC2 enabled
        p[P.vdfMGFlags] = 0x60
        p[P.jsPitchBend] = 2
        p[P.effect1Type] = 0          // Hall
        p[P.effect2Type] = 0x21       // Thru
        p[P.effect1BalL] = 50; p[P.effect1BalR] = 50
        p[P.effect2BalL] = 50; p[P.effect2BalR] = 50
        p[P.effectIO] = 0x0F          // all four effect channels on, parallel
        for base in [P.voice1Base, P.voice2Base] {
            p[base + V.vdfCutoff] = 99
            p[base + V.vdfKbdTrackCenter] = 60
            p[base + V.vdaLevel] = 99
            p[base + V.vdaKbdTrackCenter] = 60
            p[base + V.vdaEGAttackLevel] = 99
            p[base + V.vdaEGSustainLevel] = 99
        }
        return p
    }()
}

/// Compact JSON form for storage: the 143 bytes as one hex string.
extension M1Program: Codable {
    public init(from decoder: Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        guard let bytes = bytesFromHex(s) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "program must be a hex string"))
        }
        try self.init(bytes: bytes)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(hex(bytes, separator: ""))
    }
}

public enum M1Error: Error, CustomStringConvertible, Equatable {
    case wrongProgramSize(Int)
    case notSysEx
    case notM1
    case truncated
    case badUnpackedSize(expected: Int, got: Int)
    case invalidValue(field: String, reason: String)

    public var description: String {
        switch self {
        case .wrongProgramSize(let n): return "program must be \(M1Program.byteCount) bytes, got \(n)"
        case .notSysEx: return "not a complete SysEx message (F0 … F7)"
        case .notM1: return "not a Korg M1 message (expected F0 42 3n 19 …)"
        case .truncated: return "message truncated"
        case .badUnpackedSize(let e, let g): return "unpacked payload is \(g) bytes, expected \(e)"
        case .invalidValue(let f, let r): return "\(f): \(r)"
        }
    }
}
