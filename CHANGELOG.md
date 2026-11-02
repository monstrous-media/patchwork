# Changelog

## 0.2.2

- Page switches up to 10× faster: sliders no longer carry a tick mark per step (AppKit was recomputing
  100–256 tick rects per slider, several times per layout — 1.4 s of a 3 s profile). Found with
  `sample`; values still snap to integers.
- Render-stats timing now fires for every page switch (editor pages had been sharing one view identity).

## 0.2.1

- Faster drawing: theme colours resolve to pre-built NSColors (the dynamic provider was re-parsing hex
  strings on every draw); row labels no longer run a scale-to-fit pass.
- View → Show render stats: body evaluations per second for the busiest views and page-switch time to
  first frame, in the status bar (`Perf.swift`, `.measured("Name")`).

## 0.2.0

- Layout reflows: editor cards fill as many columns as fit (one on a narrow window, three on a wide
  one), envelope sketches sit inside their EG card, bit switches wrap, labels truncate instead of
  squeezing sliders; drum kit header split in two rows; window minimum 880 × 600.
- New app icon (patch bay: nine sockets, one cable) and a visual theme to match the hardware: dark by
  default with the M1's LCD green as the single signal colour, monospaced accent values, LCD-style name
  field and envelope wells, section cards with their SysEx byte ranges, status chips, and a colour
  language in the MIDI log (acks green, incoming blue, warnings amber, refusals red). View → Appearance
  switches dark / light / system. `Theme.swift` holds every colour; change `Theme.accent` to retint.
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
