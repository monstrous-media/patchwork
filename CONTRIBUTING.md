# Contributing

## Architecture in one paragraph

Everything the app and CLI do — CoreMIDI, SysEx reassembly, ack-driven transfers (fetch / restore / verify),
banks and slots, undo, the table-driven editor, generators, the play bar, help — is synth-agnostic and talks to
the instrument through one protocol, `SynthDefinition` (`Sources/PatchworkCore/Synth.swift`). A synth is a program
byte layout, a parameter table that describes it, and the SysEx grammar to read and write it. The Korg M1
(`Sources/PatchworkCore/KorgM1.swift`) is the reference implementation; the app selects the synth at compile time via
`ActiveSynth` (`Sources/PatchworkApp/ActiveSynth.swift`). Runtime selection is the obvious next step once there is a
second definition.

## Adding a synth

1. **Program type** — a struct conforming to `ProgramData`: raw bytes, a name, typed accessors (the M1's
   `M1Program` is the template; the accessors are the same for any byte-array program).
2. **Parameter table** — `[ParamDef]` with index, name, section and kind (`unsigned`, `signed`, `choice`,
   `bits`, `note`, …). The editor, tooltips, randomiser, mutator, morph and the generated parameter reference
   all come from this table. The `ParamKind` vocabulary grew from the M1; add kinds when a synth needs them.
3. **Sections and pages** — `ParamSection` values and `[EditorPage]` (rows of sections, optionally with an
   envelope sketch). This is the whole editor layout.
4. **Transport** — `isMessage`, `parse` (into the generic `SynthMessage` kinds), `programDumpRequest`,
   `programDump`, `writeRequest`, `prepareForTransfer` (e.g. a mode change), `selectProgram` (a Program
   Change by default), and `hasEditBuffer`. Manufacturer packing/checksum helpers live beside the definition
   (`KorgPacking` is Korg's 7-in-8; Roland and Yamaha need their own).
5. **Files** — `programs(inSyx:)`, and a human-readable JSON form (`json(for:)` / `program(fromJSON:)`) so
   Claude or a person can author patches; add a schema under `schema/` and a skill under `skills/`.
6. **Help** — `help(for:)` text per parameter: what the synth calls it, the general synthesis idea, the musical
   effect. One sentence each is enough.
7. **Tests** — vectors generated independently (see `tools/m1ref.py`), round-trips, and a conformance test
   like `SynthDefinitionTests` (every section on exactly one page, parse ↔ build symmetry).

What still references the M1 directly, and would need generalising for a second synth with similar features:
the **Drum kits** page (Global data), the MIDI log's decoding of M1 extras (mode data, panel parameter
changes), a few `ParamKind` cases (`multisound`, `effectType`, `effectParam`) that carry M1 name tables, and
`patchwork`, which is intentionally M1-specific.

## Ground rules

- Don't commit factory banks or any dump captured from an instrument: those are the manufacturer's copyright.
  Test vectors are synthetic.
- Every change that touches bytes on the wire comes with a test vector.
- Labels, tooltips and the guide share one vocabulary (edit buffer / slot / bank; Request / Send / Write /
  Fetch / Restore / Store / Load). Keep it.
- `swift test` must pass on macOS and Linux (the Core has no Apple-only imports).
