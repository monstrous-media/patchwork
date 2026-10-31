import Foundation

/// Korg's 7-in-8 SysEx data packing, as used by the M1 (and most Korg synths of the era).
///
/// Each group of up to 7 data bytes is transmitted as 8 MIDI bytes: a leading byte
/// holding bit 7 of each of the following data bytes (bit 0 ↔ first data byte),
/// followed by the data bytes with bit 7 cleared.
///
/// 143-byte program → 164 packed bytes → 170 bytes on the wire including header/EOX.
public enum KorgPacking {

    public static func pack(_ data: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(data.count + data.count / 7 + 1)
        var i = 0
        while i < data.count {
            let end = min(i + 7, data.count)
            var msb: UInt8 = 0
            for j in i..<end where data[j] & 0x80 != 0 {
                msb |= UInt8(1 << (j - i))
            }
            out.append(msb)
            for j in i..<end {
                out.append(data[j] & 0x7F)
            }
            i = end
        }
        return out
    }

    public static func unpack(_ data: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(data.count)
        var i = 0
        while i < data.count {
            let msb = data[i]
            let end = min(i + 8, data.count)
            var j = i + 1
            while j < end {
                let bit = UInt8(1 << (j - i - 1))
                out.append(data[j] | ((msb & bit) != 0 ? 0x80 : 0))
                j += 1
            }
            i = end
        }
        return out
    }

    /// Number of packed bytes produced for `count` raw bytes.
    public static func packedCount(forRaw count: Int) -> Int {
        let full = count / 7
        let rem = count % 7
        return full * 8 + (rem == 0 ? 0 : rem + 1)
    }
}
