# Security

Patchwork is a desktop app that talks to a synthesizer over MIDI. It has no network access of its own, no
accounts, and no third-party package dependencies; it reads and writes files you point it at, plus its own
banks and Global-data backups under `~/Library/Application Support/Patchwork`.

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting on this repository (**Security → Report a vulnerability**)
rather than a public issue, so a fix can ship before details are public. Expect an acknowledgement within a
week. Once fixed, the advisory is published with credit unless you ask otherwise.

## What's in scope

- Anything that lets a crafted `.syx` or `.json` file do more than load a patch (crashes on malformed input
  are bugs we want to hear about too).
- The release pipeline: the shipped `Patchwork.app` is signed with a Developer ID and notarised by the
  `Release` workflow from a tag; a build that doesn't verify with `spctl -a -vv Patchwork.app` is a problem.

## Supported versions

The latest release only.
