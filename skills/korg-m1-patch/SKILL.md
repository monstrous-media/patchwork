---
name: korg-m1-patch
description: Design, edit or audition Korg M1 synthesizer programs. Use when the user asks for an M1 sound ("make me a warm pad for the M1", "brighter", "more pluck"), wants a patch written as JSON, converted to SysEx, or sent to the synth with patchwork.
---

# Korg M1 patch authoring

You write M1 programs as JSON in the `korg-m1-program/1` format (schema: `schema/m1-patch.schema.json`,
worked examples: `examples/*.json`). The `patchwork` tool turns that JSON into SysEx and sends it to the
synth; the Patchwork app opens the same files.

## Workflow

1. **Start from something.** Copy the nearest example (`examples/glass-pad.json` for sustained sounds,
   `examples/pluck-bass.json` for percussive ones) or ask for the current sound: `patchwork dump --json current.json`.
   Never write a patch from a blank object — every field is required and the examples carry sensible defaults.
2. **Edit the fields that matter for the request** (see the cookbook below). Keep `name` ≤ 10 characters.
3. **Validate** before sending: `patchwork validate patch.json` (errors name the exact field and range).
4. **Audition**: `patchwork send patch.json` loads it into the M1's edit buffer (not stored). Then play it:
   `patchwork play --notes "C4 E4 G4" --ms 1500` for a chord, or a preset phrase that suits the sound —
   `patchwork play --phrase "Pad swell"`, `"Bass riff" --transpose -12`, `"Arpeggio"`, `"Velocity ramp"` (reveals velocity
   sensitivity), `"Octaves"` (reveals keyboard tracking). The user can also hear it from the Patchwork play bar.
5. **Iterate** on their feedback by editing the JSON again — change 1–3 parameters per step and say which ones.
6. **Store** only when asked: `patchwork send patch.json --write 57 --yes` writes to internal slot I57 (Memory Protect must be OFF).
   Commands that overwrite the M1 (`--write`, `write`, `restore`, `global --send/--load`) refuse to run without a
   terminal confirmation or `--yes`; pass `--yes` only after the user has agreed to that specific slot.

Describe a patch with `patchwork describe patch.json`. Convert between formats with `patchwork convert in.json out.syx`.

## The M1 signal path (what the fields mean)

`multisound (PCM sample) → VDF (low-pass filter with its own EG) → VDA (amplifier with its own EG) → effect1 → effect2`

- **oscillatorMode**: `single` uses OSC1 only (16-note polyphony); `double` layers OSC1+OSC2 (8 notes). Layering
  a sampled sound with a `SawWave`/`SquareWave`/`DWGS …` waveform is the classic M1 trick for thickness.
- **Multisounds** (OSC source, pick by name):
  - Keys: `A.Piano`, `E.Piano1`, `E.Piano2`, `Clav`, `Harpsichord`, `Organ1`, `Organ2`, `MagicOrgan`
  - Strings/guitars: `Guitar1`, `Guitar2`, `E.Guitar`, `Sitar1`, `Sitar2`, `Strings`, `KotoTrem`, `BambooTrem`
  - Bass: `A.Bass`, `PickBass`, `E.Bass`, `Fretless`, `SynthBass1`, `SynthBass2`, `BassThumb`
  - Mallets/bells: `Vibes`, `Bell`, `Tubular`, `BellRing`, `Karimba`, `SynMallet`, `WindBells`
  - Winds/brass: `Flute`, `PanFlute`, `Bottles`, `Brass1`, `Brass2`, `TenorSax`, `MuteTP`, `Trumpet`, `TubaFlugel`, `DoubleReed`
  - Voices: `Voices`, `Choir`, `VoiceWave`, `DWGS Voice`
  - Synth waves: `SquareWave`, `SawWave`, `25% Pulse`, `10% Pulse`, `Digital1`–`Digital5`, `DWGS Tri`, `DWGS Sine`,
    `DWGS EP1`–`3`, `DWGS Piano`, `DWGS Clav`, `DWGS Vibe1`, `DWGS Bass1`/`2`, `DWGS Bell1`, `DWGS Orgn1`/`2`, `PanWave`, `PingWave`, `FvWave`, `MvWave`
  - Hits/FX: `FingerSnap`, `Pop`, `Drop`, `Breath`, `Pluck`, `VibeHit`, `Hammer`, `MetalHit`, `Pick`, `Distortion`, `Wire`, `Lore`, `Flexatone`, `Pole`, `Block`, `Rhythm`
  - `…NT` variants are the attack transient only (no loop) — good for layering a click/pluck onto a sustained sound.
- **VDF**: `cutoff` 99 = open (bright/raw sample), 30–55 = warm, < 25 = dark. `egIntensity` sets how far the filter EG
  pushes the cutoff; `egIntensityVelocitySens` > 0 makes harder playing brighter. Filter EG levels are bipolar (−99…+99).
- **VDA EG**: attack/decay/break/slope/sustain/release, all 0–99. Pads: attack 30–60, sustain 70–99, release 40–60.
  Plucks/bass: attack 0, decay 20–40, sustain 0–45, release 8–15. `velocitySens` 20–50 for playable dynamics.
- **pitchMG** = vibrato (frequency ~35–45, intensity 3–8, delay 20–40 for delayed vibrato). **vdfMG** = filter wobble.
- **osc2.detune** ±4…8 cents on a double program = chorus-like width; `interval` 7 = fifth, 12 = octave.
- **Effects**: effect1 → effect2, `serial: true` chains them. Reverbs: `Hall`, `Concert Hall`, `Room`, `Large Room`;
  modulation: `Stereo Chorus I`, `Symphonic Ensemble`, `Stereo Flanger`, `Phaser I`; drive: `Overdrive`, `Distortion`;
  `Rotary Speaker` for organs; `Delay/Hall` etc. give delay + reverb in one slot. `balanceL/R` 0 = dry, 100 = wet
  (reverb 30–45, chorus 40–50, overdrive 15–30). Leave `params` out unless copying from a dump.

## Cookbook (what to change for common requests)

| Request | Change |
|---|---|
| warmer / darker | lower `vdf.cutoff` by 10–15, lower `effect` balances slightly |
| brighter | raise `vdf.cutoff`, raise `egIntensityVelocitySens` |
| more pluck / attack | `vdf.egIntensity` 60–80, filter `eg.attackTime` 0, `eg.decayTime` 15–30, `eg.sustainLevel` ≤ 0 |
| softer / slower | VDA `eg.attackTime` +15, filter `eg.attackTime` +15 |
| thicker | switch to `double`, add a `SawWave`/`DWGS …` OSC2 with `detune` 5–8 |
| wider / shimmer | `Stereo Chorus I` or `Symphonic Ensemble` in effect1, balance 45 |
| more space | `Concert Hall` in effect2, balance 35–50, VDA release +10 |
| dry / tight | effect types `thru` or balances ≤ 10, release 8–12 |
| vibrato | `pitchMG.intensity` 4–8, `delay` 25–35, `aftertouch.pitchMG` 20–40 |
| bass | `oscillatorMode` double, `assign: mono`, octave `16'`, `kbdTrackCenter` C2 |

## Gotchas

- The M1 must be in **Program mode** with **Global → MIDI filter → Exclusive = ENA** to accept dumps, and
  **Memory Protect OFF** for `--write`. Sends go to the edit buffer and are lost when the user changes program
  unless written.
- `voice2` must always be present even in `single` mode (the M1 ignores it).
- `name` is ≤ 10 printable ASCII characters.
- The 8 effect `params` bytes have undocumented per-type encodings — don't invent values; omit the key.
- Multisound numbers ≥ 100 (`card:N`) need a PCM card inserted.
