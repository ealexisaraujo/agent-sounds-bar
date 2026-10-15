# Architecture

How the pieces fit together. Last verified 10-14-2026.

## Goal
Agent hooks (Claude Code, Codex, others) played sounds with a hardcoded `afplay <file>`, so there was no volume control and changing a sound meant editing JSON. This project puts one shared config in the middle and a menu bar app on top of it.

## Data flow
```
agent hook ──> play-sound <event> ──reads──> ~/.config/agent-sounds/config.json <──writes── menu bar app
                    │                                                                          │
                    ├─> afplay -v <volume> <sound>                                  previews call afplay directly
                    └─> appends a line to history.log ──────────────read by────────────────────┘
```
`config.json` is the only contract between hooks and app. The app does not need to be running for sounds to play.

## Runtime files (`~/.config/agent-sounds/`, outside the repo)
| Path | Purpose |
|---|---|
| `bin/play-sound` | Installed copy of `scripts/play-sound` (versioned by a `# agent-sounds-cli-version: N` header; the app refreshes it at launch when it ships a newer one) |
| `config.json` | `{ muted, volume, events: { <event>: { enabled, sound } } }` |
| `sounds/` | Selectable sound files (.wav .mp3 .aiff .m4a .caf) |
| `history.log` | TSV: `epoch  event  result  sound  agent`, capped around 200 lines |
| `connections.json` | What the app replaced in each agent's hook file, so Disconnect can restore it |

Events: `session_start`, `user_prompt_submit`, `stop`, `stop_error`, `notification`.
Results: `played`, `muted`, `disabled`, `zero_volume`, `missing_file`.

## play-sound (`scripts/play-sound`)
Bash plus `jq`. For `stop` it reads the hook JSON from stdin and greps the last 50 transcript lines for `overloaded_error|rate_limit_error|"status":429|"status":529|too_many_requests`; a match switches the event to `stop_error`. Falls back to built-in default sounds when config is missing or corrupt. Clamps volume to 0..1. Always exits 0. `AGENT_SOUNDS_AGENT=<claude|codex>` (set in the hook command) is recorded in the history log. Env overrides for tests: `AGENT_SOUNDS_HOME`, `AGENT_SOUNDS_PLAYER`.

## Menu bar app (`Sources/AgentSoundsBar/`, SwiftUI, SPM executable)
| File | Role |
|---|---|
| `App.swift` | `MenuBarExtra` (window style) with the equalizer icon, a `Window` scene with id `config`, and the `AppDelegate` adaptor |
| `ConfigStore.swift` | `SoundConfig` model, `SoundEvent` list, `Paths`, atomic save, directory watcher that reloads hand edits |
| `ActivityStore.swift` | Polls `history.log` every 0.4 s, drives the icon animation, also holds `EqualizerIcon` (the menu bar NSImage) |
| `AgentWiring.swift` | Read-only scan of each agent's hook file into an `AgentState` (`notInstalled`, `notConnected`, `connected`, `drifted`) with per-hook status |
| `JSONTextEditor.swift` | Edits JSON as text (insert first child, replace a string, remove a child) so untouched bytes stay identical |
| `HookConnector.swift` | `AgentSpec`, `planConnect` / `planDisconnect` / `apply`, command classification, line diff, `connections.json` records |
| `SetupInstaller.swift` | `status()` (`notInstalled`/`outdated`/`ready`), `install()` with per-step results, silent CLI upgrade |
| `CLI.swift`, `Entry.swift` | Command line mode of the same binary (`setup`, `status`, `connect`, `disconnect`); `Entry` is the only `@main` |
| `AppEnvironment.swift` | Shared stores, `SetupModel` (UI-facing install/connect state), `AppDelegate` (launch upkeep, first-run wizard), wizard window |
| `OnboardingView.swift`, `SetupCard.swift` | The five-step wizard; the popover Setup card, `AgentCard`, `OtherAgentsView` |
| `SoundLibrary.swift` | Lists sound files, `add`/`addViaPanel` (copy a chosen file in, never overwriting), `Previewer` (afplay, ignores mute so sounds can be auditioned) |
| `Theme.swift` | Glass helpers with macOS < 26 fallback, `AuroraBackground`, `GlassSlider`, `GlassSwitch`, `Waveform`, `RelativeTime`, per-event symbol and accent |
| `MenuView.swift` | The popover: header, volume card, event tiles, last activity, footer |
| `ConfigWindow.swift` | Four tabs: Overview, Events, Agents, Activity |

`ConfigStore`, `ActivityStore` and `SetupModel` are `@Observable` and live in the `AppEnvironment` singleton, so the SwiftUI scenes and the AppKit side (delegate, wizard window) share one instance of each.

## Packaging and scripts
- `build.sh`: builds `build/AgentSoundsBar.app` and bundles `scripts/play-sound` and `Resources/sounds/*.wav` into `Contents/Resources`, so the app installs everything the hooks need without a repo checkout. Ad-hoc codesign.
- App icon (added 10-14-2026): source is `Resources/AppIcon.icon` (Icon Composer bundle: `icon.json` holds the pink-to-violet gradient, glass and shadow settings; `Assets/` holds three glyph layers: speaker, waves, gold spark). `scripts/draw-icon-layers.swift` regenerates the layer PNGs. `build.sh` compiles the bundle with `actool` into `Contents/Resources/Assets.car` (Liquid Glass, macOS 26) and `AppIcon.icns` (flattened fallback, up to 256 px), and sets `CFBundleIconFile`/`CFBundleIconName`.
- The app's own command line (`AgentSoundsBar setup | status | connect <agent|all> | disconnect <agent|all> [--dry-run]`) is the single implementation of install and hook wiring. `scripts/install.sh` and `scripts/uninstall.sh` are thin wrappers over it. `scripts/rewire-hooks.py` was removed.
- Tests: `swift test` (20 XCTests: connector, JSON editing round trips, installer) and `tests/test-play-sound.sh` (17 shell tests with a fake player).

## Current live state (this machine, 10-14-2026)
Claude Code and Codex sound hooks both call `play-sound` (commands written by the first version, without the `AGENT_SOUNDS_AGENT` tag; the app would update them if Connect or Reconnect is pressed). Codex has no Notification sound hook. Default volume is 0.6 (previously full volume). See the onboarding topic file for the first-run flow.

## Update 10-15-2026: public release
- Sounds: the app bundles no audio. Defaults are macOS system sounds by absolute path (`SoundLibrary.system("Glass")` -> `/System/Library/Sounds/Glass.aiff`), mirrored in `play-sound` (CLI version 3). `SoundLibrary.available()` returns the user's folder (file names) followed by the system sounds (absolute paths); `display()` strips folder and extension. `build.sh` copies `Resources/sounds` only if the folder exists.
- New files: `Updates.swift` (channels, version comparison, GitHub Releases check, Homebrew upgrade), `UpdateCard.swift` (popover banner and gear-menu items). `UpdateChecker` joins `AppEnvironment`; `AppDelegate` calls `updates.start()`.
- Versioning, signing, release script, cask and update flow: see `ctx-10-15-2026-release.md`.
