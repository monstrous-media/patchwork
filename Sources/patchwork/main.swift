import Foundation
import PatchworkCore
import PatchworkMIDI
#if canImport(Darwin)
import Darwin      // isatty
#elseif canImport(Glibc)
import Glibc
#endif

// patchwork — command-line companion for the Korg M1.
//
//   patchwork ports                                   list MIDI sources / destinations
//   patchwork dump [--json out.json] [--syx out.syx]  request the current program from the M1
//   patchwork send <patch.json|dump.syx> [--write N]  send a program to the edit buffer (and store to slot N)
//   patchwork write N                                 store the edit buffer to program slot N (0–99)
//   patchwork convert <in.json|in.syx> <out.json|out.syx>
//   patchwork validate <patch.json>
//   patchwork random [--seed N] [--from base.json] [-o out.json]
//   patchwork mutate <patch.json> [--amount 0.2] [--seed N] [-o out.json]
//   patchwork morph <a.json> <b.json> <t> [-o out.json]
//   patchwork describe <patch.json|dump.syx>          human summary of a patch
//   patchwork play [--notes "C4 E4 G4"] [--velocity 100] [--ms 800]   audition: play notes on the M1
//   patchwork play --phrase "Bass riff" [--transpose -12] [--repeat 2] (presets: see TestPhrase.presets)
//   patchwork bank --syx bank.syx [--json-dir bank/]  back up all 100 internal programs, one dump at a time (~20 s)
//   patchwork restore bank.syx [--verify]             write a whole bank back (slot = position in file), optionally read back and compare
//   patchwork restore patch.json --slot 57 [--verify] write one program to one slot
//
//   Commands that overwrite what the M1 stores — restore, write, send --write, global --send / --load —
//   describe what they will replace and ask for a `y` at the terminal. Pass --yes to skip the prompt;
//   without it, a non-interactive run (script, pipe, CI, agent) exits 2 and sends nothing.
//   patchwork params                                  print the parameter reference as Markdown
//   patchwork global [--syx f] [--kit N --json f | --load f] [--send f] [--yes]   drum kits (Global data): show, save, load, send
//   patchwork mode [program|combi|global|seq]         show the M1's mode, or switch it (dump/send switch to Program automatically)
//   patchwork raw "F0 42 30 19 12 F7"                 send arbitrary SysEx, print replies for 2 s
//   patchwork monitor [--raw]                         print incoming SysEx (learn parameter-change page/pos); --raw shows every byte
//
// Port selection: --in <idx|substring> --out <idx|substring> --channel 1..16, or environment
// variables M1_IN, M1_OUT, M1_CHANNEL. With a single interface present, no flags are needed.

struct Options {
    var positional: [String] = []
    var flags: [String: String] = [:]

    /// Switches that never take a value, so `--yes bank.syx` keeps bank.syx as the positional.
    static let switches: Set<String> = ["yes", "verify", "raw"]

    init(_ args: [String]) {
        var i = 0
        while i < args.count {
            let a = args[i]
            if a.hasPrefix("--") || (a.hasPrefix("-") && a.count == 2) {
                let key = a.hasPrefix("--") ? String(a.dropFirst(2)) : String(a.dropFirst())
                if Options.switches.contains(key) {
                    flags[key] = "true"; i += 1
                } else if i + 1 < args.count && !args[i + 1].hasPrefix("-") {
                    flags[key] = args[i + 1]; i += 2
                } else {
                    flags[key] = "true"; i += 1
                }
            } else {
                positional.append(a); i += 1
            }
        }
    }

    func flag(_ key: String, env: String? = nil) -> String? {
        if let v = flags[key] { return v }
        if let e = env, let v = ProcessInfo.processInfo.environment[e] { return v }
        return nil
    }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("error: " + message + "\n").utf8))
    exit(1)
}

func note(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

/// Gate for anything that overwrites what the M1 stores. Call BEFORE opening ports, so a refusal
/// sends nothing. `--yes` skips the prompt; at a terminal the user is told what will be replaced and
/// asked for a y; anywhere else (pipe, script, CI) the command exits 2 with a message that names --yes.
func requireConsent(_ opts: Options, toOverwrite description: String) {
    let decision = WriteConsent.decide(
        yes: opts.flag("yes") != nil,
        interactive: isatty(0) != 0,
        description: "This will " + description + " (Memory Protect must be OFF).",
        prompt: { q in FileHandle.standardError.write(Data(q.utf8)); return readLine() })
    if case .refused(let why) = decision {
        FileHandle.standardError.write(Data(("error: " + why + "\n").utf8))
        exit(2)
    }
}

func slotName(_ n: Int) -> String { String(format: "I%02d", n) }

func readProgram(path: String) throws -> M1Program {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    if path.lowercased().hasSuffix(".syx") || data.first == 0xF0 {
        let programs = M1SysEx.programs(inSyx: [UInt8](data))
        guard let first = programs.first else { fail("no M1 program dump found in \(path)") }
        if programs.count > 1 { note("note: \(path) holds \(programs.count) programs; using the first (“\(first.name)”)") }
        return first
    }
    return try M1Patch.decode(json: data).toProgram()
}

func writeProgram(_ program: M1Program, to path: String?, channel: UInt8) throws {
    let patch = M1Patch(program: program)
    guard let path = path else {
        FileHandle.standardOutput.write(try patch.jsonData())
        FileHandle.standardOutput.write(Data("\n".utf8))
        return
    }
    if path.lowercased().hasSuffix(".syx") {
        try Data(M1SysEx.programDump(program, channel: channel)).write(to: URL(fileURLWithPath: path))
    } else {
        try patch.jsonData().write(to: URL(fileURLWithPath: path))
    }
    note("wrote \(path)")
}

func channel(from opts: Options) -> UInt8 {
    let s = opts.flag("channel", env: "M1_CHANNEL") ?? "1"
    guard let n = Int(s), n >= 1, n <= 16 else { fail("--channel must be 1…16") }
    return UInt8(n - 1)
}

struct Ports {
    let engine: MIDIEngine
    let input: MIDIEngine.Endpoint
    let output: MIDIEngine.Endpoint
    let channel: UInt8
}

/// CoreMIDI can report zero endpoints on the very first query in a fresh process (before the
/// client connection to MIDIServer settles), so create the client first and retry briefly.
func enumerateEndpoints() throws -> (engine: MIDIEngine, sources: [MIDIEngine.Endpoint], destinations: [MIDIEngine.Endpoint]) {
    let engine = try MIDIEngine(name: "patchwork")
    var sources = MIDIEngine.sources()
    var destinations = MIDIEngine.destinations()
    var attempts = 0
    while destinations.isEmpty && attempts < 10 {
        Thread.sleep(forTimeInterval: 0.1)
        sources = MIDIEngine.sources()
        destinations = MIDIEngine.destinations()
        attempts += 1
    }
    return (engine, sources, destinations)
}

func openPorts(_ opts: Options, needInput: Bool = true) throws -> Ports {
    let (engine, sources, destinations) = try enumerateEndpoints()
    guard !destinations.isEmpty else { fail("no MIDI destinations — is the interface plugged in?") }

    func pick(_ query: String?, from list: [MIDIEngine.Endpoint], what: String) -> MIDIEngine.Endpoint {
        if let q = query {
            guard let e = MIDIEngine.match(q, in: list) else { fail("no \(what) matches “\(q)” (try `patchwork ports`)") }
            return e
        }
        if list.count == 1 { return list[0] }
        if let e = list.first(where: { $0.name.lowercased().contains("komplete") || $0.name.lowercased().contains("midi") }) { return e }
        fail("several \(what)s present; choose with --\(what == "source" ? "in" : "out") (see `patchwork ports`)")
    }

    let out = pick(opts.flag("out", env: "M1_OUT"), from: destinations, what: "destination")
    let inp = needInput ? pick(opts.flag("in", env: "M1_IN"), from: sources, what: "source") : MIDIEngine.Endpoint(id: 0, name: "-")
    if needInput { try engine.connect(source: inp.id) }
    return Ports(engine: engine, input: inp, output: out, channel: channel(from: opts))
}

func describe(_ p: M1Program) -> String {
    let patch = M1Patch(program: p)
    var lines: [String] = []
    lines.append("Program “\(p.name)” — \(patch.oscillatorMode), \(patch.assign)\(patch.hold ? ", hold" : "")")
    lines.append("  OSC1: \(patch.osc1.multisound) \(patch.osc1.octave)")
    if patch.oscillatorMode == "double" {
        lines.append("  OSC2: \(patch.osc2.multisound) \(patch.osc2.octave)  interval \(patch.osc2.interval)  detune \(patch.osc2.detune)  delay \(patch.osc2.delayStart)")
    }
    lines.append("  Pitch MG: \(patch.pitchMG.waveform) f\(patch.pitchMG.frequency) int\(patch.pitchMG.intensity) delay\(patch.pitchMG.delay)")
    lines.append("  VDF MG:   \(patch.vdfMG.waveform) f\(patch.vdfMG.frequency) int\(patch.vdfMG.intensity) delay\(patch.vdfMG.delay)")
    for (label, v) in [("OSC1", patch.voice1), ("OSC2", patch.voice2)] {
        if label == "OSC2" && patch.oscillatorMode != "double" { continue }
        let fe = v.vdf.eg
        let fEG = "EG A\(fe.attackTime)/\(fe.attackLevel) D\(fe.decayTime)/\(fe.breakPoint) S\(fe.slopeTime)/\(fe.sustainLevel) R\(fe.releaseTime)/\(fe.releaseLevel)"
        lines.append("  \(label) VDF: cutoff \(v.vdf.cutoff)  EG int \(v.vdf.egIntensity)  kbd \(v.vdf.cutoffKbdTrack)@\(v.vdf.kbdTrackCenter)  \(fEG)")
        let ae = v.vda.eg
        let aEG = "EG A\(ae.attackTime)/\(ae.attackLevel) D\(ae.decayTime)/\(ae.breakPoint) S\(ae.slopeTime)/\(ae.sustainLevel) R\(ae.releaseTime)"
        lines.append("  \(label) VDA: level \(v.vda.level)  vel \(v.vda.velocitySens)  \(aEG)")
    }
    let fx = patch.effects
    lines.append("  FX1: \(fx.effect1.type) (\(fx.effect1.balanceL)/\(fx.effect1.balanceR))   FX2: \(fx.effect2.type) (\(fx.effect2.balanceL)/\(fx.effect2.balanceR))   \(fx.serial ? "serial" : "parallel")")
    return lines.joined(separator: "\n")
}

func waitForAck(_ ports: Ports, after bytes: [UInt8], what: String) throws {
    let reply = try ports.engine.sendAndWait(bytes, to: ports.output.id, timeout: 3.0) { msg in
        guard let parsed = try? M1SysEx.parse(msg) else { return false }
        return parsed.message.isAck
    }
    if let r = reply, let parsed = try? M1SysEx.parse(r) {
        note("M1: \(parsed.message.summary)")
        switch parsed.message {
        case .writeError, .loadError, .formatError: exit(2)
        default: break
        }
    } else {
        note("no acknowledgement within 3 s (check: M1 in Program mode, Global → MIDI filter Exclusive = ENA, M1 MIDI OUT wired to the interface's MIDI IN for \(what))")
    }
}

func queryMode(_ ports: Ports) throws -> M1SysEx.Mode? {
    let reply = try ports.engine.sendAndWait(M1SysEx.modeRequest(channel: ports.channel), to: ports.output.id, timeout: 2.0) { msg in
        if case .modeData = (try? M1SysEx.parse(msg))?.message { return true }
        return false
    }
    guard let r = reply else { return nil }
    return M1SysEx.mode(from: try M1SysEx.parse(r).message)
}

/// Program dumps are only accepted/answered in Program mode; switch the M1 there if it isn't.
func ensureProgramMode(_ ports: Ports) throws {
    guard let current = try queryMode(ports) else {
        note("M1 did not answer a mode request — continuing anyway")
        return
    }
    if current == .program || current == .editProgram { return }
    note("M1 is in \(current.name) mode — switching to Program mode")
    try waitForAck(ports, after: M1SysEx.modeChange(.program, channel: ports.channel), what: "mode change")
    Thread.sleep(forTimeInterval: 0.3)
}

// MARK: - Commands

let argv = Array(CommandLine.arguments.dropFirst())
guard let command = argv.first else {
    print("usage: patchwork <ports|dump|bank|restore|send|write|convert|validate|random|mutate|morph|describe|play|params|global|mode|raw|monitor> …  (see source header)")
    print("       restore, write, send --write and global --send/--load overwrite the M1: they ask at a terminal, or need --yes")
    exit(0)
}
let opts = Options(Array(argv.dropFirst()))

do {
    switch command {

    case "ports":
        let (_, sources, destinations) = try enumerateEndpoints()
        print("Sources (M1 → Mac):")
        for (i, e) in sources.enumerated() { print("  [\(i)] \(e.name)") }
        print("Destinations (Mac → M1):")
        for (i, e) in destinations.enumerated() { print("  [\(i)] \(e.name)") }

    case "dump":
        let ports = try openPorts(opts)
        try ensureProgramMode(ports)
        note("requesting current program on channel \(ports.channel + 1) via \(ports.output.name) …")
        var lastReply: String?
        let reply = try ports.engine.sendAndWait(M1SysEx.programDumpRequest(channel: ports.channel), to: ports.output.id, timeout: 4.0) { msg in
            guard let p = try? M1SysEx.parse(msg) else { return false }
            if case .programDump = p.message { return true }
            lastReply = p.message.summary
            return false
        }
        guard let r = reply else {
            fail("no program dump received" + (lastReply.map { " — M1 replied: \($0)" } ?? " (Exclusive = ENA? MIDI OUT of the M1 connected?)"))
        }
        let parsedDump = try M1SysEx.parse(r)
        guard case .programDump(let program) = parsedDump.message else { fail("unexpected reply: \(parsedDump.message.summary)") }
        note("received “\(program.name)”")
        if let syx = opts.flag("syx") { try Data(r).write(to: URL(fileURLWithPath: syx)); note("wrote \(syx)") }
        try writeProgram(program, to: opts.flag("json"), channel: ports.channel)

    case "send":
        guard let path = opts.positional.first else { fail("send needs a .json or .syx file") }
        let program = try readProgram(path: path)
        var writeSlot: Int? = nil
        if let slot = opts.flag("write") {
            guard let n = Int(slot), n >= 0, n <= 99 else { fail("--write needs a slot 0…99") }
            writeSlot = n
            requireConsent(opts, toOverwrite: "send “\(program.name)” to the edit buffer and then store it in slot \(slotName(n)), replacing the program the M1 keeps there")
        }
        let ports = try openPorts(opts)
        try ensureProgramMode(ports)
        note("sending “\(program.name)” to \(ports.output.name) …")
        try waitForAck(ports, after: M1SysEx.programDump(program, channel: ports.channel), what: "acks")
        if let n = writeSlot {
            note("writing to program slot \(n) …")
            try waitForAck(ports, after: M1SysEx.programWriteRequest(slot: n, channel: ports.channel), what: "acks")
        }

    case "write":
        guard let s = opts.positional.first, let n = Int(s), n >= 0, n <= 99 else { fail("write needs a slot 0…99 [--yes]") }
        requireConsent(opts, toOverwrite: "store the M1's edit buffer in slot \(slotName(n)), replacing the program kept there")
        let ports = try openPorts(opts)
        try waitForAck(ports, after: M1SysEx.programWriteRequest(slot: n, channel: ports.channel), what: "acks")

    case "convert":
        guard opts.positional.count == 2 else { fail("convert <in> <out>") }
        let program = try readProgram(path: opts.positional[0])
        try writeProgram(program, to: opts.positional[1], channel: channel(from: opts))

    case "validate":
        guard let path = opts.positional.first else { fail("validate <patch.json>") }
        let program = try readProgram(path: path)
        print("ok: “\(program.name)” → \(M1SysEx.programDump(program).count)-byte dump")

    case "describe":
        guard let path = opts.positional.first else { fail("describe <file>") }
        print(describe(try readProgram(path: path)))

    case "random":
        let seed = UInt64(opts.flag("seed") ?? "") ?? UInt64(Date().timeIntervalSince1970 * 1000)
        let base = try opts.flag("from").map { try readProgram(path: $0) } ?? M1Program()
        let program = KorgM1.randomise(base: base, seed: seed)
        note("seed \(seed)")
        try writeProgram(program, to: opts.flag("o"), channel: channel(from: opts))

    case "mutate":
        guard let path = opts.positional.first else { fail("mutate <patch> [--amount 0.2] [--seed N]") }
        let seed = UInt64(opts.flag("seed") ?? "") ?? UInt64(Date().timeIntervalSince1970 * 1000)
        let amount = Double(opts.flag("amount") ?? "0.2") ?? 0.2
        let program = KorgM1.mutate(try readProgram(path: path), amount: amount, seed: seed)
        note("seed \(seed), amount \(amount)")
        try writeProgram(program, to: opts.flag("o"), channel: channel(from: opts))

    case "morph":
        guard opts.positional.count == 3, let t = Double(opts.positional[2]) else { fail("morph <a> <b> <t 0…1>") }
        let program = KorgM1.morph(try readProgram(path: opts.positional[0]), try readProgram(path: opts.positional[1]), t: t)
        try writeProgram(program, to: opts.flag("o"), channel: channel(from: opts))

    case "play":
        // patchwork play [--notes "C4 E4 G4"] [--velocity 100] [--ms 800] | [--phrase "Bass riff"] [--transpose 0] [--repeat 1]
        let ports = try openPorts(opts, needInput: false)
        let transpose = Int(opts.flag("transpose") ?? "0") ?? 0
        let repeats = max(1, Int(opts.flag("repeat") ?? "1") ?? 1)
        let phrase: TestPhrase
        if let name = opts.flag("phrase") {
            guard let p = TestPhrase.presets.first(where: { $0.name.lowercased().contains(name.lowercased()) }) else {
                fail("no preset phrase matches “\(name)”; presets: " + TestPhrase.presets.map { $0.name }.joined(separator: ", "))
            }
            phrase = p
        } else {
            guard let notes = TestPhrase.parseNotes(opts.flag("notes") ?? "C4"), !notes.isEmpty else {
                fail("--notes needs note names like \"C4 E4 G4\" or numbers")
            }
            let vel = Int(opts.flag("velocity") ?? "100") ?? 100
            let ms = Int(opts.flag("ms") ?? "800") ?? 800
            phrase = TestPhrase(name: "ad hoc", steps: [PhraseStep(notes: notes, velocity: vel, durationMs: ms, gapMs: 0)])
        }
        note("playing “\(phrase.name)” ×\(repeats) on channel \(ports.channel + 1)")
        for _ in 0..<repeats {
            for step in phrase.steps {
                let notes = step.notes.map { UInt8(max(0, min(127, $0 + transpose))) }
                for n in notes { try ports.engine.noteOn(n, velocity: UInt8(max(1, min(127, step.velocity))), channel: ports.channel, to: ports.output.id) }
                Thread.sleep(forTimeInterval: Double(step.durationMs) / 1000)
                for n in notes { try ports.engine.noteOff(n, channel: ports.channel, to: ports.output.id) }
                Thread.sleep(forTimeInterval: Double(step.gapMs) / 1000)
            }
        }
        try ports.engine.allNotesOff(channel: ports.channel, to: ports.output.id)

    case "bank":
        // patchwork bank --syx bank.syx [--json-dir bank/]
        // Fetch all 100 internal programs one at a time (program change + single dump request),
        // which works on interfaces that drop the 16 KB all-program dump.
        let ports = try openPorts(opts)
        try ensureProgramMode(ports)
        var programs: [M1Program] = []
        for n in 0..<100 {
            try ports.engine.programChange(UInt8(n), channel: ports.channel, to: ports.output.id)
            Thread.sleep(forTimeInterval: 0.12)
            let reply = try ports.engine.sendAndWait(M1SysEx.programDumpRequest(channel: ports.channel), to: ports.output.id, timeout: 2.5) { msg in
                if case .programDump = (try? M1SysEx.parse(msg))?.message { return true }
                return false
            }
            guard let r = reply else { fail("no dump for program \(n) (got \(programs.count) so far)") }
            let parsedBank = try M1SysEx.parse(r)
            guard case .programDump(let p) = parsedBank.message else { fail("unexpected reply for program \(n): \(parsedBank.message.summary)") }
            programs.append(p)
            note(String(format: "I%02d  %@", n, p.name))
        }
        if programs.count >= 2 && Set(programs.map { $0.name }).count == 1 {
            note("warning: every program has the same name — the M1 may be ignoring Program Change (Global 5+1: Combi/Prog Change = ENA)")
        }
        if let syx = opts.flag("syx") {
            var bytes: [UInt8] = []
            for p in programs { bytes += M1SysEx.programDump(p, channel: ports.channel) }
            try Data(bytes).write(to: URL(fileURLWithPath: syx))
            note("wrote \(programs.count) programs to \(syx)")
        }
        if let dir = opts.flag("json-dir") {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            for (n, p) in programs.enumerated() {
                let safe = p.name.map { $0.isLetter || $0.isNumber ? $0 : "_" }
                let path = (dir as NSString).appendingPathComponent(String(format: "I%02d-%@.json", n, String(safe)))
                try M1Patch(program: p).jsonData().write(to: URL(fileURLWithPath: path))
            }
            note("wrote \(programs.count) JSON patches to \(dir)/")
        }
        if opts.flag("syx") == nil && opts.flag("json-dir") == nil {
            note("(nothing written — pass --syx bank.syx and/or --json-dir bank/)")
        }

    case "restore":
        // patchwork restore bank.syx [--verify]            write every program in the file to its slot (0, 1, 2 …)
        // patchwork restore patch.json --slot 57 [--verify] write one program to one slot
        guard let path = opts.positional.first else { fail("restore <bank.syx | patch> [--slot N] [--verify] [--yes]") }
        let items: [(slot: Int, program: M1Program)]
        if let s = opts.flag("slot") {
            guard let n = Int(s), n >= 0, n <= 99 else { fail("--slot must be 0…99") }
            items = [(slot: n, program: try readProgram(path: path))]
        } else {
            let programs = M1SysEx.programs(inSyx: [UInt8](try Data(contentsOf: URL(fileURLWithPath: path))))
            guard !programs.isEmpty else { fail("no program dumps found in \(path) (for a single JSON patch use --slot N)") }
            items = programs.prefix(100).enumerated().map { (slot: $0.offset, program: $0.element) }
        }
        let slots = WriteConsent.slotRanges(items.map(\.slot), label: slotName)
        let names = items.prefix(3).map { "“\($0.program.name)”" }.joined(separator: ", ") + (items.count > 3 ? ", …" : "")
        requireConsent(opts, toOverwrite: "overwrite M1 slot\(items.count == 1 ? "" : "s") \(slots) (\(items.count) program\(items.count == 1 ? "" : "s"): \(names))")
        let ports = try openPorts(opts)
        try ensureProgramMode(ports)
        note("writing \(items.count) program\(items.count == 1 ? "" : "s") to the M1 (Memory Protect must be OFF) …")
        for item in items {
            let a1 = try ports.engine.sendAndWait(M1SysEx.programDump(item.program, channel: ports.channel), to: ports.output.id, timeout: 3.0) { msg in
                (try? M1SysEx.parse(msg))?.message.isAck ?? false
            }
            guard let ack1 = a1 else { fail("no acknowledgement of the program dump for I\(String(format: "%02d", item.slot))") }
            let m1 = try M1SysEx.parse(ack1).message
            guard case .loadCompleted = m1 else { fail("M1 replied “\(m1.summary)” to the dump for I\(String(format: "%02d", item.slot))") }
            let a2 = try ports.engine.sendAndWait(M1SysEx.programWriteRequest(slot: item.slot, channel: ports.channel), to: ports.output.id, timeout: 3.0) { msg in
                (try? M1SysEx.parse(msg))?.message.isAck ?? false
            }
            guard let ack2 = a2 else { fail("no acknowledgement of the write to I\(String(format: "%02d", item.slot))") }
            let m2 = try M1SysEx.parse(ack2).message
            guard case .writeCompleted = m2 else { fail("write to I\(String(format: "%02d", item.slot)) refused: “\(m2.summary)” — Memory Protect on? (GLOBAL → 6 → Program = OFF)") }
            note(String(format: "I%02d  %@  written", item.slot, item.program.name))
        }
        if opts.flag("verify") != nil {
            note("verifying …")
            var bad: [Int] = []
            for item in items {
                try ports.engine.programChange(UInt8(item.slot), channel: ports.channel, to: ports.output.id)
                Thread.sleep(forTimeInterval: 0.12)
                let reply = try ports.engine.sendAndWait(M1SysEx.programDumpRequest(channel: ports.channel), to: ports.output.id, timeout: 2.5) { msg in
                    if case .programDump = (try? M1SysEx.parse(msg))?.message { return true }
                    return false
                }
                guard let r = reply else { fail("verify: no dump for I\(String(format: "%02d", item.slot))") }
                let back = try M1SysEx.parse(r).message
                guard case .programDump(let p) = back else { fail("verify: unexpected reply \(back.summary)") }
                if p != item.program { bad.append(item.slot) }
            }
            if bad.isEmpty { note("verified: all \(items.count) slot\(items.count == 1 ? "" : "s") read back identical ✓") }
            else { fail("verify: \(bad.count) slot(s) differ: " + bad.map { String(format: "I%02d", $0) }.joined(separator: " ")) }
        }

    case "params":
        // Markdown parameter reference (the same text as the app's tooltips and guide) for the docs site.
        print(ParameterHelp.markdownReference())

    case "global":
        // patchwork global [--syx global.syx]            request Global data (settings + 4 drum kits), print the kits
        // patchwork global --send global.syx             send a saved Global dump back
        // patchwork global --kit 2 --json kit2.json       save one kit as JSON
        // patchwork global --kit 2 --load kit2.json       replace one kit from JSON and send the Global data back
        if opts.flag("send") != nil {
            requireConsent(opts, toOverwrite: "replace the M1's Global data (settings and all four drum kits) with \(opts.flag("send")!); the M1 stores it immediately")
        } else if opts.flag("load") != nil {
            requireConsent(opts, toOverwrite: "replace drum kit \(opts.flag("kit") ?? "?") on the M1 from \(opts.flag("load")!) and store the Global data immediately")
        }
        let ports = try openPorts(opts)
        if let path = opts.flag("send") {
            let msgs = M1SysEx.splitMessages([UInt8](try Data(contentsOf: URL(fileURLWithPath: path))))
            guard let m = msgs.first(where: { (try? M1SysEx.parse($0))?.message.summary.hasPrefix("Global") ?? false }) else { fail("no Global data dump in \(path)") }
            try waitForAck(ports, after: m, what: "acks")
            break
        }
        let reply = try ports.engine.sendAndWait(M1SysEx.globalDumpRequest(channel: ports.channel), to: ports.output.id, timeout: 5.0) { msg in
            if case .globalDump = (try? M1SysEx.parse(msg))?.message { return true }
            return false
        }
        guard let r = reply else { fail("no Global data received (Exclusive = ENA? interface dropping ~1 KB messages?)") }
        let parsedGlobal = try M1SysEx.parse(r)
        guard case .globalDump(var g) = parsedGlobal.message else { fail("unexpected reply: \(parsedGlobal.message.summary)") }
        note("received Global data: \(g.bytes.count) bytes")
        if let syx = opts.flag("syx") { try Data(r).write(to: URL(fileURLWithPath: syx)); note("wrote \(syx)") }
        if let k = opts.flag("kit") {
            guard let kit = Int(k), (1...4).contains(kit) else { fail("--kit must be 1…4") }
            if let json = opts.flag("json") {
                let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
                try enc.encode(DrumKitPatch(kit: kit - 1, entries: g.kit(kit - 1))).write(to: URL(fileURLWithPath: json))
                note("wrote kit \(kit) to \(json)")
            }
            if let load = opts.flag("load") {
                let patch = try JSONDecoder().decode(DrumKitPatch.self, from: Data(contentsOf: URL(fileURLWithPath: load)))
                g.setKit(kit - 1, try patch.toEntries())
                note("sending Global data with kit \(kit) replaced from \(load) …")
                try waitForAck(ports, after: M1SysEx.globalDump(g, channel: ports.channel), what: "acks")
            }
        }
        if opts.flag("json") == nil && opts.flag("load") == nil {
            print("Master tune \(g.signed(M1GlobalData.G.masterTune))  transpose \(g.signed(M1GlobalData.G.keyTranspose))  scale \(M1GlobalData.scaleTypes[min(4, Int(g.bytes[M1GlobalData.G.scaleType]))])")
            for k in 0..<4 {
                let lines = g.kitSummary(k)
                print("\nDrum Kit \(k + 1): \(lines.count) instruments")
                for l in lines { print("  " + l) }
            }
        }

    case "mode":
        // patchwork mode            → ask the M1 which mode it is in (0x12 → 0x42)
        // patchwork mode program    → switch it (0x4E); also combi / global / seq
        let ports = try openPorts(opts)
        if let want = opts.positional.first {
            guard let m = M1SysEx.Mode.named(want) else { fail("mode must be program, combi, global or seq") }
            try waitForAck(ports, after: M1SysEx.modeChange(m, channel: ports.channel), what: "mode change")
        }
        if let m = try queryMode(ports) { print("M1 is in \(m.name) mode") } else { fail("no reply to mode request") }

    case "raw":
        // Send arbitrary SysEx and print every M1 reply for 2 s:  patchwork raw "F0 42 30 19 12 F7"
        guard let hexText = opts.positional.first, var bytes = bytesFromHex(hexText), !bytes.isEmpty else {
            fail("raw needs a hex string like \"F0 42 30 19 12 F7\"")
        }
        let ports = try openPorts(opts)
        if bytes.count > 2 && bytes[0] == 0xF0 && bytes[1] == M1SysEx.korgID && (bytes[2] & 0xF0) == 0x30 {
            bytes[2] = 0x30 | ports.channel     // keep the channel consistent with --channel
        }
        ports.engine.onSysEx = { msg in
            if let p = try? M1SysEx.parse(msg) { print("← ch\(p.channel + 1) \(p.message.summary)   [\(hex(Array(msg.prefix(24))))\(msg.count > 24 ? " …" : "")]") }
            else { print("← \(hex(Array(msg.prefix(24))))\(msg.count > 24 ? " …" : "")") }
            fflush(stdout)
        }
        print("→ \(hex(bytes))")
        try ports.engine.send(bytes, to: ports.output.id)
        Thread.sleep(forTimeInterval: 2.0)

    case "monitor":
        let ports = try openPorts(opts)
        let raw = opts.flag("raw") != nil
        note("listening on \(ports.input.name)\(raw ? " (raw: every incoming byte)" : "") — play a key or edit on the M1's panel; Ctrl-C to stop")
        if raw {
            ports.engine.onRawBytes = { bytes in
                let stamp = ISO8601DateFormatter().string(from: Date())
                var label = ""
                if let s = bytes.first, s < 0xF0 {
                    let kinds = [0x8: "note off", 0x9: "note on", 0xA: "poly AT", 0xB: "control change", 0xC: "program change", 0xD: "channel AT", 0xE: "pitch bend"]
                    label = "  \(kinds[Int(s >> 4)] ?? "?") ch\((s & 0x0F) + 1)"
                } else if bytes.first == 0xF0 { label = "  sysex" }
                print("\(stamp)  \(hex(Array(bytes.prefix(24))))\(bytes.count > 24 ? " …(\(bytes.count) bytes)" : "")\(label)")
                fflush(stdout)
            }
        }
        ports.engine.onSysEx = { msg in
            let stamp = ISO8601DateFormatter().string(from: Date())
            if let parsed = try? M1SysEx.parse(msg) {
                print("\(stamp)  ch\(parsed.channel + 1)  \(parsed.message.summary)   \(msg.count <= 16 ? hex(msg) : hex(Array(msg.prefix(12))) + " …")")
            } else {
                print("\(stamp)  \(msg.count) bytes  \(hex(Array(msg.prefix(16))))\(msg.count > 16 ? " …" : "")")
            }
            fflush(stdout)
        }
        RunLoop.main.run()

    default:
        fail("unknown command “\(command)”")
    }
} catch {
    fail("\(error)")
}
