# Backdrop

Plays the videos already in your Photos library in Picture in Picture and in the
background, with the system Now Playing card on the Lock Screen and in the Dynamic
Island. Nothing leaves the phone. TestFlight only; no App Store release.

Design: `docs/superpowers/specs/2026-08-23-backdrop-design.md`.

## Layout

- `core/` — BackdropCore, a pure-Swift package (queue, resume rules, store, Now Playing
  snapshot, diagnostics log). `cd core && swift test` runs on Windows, macOS and CI.
- `ios/` — the SwiftUI app. The Xcode project is generated from `project.yml` by XcodeGen
  and never committed.

## Pipeline

Windows (code) → push → GitHub Actions (core tests, unsigned simulator build, screenshots
of every screen) → Codemagic (signed build) → TestFlight → phone.

- Watch Actions: `gh run list --branch main --limit 1`, then `gh run watch <id> --exit-status`.
- Watch Codemagic: `python scripts/codemagic.py watch`.

## Screens for CI

Launch arguments: `-initialScreen library|permission|player|queue|diagnostics`,
`-fixtureLibrary YES` (bundled clip instead of Photos), `-legacyGlass YES` (material
fallback the simulator renders reliably).

## Device checklist

See the spec's "Device checklist". Diagnostics (gear on the library screen) shows the
on-device log and the background-detach experiment switch; share the log if a step fails.
