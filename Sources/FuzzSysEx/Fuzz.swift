// libFuzzer harness for the SysEx parser and the Korg 7-in-8 unpacker — the two places untrusted
// bytes (a .syx file, or whatever arrives on MIDI In) are turned into structure.
//
// Instrumented build and run (CI does this on Linux; works on macOS with an Xcode toolchain too):
//
//   swift build -c release -Xswiftc -sanitize=fuzzer,address -Xswiftc -parse-as-library -Xswiftc -DFUZZING --product FuzzSysEx
//   mkdir -p fuzz/corpus && cp Tests/PatchworkCoreTests/Vectors/* fuzz/corpus/
//   .build/release/FuzzSysEx -max_total_time=120 -max_len=20000 fuzz/corpus
//
// SwiftPM gives every executable module its own entry symbol (`FuzzSysEx_main`) and aliases `main`
// to it at link time, so the target must always define an entry point. With -DFUZZING that entry
// point hands straight to libFuzzer through LLVMFuzzerRunDriver (the supported way to own `main` in
// a fuzz binary); without it, an ordinary `swift build` links a placeholder that prints the recipe.

import Foundation
import PatchworkCore

@_cdecl("LLVMFuzzerTestOneInput")
public func fuzzOne(_ data: UnsafePointer<UInt8>, _ size: Int) -> CInt {
    let bytes = Array(UnsafeBufferPointer(start: data, count: size))
    _ = try? M1SysEx.parse(bytes)
    _ = KorgPacking.unpack(bytes)
    return 0
}

#if FUZZING
/// libFuzzer's driver: parses the usual -max_total_time etc. from argv and loops over `fuzzOne`.
@_silgen_name("LLVMFuzzerRunDriver")
func LLVMFuzzerRunDriver(_ argc: UnsafeMutablePointer<CInt>,
                         _ argv: UnsafeMutablePointer<UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?>,
                         _ callback: @convention(c) (UnsafePointer<UInt8>, Int) -> CInt) -> CInt

@main
struct FuzzSysExMain {
    static func main() {
        var argc = CommandLine.argc
        var argv = CommandLine.unsafeArgv
        exit(LLVMFuzzerRunDriver(&argc, &argv, { data, size in fuzzOne(data, size) }))
    }
}
#else
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
