# Implementation record: onboarding and self-contained install

How the first-run work was built, how each part was verified, and what is still open. This is the "how it was done and what we know" companion to the other topic files: see `architecture` for the module map, `decisions` for the why, `onboarding` for the user-facing flow, and `warnings` for fragile spots. Written 10-14-2026.

## Outcome
Before: the app only worked on the author's machine. `play-sound`, the sounds and the hook wiring came from `scripts/install.sh` in a repo checkout, and wiring could only replace existing `afplay` commands. A new user got silence and an empty sound picker.

After: the `.app` carries everything. First launch opens a wizard that installs, connects Claude Code and Codex (adding hooks where none exist), and confirms a real event arrives. Every empty state in the popover points at the next step. The same logic is available from the app's command line, which the tests and the install scripts use.

## Commits
| Commit | What |
|---|---|
| `512cc9f` | First version: `play-sound`, menu bar app, install scripts |
| `9ec3bab` | Liquid Glass popover redesign |
| `640b301` | `CLAUDE.md` and the first `.context` files |
| `b755909` | Onboarding, self-contained install, empty states, CLI mode, Swift connector |
| `4e79525` | Docs for the above |
| `4226039` | Wizard window ordered to the front at launch (found on the real run) |
| `e0cb39b` | Accessibility labels and a readable change list (found while driving the real UI) |

## Key mechanisms

### JSON is edited as text (`JSONTextEditor.swift`)
Agent hook files are also written by plugins and tools (Orca, GitKraken, Claude Code itself), so re-serializing them would reorder keys and rewrite whitespace. Instead a small scanner finds byte ranges and edits text. Invariants worth keeping:
- **New children are inserted first** (right after the opening bracket). That avoids trailing-comma handling, and `removeChild` is the exact inverse, so connect then disconnect is byte-identical when the file only gained our hooks.
- Removal rules: only child -> empty the container; first child -> remove through its comma; any later child -> remove from the previous child's end through its own end.
- Indent unit is detected from the file (two spaces by default); nested JSON we generate is rendered from a tiny `JNode` tree at the host indent.
- Scanning is a full recursive walk of the file per edit step, which is fine at the 46 KB size of a real `settings.json`.

### Connect is a loop of single edits (`HookConnector.planConnect`)
`connectStep` makes at most one edit and returns true; the caller re-scans the new text and repeats until it returns false (cap of 40). This keeps offsets valid without tracking shifts. Per spec hook it: finds the event array (or creates it, or the whole `hooks` object, or the whole file), classifies each existing command, and either leaves ours, updates an older play-sound command (for example to add the agent tag), takes over a recognized legacy command (recording the original in `connections.json`), or inserts a new group. Commands that play their own sound are kept and reported as a warning.
Safety net after the loop: the result must parse, and every pre-existing command that was not deliberately replaced must still be present, otherwise nothing is written.

### Disconnect (`planDisconnect`)
Restores recorded originals; otherwise removes our hook element, then removes the event key if its array ended up empty, then the `hooks` object if it did. Cleanup only runs after we changed something, so a file with a pre-existing empty array is reported as "nothing to change".

### Apply (`HookConnector.apply`)
Writes a `<file>.bak-agent-sounds-<timestamp>` copy first (a numeric suffix is added if one exists in the same second, a bug the tests caught), preserves file permissions (Codex's `hooks.json` is mode 600), writes atomically, then updates `connections.json`.

### State model (`AgentWiring.swift`)
`notInstalled` (no config dir or file), `notConnected`, `connected` (every spec hook calls play-sound), `drifted` (some do, or a `connections.json` record exists but none do). "Drifted" is how an overwrite by another tool is noticed.

### Install and upgrade (`SetupInstaller.swift`)
`install()` is idempotent and returns one `StepResult` per step. `play-sound` carries `# agent-sounds-cli-version: N`; `AppDelegate` calls `updateCLIIfNeeded()` at launch, so a newer app silently upgrades the installed script. Existing config and sounds are never overwritten.

### Launch decision (`AppDelegate`)
Not installed -> wizard at Welcome. Installed but wizard never completed: agents present and none connected -> wizard at Connect; otherwise mark completed silently (so already-configured machines never see it).

### Wizard attribution
Hook commands are written as `AGENT_SOUNDS_AGENT=<agent> .../play-sound <event>`; `play-sound` logs the agent as the fifth field. The Test step uses it to tick each agent.

## Test matrix
| Suite | Count | Covers |
|---|---|---|
| `swift test` HookConnectorTests | 14 | create file, `{}` and compact JSON, add `hooks` and keep the rest byte for byte, keep other hooks and round-trip byte-identical, replace legacy and restore on disconnect, idempotence, update older play-sound command, refuse invalid JSON, keep and warn on other sound hooks, four-space indent and 0600 permissions, backup created, drift detection, agent not installed, disconnect on an untouched file is a no-op |
| `swift test` SetupInstallerTests | 6 | fresh install, audio-only copy and default config, reinstall keeps user settings and sounds, silent script upgrade, missing resources fail clearly, Add sound never overwrites |
| `tests/test-play-sound.sh` | 17 | volume, mute, disable, clamping, corrupt config, rate-limit transcript, history log fields, log trimming |
Tests isolate themselves with `AGENT_SOUNDS_HOME` and `AGENT_SOUNDS_USER_HOME`; none touch real files or speakers.

## Verification log (what was checked, how, result)
| When | Method | Result |
|---|---|---|
| After connector | `swift test` | 10 of 14 failed: duplicate backup names within one second. Fixed, then 14/14 |
| After CLI mode | Fresh-machine simulation through the built binary with temp homes (status, refuse connect before setup, setup, connect all, run the written Stop command with a fake player, disconnect) | Connect created `settings.json`, the command played the bundled sound at 0.6 and logged `agent=claude`, disconnect left `{}`; Codex skipped as not installed |
| Before touching real files | `connect --dry-run` against the real hook files | Only agent-tag updates on 4 Claude and 3 Codex commands |
| UI states | Real views hosted in a throwaway window on scratch homes, captured by window id | Welcome, Install, Connect (before and after), Test, Done, popover not-set-up, no-agent, reset, connected |
| Real account | Backup verified identical, disconnect (7 commands removed, all others and other top-level keys unchanged), settings folder to Trash, flag reset, relaunch | State read `notInstalled`/`notConnected` as intended. First launch exposed the wizard opening behind other windows |
| Real account, GUI driven | Orca computer-use against the live app (by pid) through all five steps | Install, both Connects (backups, valid JSON), Finish set the completion flag. Exposed unlabeled buttons and the hard-to-read diff |
| Real events | `history.log` after the run | 13:34:37 `stop` and 13:34:46 `user_prompt_submit`, both `agent=claude`, not created by any command of ours: the connected hooks fire in a live session and Claude Code picked up the changed hooks without a restart |

## Known gaps (as of 10-14-2026)
- Codex has no real event yet (only the simulated one); its re-approval behaviour after a hook change is unobserved.
- SessionStart and Notification have not fired for real (this session predates the hooks; Notification needs a permission prompt).
- No run on a brand-new macOS user; macOS 14 (no `/usr/bin/jq`) untried.
- Launch at login and the 25-second "nothing yet" hint were not exercised.
- Config window tabs other than Overview were not screenshotted.
- Gemini, Cursor and opencode are copy-paste only; their formats are unverified.
- The bundled Peon sounds are Warcraft audio: private use only.
- The menu bar icon was confirmed visible in the author's bar after the real run (it had been hidden by crowding earlier), but only on this machine.

## How to extend
- **Add an agent:** add an `AgentSpec` in `HookConnector.swift` (config dir, hook file, hook-to-event map). If its file is not JSON shaped like `{"hooks": {Event: [{"hooks": [{"command": ...}]}]}}`, the text editor needs a new writer; do not force it through this one. Add fixtures to `HookConnectorTests`.
- **Add an event:** a `SoundEvent` in `ConfigStore.swift` (key, copy, default, hook), a `case` in `scripts/play-sound`, a default in `SoundConfig.defaults`, a symbol and accent in `Theme.swift`, tests, and bump the script's version header.
- **Change the starter sounds:** replace `Resources/sounds/*.wav` (names are referenced by `SoundEvent.defaultSound` and the script's defaults).

## Gotchas for the next session
- `tests/` (lowercase) holds both the shell test and the Swift test target. macOS is case-insensitive, so `Tests/` silently resolves to it; keep `Package.swift` lowercase for case-sensitive checkouts.
- The app has no Dock icon: find it with `pgrep -x AgentSoundsBar` and `orca computer ... --app pid:<pid>`; `list-apps` will not show it. The GUI tool's tree does not print accessibility labels, only values; use the Accessibility API for labels.
- Windows opened at launch must call `orderFrontRegardless()` or they can appear behind other apps.
- SwiftUI animations make an immediate screenshot after a click unreliable (the diff first looked overlapped); wait about a second.
- The author's pre-test backup is `~/agent-sounds-backup-20261014-132733/` with a `RESTORE.md`; per-write backups sit beside each hook file as `*.bak-agent-sounds-*`.
