# Patchwork — Korg M1 User Guide

Patchwork is a Mac editor, librarian and audition tool for hardware synthesizers — the Korg M1 first — with a command-line companion (`patchwork`) and a patch format Claude can write.

## Three places a sound can live

Everything in the app is easier once these three are clear:

- **Edit buffer** — the sound the M1 is playing *right now*. Temporary: the M1 throws it away the moment you select another program on its panel. Everything the editor sends goes here.
- **Slot** — one of the M1's 100 stored programs, I00–I99. The only way into a slot is **Write**. Memory Protect on the M1 must be off.
- **Bank** — a local, named copy of 100 slots kept by the app (and exportable as a `.syx` file). The M1 holds one bank; the app can hold many: a factory backup, work in progress, experiments.

The verbs match the direction of travel:

| Verb | From → to | Where |
|---|---|---|
| **Request** | M1 edit buffer → editor | toolbar ⬇, ⌘R |
| **Send** | editor → M1 edit buffer | toolbar ⬆, ⌘S, or automatically with *Auto-send* |
| **Write** | editor → M1 slot | toolbar 🖴 + slot picker, ⇧⌘W — asks first |
| **Fetch bank** | all 100 M1 slots → a new local bank | Library |
| **Request / Send (Global)** | the M1's drum kits ↔ the Drum kits page (stored on Send) | Drum kits |
| **Restore** | local bank → all M1 slots | Library |
| **Store** | editor → a local bank slot | Library row ⬇ |
| **Load** | local bank slot → editor | Library row |

## Setup

### Wiring

Two MIDI cables through the audio interface (a Komplete Audio 6 in the original setup, but any interface with 5-pin MIDI works):

- Interface **MIDI OUT → M1 MIDI IN** — lets the app play and program the M1.
- M1 **MIDI OUT → interface MIDI IN** — lets the M1 answer. Without it *Request*, *Fetch*, *Verify* and every acknowledgement are silent. Use the socket marked **OUT** on the M1, not **THRU**.

Audio: M1 outputs 1/L and 2/R → interface line inputs. Hear it through the interface's direct-monitor control or a monitoring track in a DAW; macOS never routes an input straight to an output by itself.

### On the M1

- **GLOBAL → 5** (MIDI Global): note the **Channel** — the app's *Ch* picker must match. *Local* stays ON.
- **GLOBAL → 5 → Page+** (MIDI Filtering): **Exclusive = ENA**. It is DIS from the factory and gates SysEx in both directions.
- **GLOBAL → 6**: **Memory Protect → Program = OFF** when you want to Write or Restore.
- The M1 answers program requests only in **Program mode**. The app switches it there itself before any transfer (M1 menu → *Switch M1 to Program mode* does it by hand).

### In the app

The app is dark by default — a matte panel with one signal colour, the green of the M1's display, used for every value and for anything the M1 has confirmed; amber means the screen is ahead of the M1. **View → Appearance** switches to light or follows the system.

The bar under the toolbar: **In** and **Out** ports (the interface is picked automatically), **Ch**, and **Auto-send on edit**. ↻ rescans after plugging something in.

At the right, a heartbeat dot: **M1 heard** (green) means bytes are arriving on In — a powered, cabled M1 sends active sensing continuously, so this proves the return path. **M1 silent** (amber) means nothing has arrived for 2 s. A *Send* only proves the data reached the interface; if the M1 doesn't acknowledge within 0.7 s the log says so and suggests what to check (at most once every 15 s while you keep editing).

### First run

1. Library → **Fetch bank from M1** (about 20 seconds). A dated bank appears.
2. **Export .syx…** → keep that file somewhere safe. The M1 has no factory reset for programs; this file is your undo.
3. **Verify against M1** should report 100 of 100 matching.
4. Back on *Program*, click **Request**, tick **Retrigger on change**, drag the OSC 1 cutoff. You should hear it.

## Editing

The **Program**, **Effects**, **OSC 1** and **OSC 2** pages show every one of the M1's 143 program parameters as a control, grouped the way the M1's own edit pages group them.

- With **Auto-send on edit** on, each change is sent to the edit buffer about 80 ms after you stop moving the control. The M1 replies "Data load completed" in the MIDI log.
- The status bar shows the current program name and *edited* when it differs from what was loaded.
- The M1's **edit buffer is not saved**. Use **Write** to keep a sound, or **Store** it in a local bank.

Signal path, for orientation: *multisound* (PCM sample) → **VDF** (low-pass filter with its own envelope) → **VDA** (amplifier with its own envelope) → **Effect 1** → **Effect 2**. *Double* mode layers two of these (OSC 1 and OSC 2) at 8-voice polyphony; *single* uses OSC 1 only at 16.

### Drum programs

In *Drums* mode OSC1 selects **Drum Kit 1–4** rather than a multisound. The kit itself — which drum instrument sounds on which key — is edited on the **Drum kits** page.

### Effects parameters

The eight raw bytes behind each effect are labelled by effect type (reverb time, pre-delay, feedback…) but their exact encodings aren't published, so they're shown as plain 0–255 values. Values copied from a real program are safe; invented ones may do odd things.

## Auditioning — the play bar

Under every editing page. The real M1 is the preview engine; the app only tells it what to play.

- **Play / Stop** (⌘↩) runs the selected **phrase**. Looping phrases are marked ↻ and run until stopped.
- **Phrase** picker: single note, held chord, pad swell, staccato, arpeggio, bass riff, velocity ramp, octaves, fifths. *Velocity ramp* exposes velocity sensitivity; *Octaves* exposes keyboard tracking.
- **Edit…** opens the phrase editor: each step is a set of notes (`C4 E4 G4`, blank = rest), a velocity, a *gate* (how long the keys are held) and a *gap* (silence after). Phrases persist; *Reset to presets* restores the defaults.
- **Transpose** shifts everything in semitones — bass phrases want −12.
- **Retrigger on change** replays the phrase after every edit, Randomise, Mutate, Morph, Init, Load or Request — hands-free listening.
- The two-octave **keyboard** plays while the mouse is held; the stepper sets its lowest octave.
- ⌘. sends All Notes Off if anything ever sticks.

## Drum kits

A *drum kit* on the M1 is what samplers call a **keymap**: each of up to 30 entries places one of the M1's 44 drum instruments on one key, with its own tune, level, decay and output pan. Unassigned keys beside an entry play the nearest instrument, so entries behave like small zones. Kits are not part of a program — they live in the M1's **Global data**, which is why the page works differently from the program editor:

1. **Request** pulls the Global data (settings plus all four kits). The M1 must have Exclusive = ENA; the message is about 1 KB.
2. Pick a **kit** (1–4) and edit entries: instrument, key (with a ▶ to hear it), pan (A…B across the main outputs; C, D, C+D for the individual outputs), tune (tenths of a semitone, ±120 = an octave), level and decay offsets.
3. Edits stay in the app until you press **Send** — or turn on *Auto-send kit edits*. Either way, what the M1 receives is **stored immediately**: Global data has no edit buffer and no memory protect, unlike programs. **Revert** discards unsent edits. Every Request also writes a dated backup `.syx` to the app's folder (Application Support/Patchwork/global-backups), and `patchwork global --send file.syx` puts one back.
4. **Use this kit in the editor** puts the editor's program into Drums mode with that kit and sends it, so the play bar's keyboard and phrases play the kit while you edit it.
5. Import/export a kit as `.json` (`korg-m1-drumkit/1`: instrument names, note names, pan labels) — Claude can write these too.

Everything else in Global data (master tune, transpose, pedal assignments, scales) is carried along untouched.

The general "different whole sounds on different key ranges" capability is the M1's **Combination** mode (eight programs with key and velocity windows); it has its own dump and isn't covered by this editor yet.

## Generators

In the sidebar.

- **Randomise** rolls a complete new program (the die tumbles through a few throwaway ones first). Effect bytes are kept from the current program; everything else is in range but unopinionated. Named `RND nnnn`.
- **Mutate** nudges a proportion of parameters — the slider sets how many — by a step scaled to each one's range. Multisounds and switches change rarely. Rows that changed glow.
- **Morph** (Library rows, ⤳) interpolates the editor's numeric parameters toward a slot's program by the percentage on the Library header slider; discrete parameters switch at 50 %.
- **Init** loads a neutral starting point: single A.Piano, filter open, sustaining amplifier, Hall.

Nothing here touches the M1's slots; it all goes to the edit buffer (and is heard immediately when *Retrigger* is on).

## Library — banks and slots

Left: your banks. Right: the 100 slots of the selected bank.

### Bank actions

- **Fetch bank from M1** — reads all 100 slots into a *new* dated bank. Never overwrites an existing one.
- **Verify against M1** — re-reads the filled slots and names any that differ.
- **Restore to M1…** — writes every filled slot of this bank into the M1, one slot at a time, each acknowledged by the M1 before the next. Stops at the first refusal (Memory Protect). *verify after* re-reads them all. Asks for confirmation.
- **Export .syx…** — the bank as a standard SysEx file (program dumps in slot order). Other librarians and Korg's own M1 software read it.
- Bank list buttons: ＋ new empty bank · import `.syx` (files with more than 100 programs become several banks) · duplicate · − delete the local copy (the M1 is untouched).
- Rename a bank in the name field.

### Slot row actions

| | Action | Effect |
|---|---|---|
| **Load** | slot → editor | sends it to the M1 too when Auto-send is on |
| ⤳ | morph | editor patch moves toward this one by the header percentage |
| ⬇ | store | editor patch replaces this *local* slot (the M1 is untouched) |
| 🖴 | write to M1 | this program into the M1's slot of the same number; confirmed, then read back and verified |
| ⬆ | save | this program as a `.syx` or `.json` file |
| ⊗ | clear | empties the local slot |

### Undo

Every local library change — Store, Clear, import, new/duplicate/delete bank, the mirror after a Write — and every kit edit is undoable with **⌘Z** (Edit → Undo), and redoable with ⇧⌘Z. Changes on the M1 itself (Write, Restore, Send of Global data) are not: for those the undo is your exported `.syx` and the automatic Global backups.

### The toolbar Write

Writes the **editor** patch to the M1 slot chosen in the picker, after a confirmation naming the patch and the slot (the same dialog whether you use the button, the M1 menu or ⇧⌘W — a Write cannot be undone, so nothing reaches the M1 from a single click). With **mirror** ticked, the same program is also stored in that slot of the selected bank once the M1 confirms, so the bank keeps matching the synth. Untick it when the selected bank is a backup you want left as it was.

## MIDI log

Everything sent and received, decoded. Two uses beyond debugging:

- Diagnosis: "No reply" means the return cable or Exclusive; "Data load error" means the M1 wasn't in Program mode; "Write error" means Memory Protect.
- Discovery: edit a parameter on the M1's own panel and the log prints the `41` parameter-change message with its page and position — the map needed to drive single-parameter edits later.

## Files

Everywhere in the app: a **folder** icon opens or imports a file; a **box with a down arrow** saves or exports one.

- **`.json`** — the readable `korg-m1-program/1` format: every parameter named, with musical units. Claude writes and edits these. *Open* and *Save* in the toolbar use it by default.
- **`.syx`** — raw SysEx. One program (170 bytes) or many; the M1 itself and other tools speak this.
- Phrases and banks are kept by the app (UserDefaults and Application Support); export banks as `.syx` for anything you'd mind losing.

## Command line — patchwork

Everything the app does, scriptable. Ports are found automatically; `--channel N` if the M1 isn't on channel 1.

```
patchwork ports                          list MIDI ports
patchwork dump --json current.json       Request → file
patchwork send patch.json [--write 57]   Send (and Write)
patchwork play --notes "C4 E4 G4"        audition;  --phrase "Pad swell"  --transpose -12
patchwork bank --syx f.syx --json-dir d/ Fetch bank → files
patchwork restore f.syx --verify         Restore (slot = position in file)
patchwork restore p.json --slot 57       write one program to one slot
patchwork describe / validate / convert  inspect and convert patches
patchwork random / mutate / morph        generators, to JSON
patchwork global [--kit 2 --json k.json] drum kits: show / save / --load k.json / --send g.syx
patchwork mode [program]                 ask or set the M1's mode
patchwork monitor [--raw]                watch what the M1 sends
```

## Claude and the patch format

`skills/korg-m1-patch/SKILL.md` teaches Claude the M1's signal path, the multisound list and a cookbook ("warmer", "more pluck", "wider"), and the loop: write JSON → `patchwork validate` → `patchwork send` → `patchwork play` → iterate on what you hear. The JSON schema in `schema/` documents every field.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Notes play but *Request* gets no reply | M1 MIDI OUT not reaching the interface, or Exclusive = DIS | check the OUT (not THRU) cable; GLOBAL 5 → Page+ → Exclusive ENA |
| "Data load error" | M1 not in Program mode | M1 menu → Switch to Program mode (transfers do this themselves) |
| "Write error" | Memory Protect on | GLOBAL 6 → Program protect OFF |
| M1 silent to the app's notes | channel mismatch | GLOBAL 5 → Channel; match the *Ch* picker |
| Fetch returns 100 identical names | M1 ignoring Program Change | GLOBAL 5 → Page+ → Combi/Prog Change ENA |
| "Sent … but nothing came back on In", dot amber | M1 off or not cabled back to the interface | power, M1 MIDI OUT → interface IN, the *In* picker |
| "M1 didn't acknowledge" but dot green | channel or Exclusive | GLOBAL 5 → Channel = *Ch*; Page+ → Exclusive ENA |
| No ports listed | interface not seen | ↻ in the MIDI bar; check the USB cable |
| Notes stuck | a note-off was lost | ⌘. (All notes off) |

## Parameter help

Every control has a tooltip explaining what the M1 calls it, what it is in general synthesis terms and what it does musically. The same text is collected in the **Parameter reference** at the end of this guide (and `patchwork params` prints it as Markdown).

## Glossary

- **Edit buffer** — the M1's working copy of the current program; not saved.
- **Slot** — a stored program I00–I99 in the M1.
- **Bank** — 100 slots as a local, named copy in the app.
- **Program** — the M1's word for a patch (one sound). *Combination* layers up to eight programs; not covered by this editor.
- **Drum kit** — a keymap: 30 entries of drum instrument → key (+ tune, level, decay, pan), stored in Global data; selected by a program in Drums mode.
- **Multisound** — one of the M1's 100 sampled waveforms, the raw material of a program.
- **VDF / VDA** — the M1's filter and amplifier sections, each with its own envelope (EG).
- **MG** — modulation generator, Korg's name for an LFO.
- **SysEx** — System Exclusive MIDI messages, the channel the editor uses to read and write programs.
