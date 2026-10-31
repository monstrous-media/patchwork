import Foundation

/// Korg M1 System Exclusive messages.
///
///     F0 42 3g 19 ff dd … dd F7
///     42 = Korg · 3g = global MIDI channel g (0–15) · 19 = M1 family · ff = function
public enum M1SysEx {

    public static let korgID: UInt8 = 0x42
    public static let m1FamilyID: UInt8 = 0x19
    public static let programCount = 100

    public enum Function: UInt8 {
        // Requests (host → M1)
        case modeRequest = 0x12
        case programDumpRequest = 0x10
        case allProgramDumpRequest = 0x1C
        case combinationDumpRequest = 0x19
        case allCombinationDumpRequest = 0x1D
        case allSequenceDumpRequest = 0x18
        case globalDumpRequest = 0x0E
        case allDataDumpRequest = 0x0F
        case programWriteRequest = 0x11
        case combinationWriteRequest = 0x1A
        // Dumps (either direction)
        case programDump = 0x40
        case allProgramDump = 0x4C
        case combinationDump = 0x49
        case allCombinationDump = 0x4D
        case allSequenceDump = 0x48
        case globalDump = 0x51
        case allDataDump = 0x50
        case parameterChange = 0x41
        case modeChange = 0x4E
        case modeData = 0x42
        // Replies (M1 → host)
        case writeCompleted = 0x21
        case writeError = 0x22
        case loadCompleted = 0x23
        case loadError = 0x24
        case formatError = 0x26
    }

    /// Operating modes as reported by Mode Data (0x42) and set by Mode Change (0x4E).
    public enum Mode: UInt8, CaseIterable {
        case combination = 0
        case editCombination = 1
        case program = 2
        case editProgram = 3
        case global = 4
        case sequencer = 6

        public var name: String {
            switch self {
            case .combination: return "Combination"
            case .editCombination: return "Combination edit"
            case .program: return "Program"
            case .editProgram: return "Program edit"
            case .global: return "Global"
            case .sequencer: return "Sequencer"
            }
        }

        public static func named(_ s: String) -> Mode? {
            let k = s.lowercased()
            if k.hasPrefix("prog") { return .program }
            if k.hasPrefix("comb") { return .combination }
            if k.hasPrefix("glob") { return .global }
            if k.hasPrefix("seq") { return .sequencer }
            return nil
        }
    }

    public enum Message: Equatable {
        case programDump(M1Program)
        case allProgramDump([M1Program])
        case parameterChange(page: UInt8, position: UInt8, value: Int)
        case globalDump(M1GlobalData)
        /// Body: mode, bank (0 internal / 1 card), card status, PCM card status.
        case modeData([UInt8])
        case writeCompleted
        case writeError
        case loadCompleted
        case loadError
        case formatError
        case other(function: UInt8, body: [UInt8])

        public var isAck: Bool {
            switch self {
            case .writeCompleted, .writeError, .loadCompleted, .loadError, .formatError: return true
            default: return false
            }
        }

        public var summary: String {
            switch self {
            case .programDump(let p): return "Program dump “\(p.name)”"
            case .allProgramDump(let ps): return "All-program dump (\(ps.count) programs)"
            case .parameterChange(let pg, let po, let v): return "Parameter change page \(pg) pos \(po) = \(v)"
            case .globalDump(let g): return "Global data dump (\(g.bytes.count) bytes, 4 drum kits)"
            case .modeData(let b):
                let mode = b.first.flatMap { Mode(rawValue: $0) }
                let bank = b.count > 1 ? (b[1] == 0 ? "internal" : "card") : "?"
                let modeName = mode?.name ?? "unknown(\(b.first.map { String($0) } ?? "-"))"
                return "Mode: \(modeName), bank \(bank)  [\(hex(b))]"
            case .writeCompleted: return "Write completed"
            case .writeError: return "Write error (memory protect on?)"
            case .loadCompleted: return "Data load completed"
            case .loadError: return "Data load error"
            case .formatError: return "Received message format error"
            case .other(let f, let b): return "Function 0x\(String(f, radix: 16)) (\(b.count) bytes)"
            }
        }
    }

    // MARK: Builders

    static func header(channel: UInt8, _ fn: Function) -> [UInt8] {
        [0xF0, korgID, 0x30 | (channel & 0x0F), m1FamilyID, fn.rawValue]
    }

    /// 0x10 — ask for the program currently in the edit buffer.
    public static func programDumpRequest(channel: UInt8 = 0) -> [UInt8] {
        header(channel: channel, .programDumpRequest) + [0xF7]
    }

    /// 0x1C — ask for all 100 internal programs (16,350 bytes back; some interfaces choke on it).
    public static func allProgramDumpRequest(channel: UInt8 = 0) -> [UInt8] {
        header(channel: channel, .allProgramDumpRequest) + [0x00, 0xF7]
    }

    /// 0x0E — ask for the Global data (settings + the four drum kits). Reply is 0x51.
    public static func globalDumpRequest(channel: UInt8 = 0) -> [UInt8] {
        header(channel: channel, .globalDumpRequest) + [0x00, 0xF7]
    }

    /// 0x51 — send Global data back (the M1 replies 0x23 load completed).
    public static func globalDump(_ g: M1GlobalData, channel: UInt8 = 0) -> [UInt8] {
        header(channel: channel, .globalDump) + [0x00] + KorgPacking.pack(g.bytes) + [0xF7]
    }

    public static func modeRequest(channel: UInt8 = 0) -> [UInt8] {
        header(channel: channel, .modeRequest) + [0xF7]
    }

    /// 0x4E — switch the M1's mode (internal bank). Reply is 0x23 load completed / 0x24 load error.
    public static func modeChange(_ mode: Mode, card: Bool = false, channel: UInt8 = 0) -> [UInt8] {
        header(channel: channel, .modeChange) + [mode.rawValue, card ? 0x01 : 0x00, 0xF7]
    }

    /// The mode a parsed Mode Data message reports, if any.
    public static func mode(from message: Message) -> Mode? {
        if case .modeData(let b) = message, let first = b.first { return Mode(rawValue: first) }
        return nil
    }

    /// 0x40 — send a program into the M1's edit buffer (not stored until a write request).
    public static func programDump(_ program: M1Program, channel: UInt8 = 0) -> [UInt8] {
        header(channel: channel, .programDump) + KorgPacking.pack(program.bytes) + [0xF7]
    }

    /// 0x4C — all 100 programs in one message.
    public static func allProgramDump(_ programs: [M1Program], channel: UInt8 = 0) -> [UInt8] {
        precondition(programs.count == programCount, "need exactly \(programCount) programs")
        let raw = programs.flatMap { $0.bytes }
        return header(channel: channel, .allProgramDump) + [0x00] + KorgPacking.pack(raw) + [0xF7]
    }

    /// 0x11 — store the edit buffer into internal program slot 0–99 (memory protect must be off).
    public static func programWriteRequest(slot: Int, channel: UInt8 = 0) -> [UInt8] {
        precondition(slot >= 0 && slot <= 99)
        return header(channel: channel, .programWriteRequest) + [0x00, UInt8(slot), 0xF7]
    }

    /// 0x41 — single parameter change. `page`/`position` follow the M1's panel edit pages
    /// (learn them with `patchwork monitor` while editing on the front panel).
    public static func parameterChange(page: UInt8, position: UInt8, value: Int, channel: UInt8 = 0) -> [UInt8] {
        let v = UInt16(bitPattern: Int16(clamping: value))
        return header(channel: channel, .parameterChange) + [page, position, UInt8(v & 0x7F), UInt8((v >> 7) & 0x7F), 0xF7]
    }

    // MARK: Parsing

    public static func isM1Message(_ bytes: [UInt8]) -> Bool {
        bytes.count >= 6 && bytes[0] == 0xF0 && bytes[1] == korgID && (bytes[2] & 0xF0) == 0x30 && bytes[3] == m1FamilyID
    }

    public static func parse(_ bytes: [UInt8]) throws -> (channel: UInt8, message: Message) {
        guard bytes.count >= 6, bytes.first == 0xF0, bytes.last == 0xF7 else { throw M1Error.notSysEx }
        guard isM1Message(bytes) else { throw M1Error.notM1 }
        let channel = bytes[2] & 0x0F
        let fnByte = bytes[4]
        let body = Array(bytes[5..<(bytes.count - 1)])
        guard let fn = Function(rawValue: fnByte) else {
            return (channel, .other(function: fnByte, body: body))
        }
        switch fn {
        case .programDump:
            let raw = KorgPacking.unpack(body)
            guard raw.count == M1Program.byteCount else {
                throw M1Error.badUnpackedSize(expected: M1Program.byteCount, got: raw.count)
            }
            return (channel, .programDump(try M1Program(bytes: raw)))
        case .allProgramDump:
            guard body.count >= 1 else { throw M1Error.truncated }
            let raw = KorgPacking.unpack(Array(body.dropFirst()))
            let expected = M1Program.byteCount * programCount
            guard raw.count == expected else { throw M1Error.badUnpackedSize(expected: expected, got: raw.count) }
            var programs: [M1Program] = []
            programs.reserveCapacity(programCount)
            for i in 0..<programCount {
                let start = i * M1Program.byteCount
                programs.append(try M1Program(bytes: Array(raw[start..<(start + M1Program.byteCount)])))
            }
            return (channel, .allProgramDump(programs))
        case .parameterChange:
            guard body.count >= 4 else { throw M1Error.truncated }
            let v = UInt16(body[2] & 0x7F) | (UInt16(body[3] & 0x7F) << 7)
            // 14 bits carried; sign-extend from bit 13 so small negative values read naturally.
            let signed = v & 0x2000 != 0 ? Int(v) - 0x4000 : Int(v)
            return (channel, .parameterChange(page: body[0], position: body[1], value: signed))
        case .globalDump:
            guard body.count >= 1 else { throw M1Error.truncated }
            let raw = KorgPacking.unpack(Array(body.dropFirst()))
            guard raw.count >= M1GlobalData.minimumByteCount else {
                return (channel, .other(function: fnByte, body: body))   // unknown layout: keep raw
            }
            return (channel, .globalDump(try M1GlobalData(bytes: raw)))
        case .modeData: return (channel, .modeData(body))
        case .writeCompleted: return (channel, .writeCompleted)
        case .writeError: return (channel, .writeError)
        case .loadCompleted: return (channel, .loadCompleted)
        case .loadError: return (channel, .loadError)
        case .formatError: return (channel, .formatError)
        default:
            return (channel, .other(function: fnByte, body: body))
        }
    }

    /// Split a byte stream (e.g. a .syx file) into complete F0…F7 messages.
    public static func splitMessages(_ bytes: [UInt8]) -> [[UInt8]] {
        var out: [[UInt8]] = []
        var current: [UInt8] = []
        var inMessage = false
        for b in bytes {
            if b == 0xF0 { current = [b]; inMessage = true }
            else if inMessage {
                current.append(b)
                if b == 0xF7 { out.append(current); current = []; inMessage = false }
            }
        }
        return out
    }

    /// Every program found in a .syx byte stream (single dumps and all-program dumps).
    public static func programs(inSyx bytes: [UInt8]) -> [M1Program] {
        var result: [M1Program] = []
        for msg in splitMessages(bytes) {
            guard let parsed = try? parse(msg) else { continue }
            switch parsed.message {
            case .programDump(let p): result.append(p)
            case .allProgramDump(let ps): result.append(contentsOf: ps)
            default: break
            }
        }
        return result
    }
}

public func hex(_ bytes: [UInt8], separator: String = " ") -> String {
    bytes.map { String(format: "%02X", $0) }.joined(separator: separator)
}

public func bytesFromHex(_ string: String) -> [UInt8]? {
    let cleaned = string.filter { !$0.isWhitespace }
    guard cleaned.count % 2 == 0 else { return nil }
    var out: [UInt8] = []
    var idx = cleaned.startIndex
    while idx < cleaned.endIndex {
        let next = cleaned.index(idx, offsetBy: 2)
        guard let b = UInt8(cleaned[idx..<next], radix: 16) else { return nil }
        out.append(b)
        idx = next
    }
    return out
}
