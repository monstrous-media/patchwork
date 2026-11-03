// libFuzzer harness for the SysEx parser and the Korg 7-in-8 unpacker — the two places untrusted
// bytes (a .syx file, or whatever arrives on MIDI In) are turned into structure.
//
// Instrumented build and run (CI does this on Linux; works on macOS with an Xcode toolchain too):
//
//   swift build -c release -Xswiftc -sanitize=fuzzer,address -Xswiftc -parse-as-library -Xswiftc -DFUZZING --product FuzzSysEx
//   mkdir -p fuzz/corpus && cp Tests/PatchworkCoreTests/Vectors/* fuzz/corpus/
//   .build/release/FuzzSysEx -max_total_time=120 -max_len=20000 fuzz/corpus
//
// -DFUZZING drops the placeholder `main` below so libFuzzer can supply its own; without the define
// this target still builds and links in an ordinary `swift build`, and just prints the recipe.

import PatchworkCore

@_cdecl("LLVMFuzzerTestOneInput")
public func fuzzOne(_ data: UnsafePointer<UInt8>, _ size: Int) -> CInt {
    let bytes = Array(UnsafeBufferPointer(start: data, count: size))
    _ = try? M1SysEx.parse(bytes)
    _ = KorgPacking.unpack(bytes)
    return 0
}

#if !FUZZING
@main
struct FuzzSysExPlaceholder {
    static func main() {
        print("""
        FuzzSysEx is a libFuzzer target. Build it instrumented:
          swift build -c release -Xswiftc -sanitize=fuzzer,address -Xswiftc -parse-as-library -Xswiftc -DFUZZING --product FuzzSysEx
        then run .build/release/FuzzSysEx <corpus-dir> (seed it from Tests/PatchworkCoreTests/Vectors).
        """)
    }
}
#endif
