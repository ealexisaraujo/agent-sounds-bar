# Decisions

What was chosen, what was rejected, and why. Add new entries at the bottom with a date; do not rewrite history, supersede it.

## 10-14-2026

### Native SwiftUI `MenuBarExtra` app
Chosen by the user over SwiftBar/xbar and Python `rumps`. Reasons: a real volume slider and per-event pickers, native look, no extra dependencies. Swift 6.3 and Xcode were already installed. SwiftBar was not installed and its menus cannot hold a slider.

### Global volume, per-event sound (not per-agent)
One master volume and mute, plus an enabled flag and a sound for each event. The same settings apply to Claude, Codex and any other agent. Per-agent settings were offered and declined as a bigger UI and config for little gain.

### One shared config file is the only contract
Hooks read `config.json`; the app writes it. They never talk to each other, so sounds work with the app closed and any agent can join by running `play-sound <event>`.

### `play-sound` is bash + jq
The existing hooks already used bash, jq and afplay, so no new runtime is needed. Chosen over a Swift CLI for startup speed and ease of editing.

### Volume via `afplay -v`
No extra audio tooling. Volume is clamped to 0..1 even though afplay allows more.

### `stop_error` is a config event, not a hook
The old `stop-sound.sh` picked a different sound on rate-limit errors. That logic moved into `play-sound`, and the alternate sound became a configurable event.

### Rewire hook files as text, not by re-serializing JSON
`rewire-hooks.py` does targeted regex replacement and then validates. Re-serializing with jq or Python would reformat the whole file and fight with plugins and Orca that also write `settings.json`. After editing it checks the JSON parses and that only `"command"` values differ.

### Revert by reversing commands, not restoring a backup
Restoring a backup would discard changes other tools made to the hook files after the rewire. Backups still exist as a safety net.

### Sounds are copied, not moved
Originals stay in `~/.claude/hooks` and `~/.codex/hooks`. The old `stop-sound.sh` copies also stay until the user decides to delete them.

### Both agents were rewired
Claude first, then Codex after the user said yes, knowing Codex may ask to re-approve changed hooks (see warnings).

### Menu bar icon is a custom drawn equalizer
Four bars drawn into a template `NSImage`. Rest height follows volume, bars dance while a sound plays, and a slash shows when muted. The user asked for "another animated icon"; a drawn image gives a distinctive look and full control of every frame. SF Symbol effects inside a `MenuBarExtra` label were not tried, so there is no evidence either way on whether they would animate there.

### History log plus polling to drive animation
The app cannot otherwise know when a hook played a sound. `play-sound` appends to `history.log`; the app polls its size and mtime every 0.4 s. A directory watcher is not enough because appending to an existing file does not fire directory events. The log also powers the Activity tab and the "why was it silent" explanations.

### Liquid Glass with a material fallback
Real `glassEffect` on macOS 26 (the target machine), `ultraThinMaterial` plus a hairline stroke on older systems. Package deployment target stays macOS 14.

### Design reference
CleanMyMac's menu bar popover (structure, cards, hero tile, footer) for layout, and WalltTune for a clean native card look. WalltTune's page gave little concrete detail, so most styling is from the CleanMyMac screenshot.

### SPM executable, no Xcode project
`build.sh` assembles the `.app` by hand with an `Info.plist` and an ad-hoc signature. Keeps the repo small and diffs readable.

### Default volume 0.6
New config starts at 60%. This is quieter than the previous full volume on purpose, so there is room to go up.

### Verification harness lives outside the repo
To look at the UI, the real views are compiled with a throwaway `main.swift` that hosts them in an `NSWindow`, then captured with `screencapture -l`. Not shipped. A `--render` flag was avoided so the app carries no debug code.

## 10-14-2026: onboarding and self-contained install

### The app installs itself
Setup no longer depends on a repo checkout. `play-sound` and the sounds ship in the bundle and `SetupInstaller` copies them. Chosen because a new user who only has the `.app` otherwise gets silence and an empty picker.

### Swift replaces `rewire-hooks.py`
One implementation (`HookConnector`), because a user may have no Python and two implementations drift. `install.sh` / `uninstall.sh` stay only as thin wrappers over the app's command line, which also makes the whole flow testable without the GUI.

### Connect adds hooks as well as replacing them
A fresh agent has no sound hooks, so replace-only was useless to a new user. New hook groups are inserted as the first element so a later Disconnect can remove them and restore the file byte for byte.

### Text-level JSON editing stays
Same reasoning as before (do not reformat files other tools also write), now implemented by `JSONTextEditor`. After every edit the result must parse and every command that was not deliberately replaced must still be present, otherwise nothing is written.

### Auto-connect only Claude Code and Codex
Chosen by the user. Gemini, Cursor and opencode have different hook formats (seen only in web search summaries, never verified), so they get copy-paste commands.

### Bundle the Peon sounds
Chosen by the user over macOS system sounds, after being told these are Warcraft audio and only suitable for personal use. Kept in one folder (`Resources/sounds/`) so swapping is a one-folder change. System sounds (`/System/Library/Sounds`, 14 `.aiff` files, `play-sound` already accepts absolute paths) remain the obvious alternative if this is ever shared.

### Agent tag in the hook command
Hooks are written as `AGENT_SOUNDS_AGENT=<agent> .../play-sound <event>` and `play-sound` logs it as a fifth field. This lets the Test step confirm per agent that a real event arrived, and the Activity tab say who fired.

### First-launch wizard plus popover Setup card
Chosen by the user. The wizard is hosted by an `AppDelegate` (works on macOS 14 and opens without the popover). Already-configured machines are detected and skip the wizard.

### App icon as an Icon Composer `.icon`, compiled at build time (10-14-2026)
The user asked for an icon following big-company guidelines, with CleanMyMac as the inspiration. The icon follows Apple's macOS 26 icon rules: layered glyphs on a system squircle with Liquid Glass, and it reuses the menu bar's `speaker.wave.2.fill` metaphor so the two read as one brand. The vivid gradient is the CleanMyMac influence, and the gold spark stands for "agent". The layers are drawn in code rather than as hand-made PNGs, so the geometry is reviewable and reproducible. A hand-built `.icns` was rejected because macOS 26 puts icons that don't follow the new format inside a gray squircle; `actool` produces both formats from one source. Compiled outputs are not committed: `build.sh` builds them, and without Xcode it builds the app with no icon.

### The existing hooks on this machine were deliberately not re-tagged
A dry-run showed the only difference would be adding the agent tag to the 4 Claude and 3 Codex commands. Applying it would change Codex commands again and may trigger another re-approval for no functional gain, so it is left for the user to apply (Reconnect).

## 10-15-2026: first public release

### macOS system sounds replace the Peon sounds
Chosen by the user. The Warcraft audio can't ship in a public MIT repo or app, and it was in git history, so the public repo starts from a fresh history without it. System sounds are played in place from `/System/Library/Sounds`, never copied or bundled. Existing installs keep their saved choices and their copied files.

### GitHub Releases checker instead of Sparkle
Chosen by the user. CodexBar turns Sparkle off for Homebrew and unsigned builds and updates those through brew instead; Homebrew is the main channel here, so the brew path was built first with no dependency or EdDSA keys. Stable and Beta channels map to GitHub's prerelease flag.

### Developer ID signing and notarization, done locally
The user has a paid Developer account, and a Developer ID Application certificate is in the keychain. The release script runs locally (as CodexBar's sign-and-notarize does) so no certificate has to be exported to CI. CI only builds and tests.

### Version 1.0.0, repo `agent-sounds-bar`, personal tap
Chosen by the user. The tap is `ealexisaraujo/homebrew-tap` so further casks can join it.

### No `uninstall quit:` in the cask
The app runs `brew upgrade` as a child process and relaunches itself afterwards. If the cask told brew to quit the app, the upgrade would finish with nothing left to relaunch it.
