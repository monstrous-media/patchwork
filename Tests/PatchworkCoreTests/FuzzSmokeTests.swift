import XCTest
@testable import PatchworkCore

/// In-process stand-in for the FuzzSysEx libFuzzer target (IH-02): the same two entry points fed
/// deterministic junk — random bytes, truncated and corrupted real messages — must throw or return,
/// never trap. The real fuzzer runs for two minutes in CI; this keeps the property under `swift test`
/// on both platforms.
final class FuzzSmokeTests: XCTestCase {

    /// xorshift64*, so a failure reproduces from the seed.
    struct RNG: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state ^= state >> 12; state ^= state << 25; state ^= state >> 27
            return state &* 2685821657736338717
        }
    }

    /// Mirrors Sources/FuzzSysEx/Fuzz.swift.
    func fuzzOne(_ bytes: [UInt8]) {
        _ = try? M1SysEx.parse(bytes)
        _ = KorgPacking.unpack(bytes)
    }

    func testRandomBytesNeverTrap() {
        var rng = RNG(state: 0x9E3779B97F4A7C15)
        for _ in 0..<2000 {
            let n = Int.random(in: 0...600, using: &rng)
            fuzzOne((0..<n).map { _ in UInt8.random(in: 0...255, using: &rng) })
        }
    }

    func testTruncatedAndCorruptedRealMessagesNeverTrap() {
        var rng = RNG(state: 42)
        let p = M1Program()
        let real: [[UInt8]] = [
            M1SysEx.programDump(p),
            M1SysEx.programDumpRequest(),
            M1SysEx.programWriteRequest(slot: 12),
            M1SysEx.modeChange(.program),
            M1SysEx.globalDumpRequest(),
        ]
        for m in real {
            for cut in 0...m.count { fuzzOne(Array(m.prefix(cut))) }               // every truncation
            for _ in 0..<200 {                                                       // random byte flips
                var c = m
                let i = Int.random(in: 0..<c.count, using: &rng)
                c[i] = UInt8.random(in: 0...255, using: &rng)
                fuzzOne(c)
            }
            fuzzOne(m + m)                                                           // two messages run together
            fuzzOne(Array(m.dropLast()) + [0xF0] + m)                                // restarted mid-message
        }
    }

    func testHeaderShapedGarbageNeverTrap() {
        // Valid Korg/M1 header, every function byte, random body lengths including the sizes the
        // parser has opinions about (170-byte program dumps, 991-byte global dumps, 16 KB banks).
        var rng = RNG(state: 7)
        for fn in 0...0x7F {
            for len in [0, 1, 7, 8, 164, 165, 166, 985, 986, 987, 2000] {
                var m: [UInt8] = [0xF0, 0x42, 0x30, 0x19, UInt8(fn)]
                m += (0..<len).map { _ in UInt8.random(in: 0...0x7F, using: &rng) }
                m.append(0xF7)
                fuzzOne(m)
            }
        }
    }
}
