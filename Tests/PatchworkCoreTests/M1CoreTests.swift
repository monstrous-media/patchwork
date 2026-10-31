import XCTest
@testable import PatchworkCore

final class KorgPackingTests: XCTestCase {

    struct Vectors: Decodable {
        struct Packing: Decodable { let raw: String; let packed: String }
        struct Dump: Decodable { let channel: Int; let program: String; let sysex: String }
        let packing: [Packing]
        let programDumps: [Dump]
        let requests: [String: String]
    }

    static let vectors: Vectors = {
        let url = Bundle.module.url(forResource: "m1-vectors", withExtension: "json", subdirectory: "Vectors")!
        return try! JSONDecoder().decode(Vectors.self, from: Data(contentsOf: url))
    }()

    func testPackingMatchesReferenceVectors() {
        for v in Self.vectors.packing {
            let raw = bytesFromHex(v.raw)!
            let packed = bytesFromHex(v.packed)!
            XCTAssertEqual(KorgPacking.pack(raw), packed, "pack \(v.raw)")
            XCTAssertEqual(KorgPacking.unpack(packed), raw, "unpack \(v.packed)")
            XCTAssertEqual(KorgPacking.packedCount(forRaw: raw.count), packed.count)
        }
    }

    func testRoundTripRandomData() {
        var rng = SeededRandom(seed: 42)
        for _ in 0..<200 {
            let n = Int.random(in: 0...300, using: &rng)
            let raw = (0..<n).map { _ in UInt8.random(in: 0...255, using: &rng) }
            XCTAssertEqual(KorgPacking.unpack(KorgPacking.pack(raw)), raw)
            XCTAssertTrue(KorgPacking.pack(raw).allSatisfy { $0 < 0x80 })
        }
    }

    func testProgramDumpIs170Bytes() {
        let dump = M1SysEx.programDump(M1Program(), channel: 0)
        XCTAssertEqual(dump.count, 170)
        XCTAssertEqual(Array(dump.prefix(5)), [0xF0, 0x42, 0x30, 0x19, 0x40])
        XCTAssertEqual(dump.last, 0xF7)
    }

    func testAllProgramDumpIs16350Bytes() {
        let programs = Array(repeating: M1Program(), count: 100)
        let dump = M1SysEx.allProgramDump(programs, channel: 3)
        XCTAssertEqual(dump.count, 16350)
        XCTAssertEqual(Array(dump.prefix(6)), [0xF0, 0x42, 0x33, 0x19, 0x4C, 0x00])
        let parsed = try! M1SysEx.parse(dump)
        XCTAssertEqual(parsed.channel, 3)
        if case .allProgramDump(let ps) = parsed.message {
            XCTAssertEqual(ps.count, 100)
            XCTAssertEqual(ps[99], M1Program())
        } else {
            XCTFail("expected all-program dump")
        }
    }

    func testProgramDumpVectors() throws {
        for v in Self.vectors.programDumps {
            let program = try M1Program(bytes: bytesFromHex(v.program)!)
            let expected = bytesFromHex(v.sysex)!
            XCTAssertEqual(M1SysEx.programDump(program, channel: UInt8(v.channel)), expected)
            let parsed = try M1SysEx.parse(expected)
            XCTAssertEqual(parsed.channel, UInt8(v.channel))
            XCTAssertEqual(parsed.message, .programDump(program))
        }
    }

    func testRequestVectors() {
        let r = Self.vectors.requests
        XCTAssertEqual(hex(M1SysEx.programDumpRequest(channel: 0), separator: "").lowercased(), r["programDumpRequest_ch1"])
        XCTAssertEqual(hex(M1SysEx.programWriteRequest(slot: 12, channel: 0), separator: "").lowercased(), r["programWriteRequest_slot12_ch1"])
        XCTAssertEqual(hex(M1SysEx.parameterChange(page: 2, position: 5, value: -12, channel: 0), separator: "").lowercased(),
                       r["parameterChange_pg2_pos5_val_minus12_ch1"])
        XCTAssertEqual(hex(M1SysEx.parameterChange(page: 0, position: 71, value: 99, channel: 15), separator: "").lowercased(),
                       r["parameterChange_pg0_pos71_val99_ch16"])
    }

    func testParseAcks() throws {
        XCTAssertEqual(try M1SysEx.parse([0xF0, 0x42, 0x30, 0x19, 0x23, 0xF7]).message, .loadCompleted)
        XCTAssertEqual(try M1SysEx.parse([0xF0, 0x42, 0x30, 0x19, 0x21, 0xF7]).message, .writeCompleted)
        XCTAssertEqual(try M1SysEx.parse([0xF0, 0x42, 0x35, 0x19, 0x22, 0xF7]).channel, 5)
        XCTAssertThrowsError(try M1SysEx.parse([0xF0, 0x43, 0x30, 0x19, 0x23, 0xF7]))   // Yamaha, not Korg
        XCTAssertThrowsError(try M1SysEx.parse([0xF0, 0x42, 0x30, 0x19, 0x40, 0x00]))   // no EOX
    }

    func testModeMessages() throws {
        XCTAssertEqual(M1SysEx.modeRequest(channel: 0), [0xF0, 0x42, 0x30, 0x19, 0x12, 0xF7])
        XCTAssertEqual(M1SysEx.modeChange(.program, channel: 0), [0xF0, 0x42, 0x30, 0x19, 0x4E, 0x02, 0x00, 0xF7])
        // Observed reply from a real M1 sitting in Combination mode:
        let parsed = try M1SysEx.parse([0xF0, 0x42, 0x30, 0x19, 0x42, 0x00, 0x00, 0x00, 0x00, 0xF7])
        XCTAssertEqual(M1SysEx.mode(from: parsed.message), .combination)
        XCTAssertEqual(M1SysEx.Mode.named("prog"), .program)
        XCTAssertNil(M1SysEx.Mode(rawValue: 5))
    }

    func testSplitSyxStream() {
        let a = M1SysEx.programDump(M1Program(), channel: 0)
        var b = M1Program(); b.name = "SECOND"
        let stream = a + [0xF8] + M1SysEx.programDump(b, channel: 0)
        let programs = M1SysEx.programs(inSyx: stream)
        XCTAssertEqual(programs.count, 2)
        XCTAssertEqual(programs[1].name, "SECOND")
    }
}

final class ProgramModelTests: XCTestCase {

    func testNameRoundTrip() {
        var p = M1Program()
        p.name = "Glass Pad"
        XCTAssertEqual(p.name, "Glass Pad")
        XCTAssertEqual(Array(p.bytes[0..<10]), Array("Glass Pad ".utf8))
        p.name = "A very long program name"
        XCTAssertEqual(p.name, "A very lon")
    }

    func testProgramCodableAsHex() throws {
        var p = M1Program()
        p.name = "CODEC"
        p.setSigned(P.osc2Detune, -7)
        let data = try JSONEncoder().encode([p, M1Program()])
        XCTAssertTrue(String(data: data, encoding: .utf8)!.hasPrefix("[\"434F444543"))   // "CODEC" in hex
        let back = try JSONDecoder().decode([M1Program].self, from: data)
        XCTAssertEqual(back, [p, M1Program()])
        let optional = try JSONDecoder().decode([M1Program?].self, from: Data("[null, \"\(hex(p.bytes, separator: ""))\"]".utf8))
        XCTAssertNil(optional[0]); XCTAssertEqual(optional[1], p)
        XCTAssertThrowsError(try JSONDecoder().decode(M1Program.self, from: Data("\"F0F1\"".utf8)))
    }

    func testSignedAccessors() {
        var p = M1Program()
        p.setSigned(P.osc2Detune, -50)
        XCTAssertEqual(p[P.osc2Detune], 0xCE)
        XCTAssertEqual(p.signed(P.osc2Detune), -50)
        p.setSigned(P.osc2Interval, -12)
        XCTAssertEqual(p[P.osc2Interval], 0xF4)
        p.setSigned(P.osc1Octave, -1)
        XCTAssertEqual(p[P.osc1Octave], 0xFF)
    }

    func testBitFields() {
        var p = M1Program()
        p.setField(P.pitchMGFlags, shift: 0, width: 2, 3)
        p.setBit(P.pitchMGFlags, 7, true)
        XCTAssertEqual(p.field(P.pitchMGFlags, shift: 0, width: 2), 3)
        XCTAssertTrue(p.bit(P.pitchMGFlags, 7))
        XCTAssertTrue(p.bit(P.pitchMGFlags, 5))   // init program has OSC1 enabled
    }

    func testParameterMapCoversEveryByteExactlyOnce() {
        var covered = Set<Int>()
        for def in ParameterMap.all {
            if case .ascii = def.kind {
                for i in 0..<10 { XCTAssertTrue(covered.insert(i).inserted) }
            } else {
                XCTAssertTrue(covered.insert(def.index).inserted, "duplicate index \(def.index)")
            }
        }
        XCTAssertEqual(covered.count, M1Program.byteCount)
        XCTAssertEqual(covered.max(), M1Program.byteCount - 1)
    }

    func testNoteNames() {
        XCTAssertEqual(NoteName.string(for: 60), "C4")
        XCTAssertEqual(NoteName.string(for: 0), "C-1")
        XCTAssertEqual(NoteName.string(for: 127), "G9")
        XCTAssertEqual(NoteName.value(for: "C4"), 60)
        XCTAssertEqual(NoteName.value(for: "F#2"), 42)
        XCTAssertEqual(NoteName.value(for: "Db4"), 61)
        XCTAssertEqual(NoteName.value(for: "C-1"), 0)
        XCTAssertNil(NoteName.value(for: "H3"))
    }

    func testLookups() {
        XCTAssertEqual(Multisounds.value(for: "Strings"), 31)
        XCTAssertEqual(Multisounds.value(for: "dwgs voice"), 88)
        XCTAssertEqual(Multisounds.value(for: "card:3"), 103)
        XCTAssertEqual(Multisounds.name(for: 103), "card:3")
        XCTAssertEqual(EffectTypes.value(for: "Hall"), 0)
        XCTAssertEqual(EffectTypes.value(for: "thru"), 0x21)
        XCTAssertEqual(EffectTypes.value(for: "33"), 32)
        XCTAssertEqual(EffectTypes.name(for: 0x21), "Thru")
        XCTAssertEqual(Multisounds.names.count, 100)
        XCTAssertEqual(EffectTypes.names.count, 33)
    }
}

final class PatchJSONTests: XCTestCase {

    func testInitProgramRoundTripsThroughPatch() throws {
        let p = M1Program()
        let patch = M1Patch(program: p)
        let back = try patch.toProgram()
        XCTAssertEqual(back, p)
    }

    func testRandomProgramsRoundTripThroughJSON() throws {
        for seed in 1...50 {
            var p = KorgM1.randomise(base: M1Program(), seed: UInt64(seed))
            ParameterMap.sanitise(&p)
            let patch = M1Patch(program: p)
            let data = try patch.jsonData()
            let decoded = try M1Patch.decode(json: data)
            XCTAssertEqual(decoded, patch)
            XCTAssertEqual(try decoded.toProgram(), p, "seed \(seed)")
        }
    }

    func testPatchFieldsReadBack() throws {
        var p = M1Program()
        p.name = "Glass Pad"
        p.setUnsigned(P.oscMode, 1)
        p.setUnsigned(P.osc1Multisound, 31)          // Strings
        p.setSigned(P.osc2Octave, -1)
        p.setSigned(P.osc2Interval, 7)
        p.setUnsigned(P.effect1Type, 11)             // Stereo Chorus I
        p.setUnsigned(P.output3Pan, 51)              // 50/50
        p.setUnsigned(P.voice1Base + V.vdfKbdTrackCenter, 48)
        let patch = M1Patch(program: p)
        XCTAssertEqual(patch.name, "Glass Pad")
        XCTAssertEqual(patch.oscillatorMode, "double")
        XCTAssertEqual(patch.osc1.multisound, "Strings")
        XCTAssertEqual(patch.osc2.octave, "16'")
        XCTAssertEqual(patch.osc2.interval, 7)
        XCTAssertEqual(patch.effects.effect1.type, "Stereo Chorus I")
        XCTAssertEqual(patch.effects.output3Pan, 50)
        XCTAssertNil(patch.effects.output4Pan)
        XCTAssertEqual(patch.voice1.vdf.kbdTrackCenter, "C3")
        XCTAssertEqual(try patch.toProgram(), p)
    }

    func testDrumKitNaming() throws {
        var p = M1Program()
        p.setUnsigned(P.oscMode, 2)
        p.setUnsigned(P.osc1Multisound, 1)
        let patch = M1Patch(program: p)
        XCTAssertEqual(patch.oscillatorMode, "drums")
        XCTAssertEqual(patch.osc1.multisound, "Drum Kit 2")
        XCTAssertEqual(try patch.toProgram(), p)
        var edited = patch
        edited.osc1.multisound = "kit:4"
        XCTAssertEqual(try edited.toProgram()[P.osc1Multisound], 3)
        edited.osc1.multisound = "Drum Kit 5"
        XCTAssertThrowsError(try edited.toProgram())
    }

    func testEveryParameterHasHelpAndTheReferenceCoversAllSections() {
        for def in ParameterMap.all {
            XCTAssertFalse(ParameterHelp.text(for: def).hasPrefix("M1 program parameter"), "no help for \(def.name) in \(def.section.rawValue)")
        }
        let md = ParameterHelp.markdownReference()
        XCTAssertTrue(md.contains("### OSC1 · VDF"))
        XCTAssertTrue(md.contains("| Cutoff |"))
    }

    func testValidationErrorsNameTheField() throws {
        var patch = M1Patch(program: M1Program())
        patch.voice1.vdf.cutoff = 150
        XCTAssertThrowsError(try patch.toProgram()) { error in
            XCTAssertEqual(error as? M1Error, .invalidValue(field: "voice1.vdf.cutoff", reason: "150 is outside 0…99"))
        }
        patch.voice1.vdf.cutoff = 50
        patch.osc1.multisound = "Theremin"
        XCTAssertThrowsError(try patch.toProgram())
    }

    func testMinimalHandWrittenJSONDecodes() throws {
        let json = """
        {
          "format": "korg-m1-program/1",
          "name": "Test",
          "oscillatorMode": "single", "assign": "poly", "hold": false,
          "osc1": {"multisound": "E.Piano1", "octave": "8'"},
          "osc2": {"multisound": "Bell", "octave": "4'", "interval": 0, "detune": 0, "delayStart": 0},
          "pitchMG": {"waveform": "triangle", "frequency": 40, "delay": 0, "intensity": 0, "osc1": true, "osc2": true, "keySync": false},
          "vdfMG": {"waveform": "triangle", "frequency": 40, "delay": 0, "intensity": 0, "osc1": true, "osc2": true, "keySync": false},
          "aftertouch": {"pitch": 0, "pitchMG": 0, "vdfCutoff": 0, "vdfMG": 0, "vdaAmplitude": 0},
          "joystick": {"pitchBend": 2, "vdfSweep": 0, "pitchMGIntensity": 0, "pitchMGFrequency": 0, "vdfMGIntensity": 0, "vdfMGFrequency": 0},
          "effects": {
            "effect1": {"type": "Hall", "balanceL": 50, "balanceR": 50, "leftOn": true, "rightOn": true},
            "effect2": {"type": "thru", "balanceL": 50, "balanceR": 50, "leftOn": true, "rightOn": true},
            "serial": false
          },
          "voice1": {
            "pitchEG": {"startLevel": 0, "attackTime": 0, "attackLevel": 0, "decayTime": 0, "releaseTime": 0, "releaseLevel": 0, "timeVelocitySens": 0, "levelVelocitySens": 0},
            "vdf": {"cutoff": 70, "kbdTrackCenter": "C4", "cutoffKbdTrack": 0, "egIntensity": 30, "egTimeKbdTrack": 0, "egTimeVelocitySens": 0, "egIntensityVelocitySens": 20,
                    "eg": {"attackTime": 0, "attackLevel": 99, "decayTime": 40, "breakPoint": 0, "slopeTime": 0, "sustainLevel": 0, "releaseTime": 20, "releaseLevel": 0}},
            "vda": {"level": 99, "kbdTrackCenter": "C4", "kbdTrackIntensity": 0, "velocitySens": 30, "egTimeKbdTrack": 0, "egTimeVelocitySens": 0,
                    "eg": {"attackTime": 0, "attackLevel": 99, "decayTime": 50, "breakPoint": 70, "slopeTime": 30, "sustainLevel": 60, "releaseTime": 25}}
          },
          "voice2": {
            "pitchEG": {"startLevel": 0, "attackTime": 0, "attackLevel": 0, "decayTime": 0, "releaseTime": 0, "releaseLevel": 0, "timeVelocitySens": 0, "levelVelocitySens": 0},
            "vdf": {"cutoff": 99, "kbdTrackCenter": "C4", "cutoffKbdTrack": 0, "egIntensity": 0, "egTimeKbdTrack": 0, "egTimeVelocitySens": 0, "egIntensityVelocitySens": 0,
                    "eg": {"attackTime": 0, "attackLevel": 0, "decayTime": 0, "breakPoint": 0, "slopeTime": 0, "sustainLevel": 0, "releaseTime": 0, "releaseLevel": 0}},
            "vda": {"level": 99, "kbdTrackCenter": "C4", "kbdTrackIntensity": 0, "velocitySens": 0, "egTimeKbdTrack": 0, "egTimeVelocitySens": 0,
                    "eg": {"attackTime": 0, "attackLevel": 99, "decayTime": 0, "breakPoint": 99, "slopeTime": 0, "sustainLevel": 99, "releaseTime": 10}}
          }
        }
        """
        let patch = try M1Patch.decode(json: Data(json.utf8))
        let p = try patch.toProgram()
        XCTAssertEqual(p.name, "Test")
        XCTAssertEqual(p[P.osc1Multisound], 1)
        XCTAssertEqual(p[P.osc2Octave], 1)
        XCTAssertEqual(p[P.effect2Type], 0x21)
        XCTAssertEqual(p[P.voice1Base + V.vdfCutoff], 70)
        XCTAssertEqual(p[P.voice1Base + V.vdfEGAttackLevel], 99)
        XCTAssertEqual(M1SysEx.programDump(p).count, 170)
    }
}

final class TestPhraseTests: XCTestCase {

    func testParseNotes() {
        XCTAssertEqual(TestPhrase.parseNotes("C4 E4 G4"), [60, 64, 67])
        XCTAssertEqual(TestPhrase.parseNotes("c2, g2"), [36, 43])
        XCTAssertEqual(TestPhrase.parseNotes("60 Bb1"), [60, 34])
        XCTAssertEqual(TestPhrase.parseNotes(""), [])
        XCTAssertNil(TestPhrase.parseNotes("C4 X9"))
    }

    func testPresetsAreWellFormedAndRoundTripJSON() throws {
        XCTAssertFalse(TestPhrase.presets.isEmpty)
        for p in TestPhrase.presets {
            XCTAssertFalse(p.steps.isEmpty, p.name)
            XCTAssertGreaterThan(p.totalMs, 0, p.name)
            for s in p.steps {
                XCTAssertTrue((1...127).contains(s.velocity), p.name)
                XCTAssertTrue(s.notes.allSatisfy { (0...127).contains($0) }, p.name)
            }
        }
        let data = try JSONEncoder().encode(TestPhrase.presets)
        let back = try JSONDecoder().decode([TestPhrase].self, from: data)
        XCTAssertEqual(back, TestPhrase.presets)
        XCTAssertEqual(TestPhrase.presets[1].steps[0].notesText, "C4 E4 G4 B4")
        for p in TestPhrase.presets {
            XCTAssertEqual(Set(p.steps.map { $0.id }).count, p.steps.count, "\(p.name) has duplicate step IDs")
        }
    }
}

final class GlobalDataTests: XCTestCase {

    func testLayoutAndRoundTrip() throws {
        XCTAssertEqual(M1GlobalData.minimumByteCount, 861)
        XCTAssertEqual(M1GlobalData.entryOffset(kit: 0, index: 0), 21)
        XCTAssertEqual(M1GlobalData.entryOffset(kit: 1, index: 0), 21 + 210)
        var g = try M1GlobalData(bytes: [UInt8](repeating: 0, count: 861))
        let e = DrumKitEntry(instrument: 4, key: 38, pan: 10, tune: -120, level: 50, decay: -7)
        g.setEntry(e, kit: 2, index: 29)
        XCTAssertEqual(g.entry(kit: 2, index: 29), e)
        let o = M1GlobalData.entryOffset(kit: 2, index: 29)
        XCTAssertEqual(Array(g.bytes[o..<(o + 7)]), [4, 38, 10, 0x88, 50, 0xF9, 0])
        // Wire format: 991 bytes, as observed from a real M1 for the Global dump.
        let dump = M1SysEx.globalDump(g, channel: 0)
        XCTAssertEqual(dump.count, 991)
        XCTAssertEqual(Array(dump.prefix(6)), [0xF0, 0x42, 0x30, 0x19, 0x51, 0x00])
        let parsed = try M1SysEx.parse(dump)
        XCTAssertEqual(parsed.message, .globalDump(g))
        XCTAssertEqual(M1SysEx.globalDumpRequest(channel: 2), [0xF0, 0x42, 0x32, 0x19, 0x0E, 0x00, 0xF7])
    }

    func testKitJSON() throws {
        var g = try M1GlobalData(bytes: [UInt8](repeating: 0, count: 861))
        g.setEntry(DrumKitEntry(instrument: 1, key: 36, pan: 5, tune: 0, level: 10, decay: 0), kit: 0, index: 0)
        g.setEntry(DrumKitEntry(instrument: 4, key: 38, pan: 11, tune: -10, level: 0, decay: 20), kit: 0, index: 1)
        let patch = DrumKitPatch(kit: 0, entries: g.kit(0))
        XCTAssertEqual(patch.kit, 1)
        XCTAssertEqual(patch.entries.count, 2)
        XCTAssertEqual(patch.entries[0].instrument, "Kick1")
        XCTAssertEqual(patch.entries[0].key, "C2")
        XCTAssertEqual(patch.entries[1].pan, "C")
        let back = try patch.toEntries()
        XCTAssertEqual(back.count, 30)
        XCTAssertEqual(back[0], g.entry(kit: 0, index: 0))
        XCTAssertEqual(back[1], g.entry(kit: 0, index: 1))
        XCTAssertFalse(back[2].isAssigned)
        let data = try JSONEncoder().encode(patch)
        XCTAssertEqual(try JSONDecoder().decode(DrumKitPatch.self, from: data), patch)
        var bad = patch
        bad.entries[0].pan = "left"
        XCTAssertThrowsError(try bad.toEntries())
    }
}

final class SynthDefinitionTests: XCTestCase {

    func testKorgM1ConformsSensibly() throws {
        XCTAssertEqual(KorgM1.id, "korg-m1")
        XCTAssertEqual(KorgM1.bankSize, 100)
        XCTAssertEqual(KorgM1.slotLabel(7), "I07")
        XCTAssertEqual(KorgM1.parameters.count, ParameterMap.all.count)
        XCTAssertEqual(KorgM1.sections.count, 19)
        XCTAssertEqual(KorgM1.pages.map { $0.id }, ["program", "effects", "osc1", "osc2"])
        // Every section appears on exactly one page.
        var placed: [ParamSection] = []
        for page in KorgM1.pages { for row in page.rows { for block in row {
            switch block { case .section(let s): placed.append(s); case .sectionWithEnvelope(let s, _): placed.append(s) }
        } } }
        XCTAssertEqual(Set(placed).count, placed.count)
        XCTAssertEqual(Set(placed), Set(KorgM1.sections))
        // Transport maps onto the generic messages.
        let p = M1Program()
        let parsed = KorgM1.parse(KorgM1.programDump(p, channel: 3))
        XCTAssertEqual(parsed?.channel, 3)
        XCTAssertEqual(parsed?.message, .programDump(p.bytes))
        XCTAssertEqual(KorgM1.parse([0xF0, 0x42, 0x30, 0x19, 0x23, 0xF7])?.message, .loadCompleted)
        XCTAssertEqual(KorgM1.selectProgram(slot: 5, channel: 1), [0xC1, 5])
        XCTAssertEqual(KorgM1.prepareForTransfer(channel: 0).count, 1)
        XCTAssertEqual(KorgM1.summary(p), "single · A.Piano")
        let json = try KorgM1.json(for: p)
        XCTAssertEqual(try KorgM1.program(fromJSON: json), p)
    }
}

final class MutationTests: XCTestCase {

    func testRandomiseIsDeterministicAndInRange() {
        let a = KorgM1.randomise(base: M1Program(), seed: 7)
        let b = KorgM1.randomise(base: M1Program(), seed: 7)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, KorgM1.randomise(base: M1Program(), seed: 8))
        var s = a
        ParameterMap.sanitise(&s)
        XCTAssertEqual(s, a, "randomise should already be within documented ranges")
    }

    func testMutateChangesSomethingButNotEverything() {
        let base = M1Program()
        let m = KorgM1.mutate(base, amount: 0.3, seed: 99)
        let changed = zip(base.bytes, m.bytes).filter { $0 != $1 }.count
        XCTAssertGreaterThan(changed, 5)
        XCTAssertLessThan(changed, 120)
        XCTAssertEqual(m.name, base.name)
    }

    func testMorphEndpoints() {
        let a = M1Program()
        var b = M1Program()
        b.setUnsigned(P.voice1Base + V.vdfCutoff, 10)
        b.setSigned(P.osc2Detune, 40)
        let mid = KorgM1.morph(a, b, t: 0.5)
        XCTAssertEqual(mid.unsigned(P.voice1Base + V.vdfCutoff), 55)   // between 99 and 10, rounded
        XCTAssertEqual(mid.signed(P.osc2Detune), 20)
        XCTAssertEqual(KorgM1.morph(a, b, t: 0).unsigned(P.voice1Base + V.vdfCutoff), 99)
        XCTAssertEqual(KorgM1.morph(a, b, t: 1).unsigned(P.voice1Base + V.vdfCutoff), 10)
    }
}
