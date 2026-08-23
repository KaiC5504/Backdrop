# Backdrop — design

Date: 2026-08-23. Status: approved in chat, written up here.

## Problem

The iOS Photos app cannot play a video in Picture in Picture, and it stops the moment the
phone is locked or the app is backgrounded. The only apps that do both are streaming apps,
and they want the video uploaded first. Backdrop plays the videos already in the phone's
Photos library, in PiP and in the background, with the system Now Playing card on the Lock
Screen and in the Dynamic Island so the timeline is visible without unlocking. Nothing
leaves the device; there is no account, no network, no upload.

Distribution is TestFlight to the owner's phone only. No App Store release is planned.

## Decisions already made

| Question | Decision |
| --- | --- |
| Lock Screen / Dynamic Island timeline | System Now Playing (`MPNowPlayingInfoCenter` + `MPRemoteCommandCenter`). No ActivityKit Live Activity, no widget extension, no App Group. |
| Where videos come from | Browse the Photos library inside the app and play straight from the `PHAsset`. No import, no copying. |
| Playback extras | Auto-play next, loop single video, playback speed, remember position. |
| Minimum iOS | 26.0 (owner's phone; gives native Liquid Glass in SwiftUI). iPhone only. |
| Player implementation | `AVPlayerViewController` (system player) inside a custom glass shell. A fully custom `AVPlayerLayer` player is a contained later swap if the system look ever grates. |
| Name / bundle id | Backdrop, `com.kaichuan.backdrop`. |
| Pipeline | NextStop's, verbatim in shape: Swift 5 mode, SwiftUI, XcodeGen `project.yml`; GitHub Actions unsigned simulator build with tests and screenshots; Codemagic signed build to TestFlight. Public GitHub repo so macOS Actions minutes stay free. |
| Where the logic lives | A pure-Swift package `core/` (BackdropCore) holds everything that needs no UIKit/AVFoundation — queue, resume rules, store, Now Playing snapshot, diagnostics log, title formatting — and is unit-tested with Swift Testing via `swift test` on the Windows dev box (Swift 6.3.3 installed 2026-08-23) as well as in CI. The app in `ios/` depends on it as a local package. |

## Scope

In v1:

- Photos permission gate (full and Limited access).
- Library: every video in Photos, newest first, with an album chip row.
- Player: full screen system player with Backdrop's overlay for loop, speed, queue.
- Picture in Picture, including automatic PiP when the app is backgrounded while playing.
- Background audio when the phone is locked or the app is not in front, with or without PiP.
- Now Playing card and Dynamic Island presence with title, thumbnail, scrubbable timeline,
  play/pause, previous/next.
- Queue: play next, add to queue, reorder, remove; auto-advance at end of video.
- Loop single video. Speed 0.5x–2x with pitch preserved. Remembered position per video.
- Mini-bar over the library while something is playing.
- A Diagnostics screen with an on-device log and a share sheet, because the phone can never
  be plugged into the build machine.

Not in v1: shuffle, audio files, import from Files, custom Live Activity, subtitle
handling beyond what the system player gives, iPad, App Store release, iCloud sync of
positions, sorting options beyond newest-first.

## Architecture

One app target (no test target) plus the BackdropCore package with its own test target.
Everything is Swift, SwiftUI for the shell, UIKit only where AVKit demands it.

```
core/                        BackdropCore — Foundation only, `swift test` anywhere
  Package.swift
  Sources/BackdropCore/      VideoItem, AlbumItem, VideoTitleFormatter, PlaybackQueue,
                             ResumePolicy, PlaybackStore, NowPlayingSnapshot(+Builder),
                             DiagnosticsLog
  Tests/BackdropCoreTests/   one Swift Testing suite per unit above
ios/
  project.yml                XcodeGen spec — the project file is generated, never committed
  Sources/App/
    BackdropApp.swift        @main, RootView
    AppModel.swift           composition root, navigation flags, launch options
    Library/                 LibrarySource protocol, PhotosLibrary, FixtureLibrarySource,
                             LibraryView, VideoCell, AlbumChips, PermissionGateView
    Playback/                PlaybackEngine, PlayerHost, PlayerScreen (+PlayerHostView),
                             PlayerControls (+SpeedMenu), MiniBarView, QueueSheet
    NowPlaying/              NowPlayingController
    Audio/                   AudioSessionController
    Diagnostics/             DiagnosticsView
    UI/                      Theme, Glass helpers, BackdropBackground
    Fixtures/sample.mp4      one small generated clip: bundled for FixtureLibrarySource,
                             and CI seeds the same file into the simulator's Photos library
    Assets.xcassets          AppIcon
```

### Units and their contracts

**`VideoTitleFormatter`** — pure: `VideoItem` to the title ("Sun 23 Aug 2026, 14:05")
and subtitle (album name or "Photos") used everywhere a video is named, plus the
`durationLabel` ("1:02:03"). Unit tested.

**`VideoItem`** — value type the whole app passes around. `id` (Photos local identifier,
or a synthetic id for fixtures), `source` (`.photos(localIdentifier)` or `.file(URL)` for
fixtures and CI), `duration`, `creationDate`, `pixelSize`, `albumTitle?`. The `.file` case
exists so the player and screenshots work on a simulator with no Photos content; it is
never reachable from the real library.

**`LibrarySource`** (protocol) — `authorizationStatus`, `requestAccess()`,
`allVideos() -> [VideoItem]`, `albums() -> [AlbumItem]`, `videos(in: AlbumItem)`,
`thumbnail(for: VideoItem, size:) async -> UIImage?`, `playerItem(for: VideoItem) async
throws -> AVPlayerItem`, and a change stream. `PhotosLibrary` implements it over
PhotoKit (`PHAsset.fetchAssets(with: .video)`, `PHCachingImageManager`,
`PHImageManager.requestPlayerItem(forVideo:)` with network access allowed so iCloud-only
videos download on first play, `PHPhotoLibraryChangeObserver`). `FixtureLibrarySource`
returns bundled items for screenshots and tests.

**`PlaybackQueue`** — pure model, no AVFoundation. Ordered `[QueueEntry]` (each a
`VideoItem` with a stable UUID so the same video can be queued twice) and a current
index. Operations: `replace(with:startingAt:)`, `playNext(_:)` (insert after current),
`append(_:)`, `moveUpcoming(fromOffsets:toOffset:)`, `removeUpcoming(atOffsets:)`,
`jump(to:)`, `advance() -> VideoItem?`, `previous(elapsed:) -> PreviousAction` (`.restart`
when more than 3 s in or already at the head, `.item` otherwise, `.none` when empty),
`hasNext`, `hasPrevious`. Fully unit tested.

**`PlaybackEngine`** — `@MainActor @Observable`, owns the single `AVPlayer` for the app's
lifetime. Public surface: `load(queue:)`, `play()`, `pause()`, `toggle()`, `seek(to:)`,
`next()`, `previous()`, `setRate(_:)`, `setLoop(_:)`, `stop()`, and an observable
`PlaybackState` (current item, isPlaying, time, duration, rate, loop, buffering, error).
Internally: resolves `VideoItem -> AVPlayerItem` through the `LibrarySource`, prefetches the
next item's `AVPlayerItem` as soon as the current one starts, swaps at end with
`replaceCurrentItem`, applies `defaultRate` and `audioTimePitchAlgorithm = .timeDomain` to
every item, observes `AVPlayerItemDidPlayToEndTime`, drives `ResumePolicy` on load and
`PlaybackStore` on a 5 s timer plus pause/background/end/advance. It also watches the
player's `timeControlStatus`, because the system player's own transport buttons drive the
AVPlayer directly and the engine must follow (and publish to Now Playing and the store).
The engine itself is not unit tested; everything it decides with is.

**`PlayerHost`** — a UIKit `UIViewController` that owns the app's one
`AVPlayerViewController`, created once by `AppModel` and kept alive for the process
lifetime. Reason: PiP dies if the `AVPlayerViewController` is deallocated, and SwiftUI
`fullScreenCover` destroys its content on dismiss. The SwiftUI `PlayerScreen` embeds this
same host through a `UIViewControllerRepresentable` that reparents it, and returns it
unharmed when dismissed. PlayerHost also owns the AVKit delegate: PiP start/stop flags,
`restoreUserInterfaceForPictureInPictureStop` (asks `AppModel` to present the player
screen, then completes), and the background/foreground handling described under
Playback mechanics. `updatesNowPlayingInfoCenter = false`, `allowsPictureInPicturePlayback
= true`, `canStartPictureInPictureAutomaticallyFromInline = true`, `showsPlaybackControls =
true`, `speeds = []` (the system speed menu is hidden so Backdrop's own speed control is
the only one and stays in sync with the store and Now Playing).

**`NowPlayingController`** — the only thing that touches `MPNowPlayingInfoCenter` and
`MPRemoteCommandCenter`. `NowPlayingSnapshotBuilder` (core) is a pure function from (item,
queue, elapsed, duration, playing, speed) to a `NowPlayingSnapshot`, unit tested; the
controller maps the snapshot onto MediaPlayer keys and adds the artwork. Remote commands registered: play, pause,
togglePlayPause, nextTrack, previousTrack, changePlaybackPosition, changePlaybackRate
(rates 0.5–2). Skip-forward/backward stay disabled so the card shows previous/next.
`nextTrack`/`previousTrack` `isEnabled` follows the queue. Elapsed time is pushed on
play/pause/seek/rate/item change, not every tick — the system interpolates from the rate.

**`AudioSessionController`** — category `.playback`, mode `.moviePlayback`, no
mix-with-others. Activated on the first play. Stays active while paused so the Lock
Screen card stays up; deactivated with `notifyOthersOnDeactivation` only on explicit
stop. Handles interruption began/ended (pause; resume when `shouldResume`) and route change
`oldDeviceUnavailable` (pause — headphones pulled).

**`PlaybackStore`** — one Codable JSON file at
`Application Support/Backdrop/state.json`, atomic write-through on every change (it is a
few hundred bytes). Holds `positions: [videoId: seconds]`, `speed`, `loop`.
**`ResumePolicy`** — pure: a saved position under 5 s is ignored; a position within
`max(5 s, 5%)` of the end counts as finished and the video restarts from 0 and its entry
is dropped.

**`DiagnosticsLog`** — append-only text file in Application Support, flushed per line,
ring-trimmed to ~1 MB. Every playback transition, audio session event, PiP event, and
background/foreground event logs one line. `DiagnosticsView` shows it and offers the share
sheet, plus the two experiment switches listed under Risks.

**`AppModel`** — composition root. Creates `PhotosLibrary` (or the fixture source when
launched with `-fixtureLibrary YES`), `PlaybackEngine`, `PlayerHost`,
`NowPlayingController`, `AudioSessionController`, `PlaybackStore`, `DiagnosticsLog`.
Holds navigation state: `isPlayerPresented`, `isQueuePresented`, selected album. Reads
launch arguments (`-initialScreen library|player|queue|diagnostics|permission`,
`-fixtureLibrary YES`) for CI screenshots.

## Screens

All ours. Dark, Liquid Glass, motion that responds to the user — never a static list.

1. **Permission gate** — first launch. One glass card explaining the app reads Photos to
   play videos and nothing leaves the phone, one prominent glass button to grant. Denied
   state offers "Open Settings". Limited state shows the library with a "Manage selection"
   chip that presents `presentLimitedLibraryPicker`.
2. **Library** — full-bleed animated mesh-gradient background; a sticky glass album chip
   row (All, Favorites, then user albums with at least one video); a two-column grid of
   thumbnails with duration badge and date. Cells scale-in with a short stagger on first
   appear and respond to scroll with `scrollTransition` (subtle scale/opacity at edges).
   Tap plays: queue becomes the visible list starting at the tapped item, the player
   opens with the iOS 18+ zoom navigation transition from the cell. Long press: Play Next,
   Add to Queue. Pull-to-refresh re-fetches (and `PHPhotoLibraryChangeObserver` refreshes
   automatically).
3. **Player** — full screen cover. Portrait: our header (close chevron, "Now Playing"),
   the system player inline at the video's aspect ratio (capped at half the screen), then
   our glass controls below it: title/subtitle, previous · play/pause · next, and a chip
   row with Loop, Speed (menu of presets, shows current) and Queue (with count). Inline
   rather than AVKit's modal presentation keeps our controls clear of the system overlay
   and is what automatic PiP from inline is designed for. Landscape: the player edge to
   edge with only the close chevron. The system player's own speed menu is hidden.
4. **Mini-bar** — floats over the library bottom when the engine has an item: thumbnail,
   title, play/pause, a progress hairline; springs in and out. Tap reopens the player.
   Swipe down or an X stops playback and clears Now Playing.
5. **Queue sheet** — medium/large detent sheet: now playing at top, upcoming list with
   drag-to-reorder and swipe-to-remove. Tapping an upcoming item jumps to it.
6. **Diagnostics** — reached from a small gear on the library. Log viewer, share, and the
   experiment switches. Not styled beyond the theme; it is an instrument.

Titles: Photos videos have no meaningful name, so the title is the creation date formatted
like "Sat 23 Aug 2026, 14:05" and the subtitle is the album name when playing from an
album, otherwise "Photos". The same strings appear in the cell, the mini-bar, the overlay
and the Now Playing card.

## Playback mechanics

The two features the app exists for, and what makes each hold:

**PiP.** The system player handles PiP and the PiP button. With
`canStartPictureInPictureAutomaticallyFromInline` on and the player visible and playing,
swiping home starts PiP. Locking the phone while in PiP hides the window and keeps the
audio; unlocking brings it back. Tapping the PiP restore button calls the delegate, which
re-presents the player screen before completing.

**Background without PiP.** If PiP does not start (disabled in Settings, or the user closed
the PiP window, or the player screen was not on screen), AVFoundation pauses a player that
is rendering into a player view when the app backgrounds. PlayerHost therefore, on
`didEnterBackground`, detaches the player from the `AVPlayerViewController`
(`player = nil`) unless PiP is active, and reattaches on `willEnterForeground`. Audio then
continues through the active playback session. Whether the detach is actually required
with today's AVKit is one of the on-device experiments (switch in Diagnostics); the code
ships with detach on.

**Auto-next in the background.** A silent app in the background is one iOS may suspend, so
the gap between videos must be near zero: the next `AVPlayerItem` is requested as soon as
the current one starts playing and is swapped in with `replaceCurrentItem` at end, then
`play()`. If the prefetch has not finished (iCloud download), the engine waits on it with
the session still active; this is logged.

**Loop** beats auto-next: at end, seek to zero and play. **Speed** is set through
`defaultRate` so resuming after a pause keeps it, and mirrored into Now Playing's
`defaultPlaybackRate`/`playbackRate`. **Remember position** is saved through
`PlaybackStore` and applied on load through `ResumePolicy`.

**Previous** from the Lock Screen or the overlay restarts the current video when more than
3 s in, otherwise goes to the previous queue item.

**Stop** (mini-bar X or swipe-down) pauses, saves the position, detaches the player,
clears Now Playing, deactivates the session and empties the queue. The mini-bar goes away;
the library is one tap from starting again.

## Error handling

- Photos denied/restricted: permission gate state, never a crash, no empty grid pretending
  to be a library.
- `requestPlayerItem` fails or returns nil (asset deleted, iCloud unreachable): engine
  logs, surfaces the message under the title on the player screen, and advances to the
  next item if there is one; otherwise stays on the item, paused.
- Audio session activation fails: logged, playback still attempted (it will be silent in
  the background, which the log will show).
- Store read failure: start with empty state and log; never block launch on it.
- Every error path writes to `DiagnosticsLog`.

## Data

`state.json` and `diagnostics.log` in Application Support only. No App Group, no iCloud,
no network. Position keys are Photos local identifiers, which are stable across launches
on the same device. Entries are tiny; no eviction in v1. The log is trimmed at 1 MB.

## Pipeline and verification

**GitHub Actions** (`.github/workflows/ios-compile.yml`, public repo, free macOS minutes):
install XcodeGen, generate, build unsigned for a simulator, run the unit tests, seed the
simulator Photos library with `ios/Sources/App/Fixtures/sample.mp4` via `simctl addmedia`,
grant `photos` permission, launch the app once per `-initialScreen` value and screenshot,
collect crash reports, upload the screenshots as an artifact. The core package's tests run
first with `swift test`. Real-library launches use the seeded
video; fixture launches (`-fixtureLibrary YES`) use the bundled item so the player screen
renders deterministically.

**Codemagic** (`codemagic.yaml`): a copy of NextStop's signed workflow with Backdrop's
names — `mac_mini_m2`, `xcode: latest`, triggered on push to `main` with
`cancel_previous_builds`, changeset-gated to `ios/` and the yaml, XcodeGen, certificate from
`CERT_KEY_B64` in the `code_signing` group, `app-store-connect fetch-signing-files
com.kaichuan.backdrop --type IOS_APP_STORE --create`, `xcode-project use-profiles`,
`build-ipa`, publish to App Store Connect with the existing integration, internal
TestFlight only.

**Unit tests** (Swift Testing, in `core/`, run locally and on every push):
`PlaybackQueueTests` (advance/previous/insert/move/remove/edges), `ResumePolicyTests`
(ignore-short, finished-window, exact edges), `PlaybackStoreTests` (round trip, nil
removes, corrupt file, unwritable path), `NowPlayingSnapshotTests` (rate while paused,
duration fallback, clamping, queue count/index), `VideoTitleFormatterTests`,
`DiagnosticsLogTests` (timestamp format, append, clear, trim on a line boundary).

**Device checklist** (owner, after TestFlight install):

1. Grant Photos access, see the library, tap a video, it plays.
2. Swipe home while playing → PiP appears and keeps playing.
3. Lock the phone during PiP → audio continues; Lock Screen shows the card with thumbnail,
   title and a moving timeline; the Dynamic Island shows the compact player.
4. From the Lock Screen: scrub, pause, play, next, previous — each lands in the app.
5. Close the PiP window (not the app) → audio continues.
6. Toggle the detach experiment off in Diagnostics, repeat step 5; report which holds.
7. Let a video end while locked → the next one starts without reopening the app.
8. Loop on → the same video restarts at end. Speed 1.5x → voice pitch unchanged; lock and
   unlock → still 1.5x.
9. Kill and relaunch the app, play the same video → resumes near where it was left.
10. Share the Diagnostics log back if anything in 2–9 fails.

**Owner setup before the first signed build:** create the App Store Connect app record
for `com.kaichuan.backdrop` (if the name "Backdrop" is taken on App Store Connect, the
record can be called "Backdrop Player" — the name on the phone stays Backdrop); add the
GitHub repo as an app in Codemagic and confirm the `NextStop ASC key` integration and the
`code_signing` environment group are available to it; add yourself as an internal tester
on the new app.

## Design language

Tokens in `Theme.swift`: background gradient stops, glass tint, accent, text on glass,
radii, spacing, spring parameters. Nothing hard-coded in views. Liquid Glass via
`.glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glass)` /
`.buttonStyle(.glassProminent)`. Motion: springs from the tokens, `scrollTransition` on
grid cells, zoom navigation transition into the player, mini-bar spring, haptics on
play/pause/next. `accessibilityReduceMotion` turns the stagger and the background motion
off.

## Risks and what answers them

| Risk | How it is answered |
| --- | --- |
| Auto-PiP does not start from our embedding | Device step 2. Fallback: present the player host modally (full screen) instead of inside a SwiftUI cover — AVKit's full-screen presentation always auto-PiPs. |
| Background audio stops without PiP | Device steps 5–6 with the detach switch. Fallback is the detach, which is the documented pattern. |
| Detach races PiP start | PlayerHost only detaches when the delegate has not reported PiP starting; logged either way. |
| App suspended between videos in background | Prefetch keeps the gap near zero; the log shows `gap` lines if it happens. |
| `@Observable`/`@MainActor` traps in Swift 5 mode (NextStop: default-arg isolation, no static stored props on generic types) | Known; kept in mind during implementation. |
| Codemagic signing for a second app | Same certificate, new bundle id created by `fetch-signing-files --create`; the ASC app record is the one manual step. |
