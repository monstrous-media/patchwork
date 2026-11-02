# Changelog

## Unreleased

- MIDI bar heartbeat: **M1 heard** / **M1 silent**, driven by anything arriving on In (the M1's
  active sensing), so a working return path is visible at a glance.
- Edit-buffer and Global sends now expect the M1's acknowledgement; when none arrives within 0.7 s
  the log explains what to check (cabling/power vs channel/Exclusive), rate-limited to one line per
  15 s. Routine "Data load completed" acks for auto-sends no longer flood the log.

## 0.1.1

- Fix crash on launch when running the downloaded `Patchwork.app` (the built-in guide's resource
  bundle was looked up via SwiftPM's `Bundle.module`, which only works on the machine that compiled
  it). The app now finds the bundle itself and shows a message instead of crashing if it is missing;
  `make-app.sh` refuses to package an app without it.

## 0.1.0

First public version.

- Korg M1: program editor for all 143 parameters, SysEx request/send/write, bank fetch/restore/verify,
  drum kit (Global data) editor, readable JSON patch format + schema + Claude skill.
- Audition play bar with editable phrases, retrigger on change, on-screen keyboard.
- Generators: randomise, mutate, morph.
- Banks and slots with undo; mirrored writes; automatic Global data backups.
- Built-in guide with generated parameter reference; tooltips on every control.
- `patchwork` CLI mirroring the app.
- `SynthDefinition` protocol so other synths can be added as one file.
