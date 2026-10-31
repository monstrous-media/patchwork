# Patchwork

A Mac editor, librarian and audition tool for hardware synthesizers, built around one protocol so that adding a
synth is one file. The **Korg M1** is the first and reference implementation. Comes with a command-line
companion (`patchwork`) and a readable JSON patch format that Claude can write.

```
Sources/PatchworkCore   pure Swift: SynthDefinition protocol, generic codec/model/generators, the Korg M1 definition (unit-tested, Linux-clean)
Sources/PatchworkMIDI   CoreMIDI wrapper (endpoints, send, SysEx reassembly)
Sources/patchwork       CLI: ports · dump · bank · restore · send · write · play · global · random · mutate · morph · describe · params · mode · monitor
Sources/PatchworkApp    SwiftUI app: generated editor pages, play bar, banks & slots, drum kits, undo, built-in guide
schema/ skills/         JSON schema + Claude skill for authoring patches
docs/                   user guide and generated parameter reference (static-site ready)
tools/                  Python reference codec (test vectors), make-app.sh, sync-docs.sh
```

## Build

macOS 13+ with Xcode or the Command Line Tools.

```sh
swift test                               # Core tests (also run on Linux in CI)
swift build -c release
.build/release/patchwork ports
swift run PatchworkApp                    # the app, straight from the package
tools/make-app.sh                        # assemble (and optionally sign + notarise) Patchwork.app
```

## Wiring and M1 settings

- Interface **MIDI OUT → M1 MIDI IN**, and M1 **MIDI OUT → interface MIDI IN** (needed for Request / acks).
- On the M1: **GLOBAL → 5 → Page+ → Exclusive = ENA**; global channel must match the app's *Ch*.
- **GLOBAL → 6 → Memory Protect → Program = OFF** to Write or Restore.
- The app switches the M1 to Program mode itself before transfers.

## Quick start

```sh
patchwork dump --json current.json           # grab what the M1 is playing now
patchwork send examples/glass-pad.json       # audition
patchwork play --phrase "Pad swell"
patchwork bank --syx factory.syx --json-dir bank/   # back up all 100 programs (do this before any Write!)
patchwork restore factory.syx --verify
patchwork global --syx global.syx            # drum kits and global settings
```

## Three places a sound lives

**Edit buffer** (what the M1 plays now; temporary) · **slot** (I00–I99, stored in the M1; Write/Restore only) ·
**bank** (a local 100-slot copy; many of them). Verbs: Request, Send, Write, Fetch, Restore, Store, Load. The
in-app guide (Help menu, ⌘?) explains each, and every control has a tooltip.

## Extending to other synths

Everything above the `SynthDefinition` protocol (`Sources/PatchworkCore/Synth.swift`) is synth-agnostic:
MIDI, transfers, banks, undo, the table-driven editor, generators, play bar, help. `KorgM1.swift` is the
reference implementation; the app selects the synth at compile time (`ActiveSynth`). See `CONTRIBUTING.md`.

## Patch JSON and Claude

`schema/m1-patch.schema.json` documents every field with its musical meaning; `skills/korg-m1-patch/SKILL.md`
teaches Claude the M1 signal path and a cookbook of edits; `patchwork validate / send / play` close the loop.

## SysEx facts (Korg M1)

```
F0 42 3g 19 ff … F7     42 Korg · 3g channel g · 19 M1 family · ff function
10 → 40  program dump (143 params, 7-in-8 packed, 170 bytes)   1C 00 → 4C 00  all programs (16,350 bytes)
11 00 nn write to slot nn      12 → 42 mode data      4E mode change      0E 00 → 51 00 global data (861 bytes: settings + 4 drum kits)
23/24 load ok/error · 21/22 write ok/error · 26 format error · FE active sensing
```

## Known gaps

- Single-parameter (`41`) live edits: the editor re-sends the whole program (debounced). The MIDI log shows the
  page/position of panel edits, which is the map needed.
- Effect parameter byte encodings per effect type (shown raw).
- Combinations and sequencer data aren't modelled.
- Dual-effect names 26–33 follow the manual's listing order; verify on the panel.

## Licence

MIT — see `LICENSE`. Korg and M1 are trademarks of Korg Inc.; this project is not affiliated with Korg.
Don't commit factory banks or instrument dumps (they're Korg's copyright).
