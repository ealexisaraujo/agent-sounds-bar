# Agent Sounds Bar

macOS menu bar app that controls the sounds played by agent hooks (Claude Code, Codex, others): master volume, mute, and the sound for each event. Hooks call a shared `play-sound` script that reads `~/.config/agent-sounds/config.json`; the SwiftUI app edits that file.

## Context folder
Project knowledge lives in `.context/`, split by topic. Read the relevant file before changing the area it covers.

- `ctx-<mm>-<dd>-<yyyy>-architecture.md`: how the pieces fit, files, data flow
- `ctx-<mm>-<dd>-<yyyy>-decisions.md`: what was chosen and rejected, and why
- `ctx-<mm>-<dd>-<yyyy>-warnings.md`: fragile spots, unverified items, live files this touches
- `ctx-<mm>-<dd>-<yyyy>-onboarding.md`: first-run flow, empty states, how to simulate a new user
- `ctx-<mm>-<dd>-<yyyy>-implementation.md`: how the onboarding work was built, verification log, known gaps, how to extend
- `ctx-<mm>-<dd>-<yyyy>-release.md`: versioning, signing, notarization, GitHub releases, Homebrew tap, in-app updates

**Naming convention (always):** `ctx-mm-dd-yyyy-{topic}.md`, for example `ctx-10-14-2026-architecture.md`. When a topic changes materially, add a new dated file for that topic (or append a dated entry) instead of silently rewriting history, and update the other topics it affects. Add new topics the same way (for example `-testing`, `-roadmap`).

## Commands
```bash
swift build -c release                         # compile
swift test                                     # 30 XCTests: hook connector, JSON editing, installer, updates
tests/test-play-sound.sh                       # 17 shell tests, silent, uses a temp home
./build.sh                                     # build build/AgentSoundsBar.app (bundles play-sound + icon)
UNIVERSAL=1 ./build.sh                         # arm64 + x86_64 (SIGN_IDENTITY=... for Developer ID)
pkill -x AgentSoundsBar; open build/AgentSoundsBar.app   # (re)launch
APP=build/AgentSoundsBar.app/Contents/MacOS/AgentSoundsBar
$APP status                                    # setup + per-agent state
$APP setup [--dry-run]                         # install CLI and default config
$APP connect claude|codex|all --dry-run        # preview hook changes, writes nothing
$APP disconnect all --dry-run                  # preview removal
$APP version; $APP check-update [--beta]       # exit 10 when an update exists
./scripts/install.sh / uninstall.sh            # thin wrappers over the same commands
scripts/release.sh build | publish             # release (see the release doc); publish is public
```

## Layout
- `scripts/play-sound`: the CLI every hook runs. Bash + jq. Source of truth; `build.sh` bundles it into the app and the app installs it to `~/.config/agent-sounds/bin/`. Bump its `agent-sounds-cli-version` header when you change it so installed copies upgrade.
- `Sources/AgentSoundsBar/`: the SwiftUI app and its command line mode (see the architecture doc for per-file roles).
- `Resources/AppIcon.icon`: app icon source (Icon Composer bundle). `swift scripts/draw-icon-layers.swift` redraws its layers; `build.sh` compiles it with `actool` (needs Xcode).
- Sounds: none are bundled. Defaults are macOS system sounds by absolute path (`/System/Library/Sounds`). Never add third-party audio to the repo; it is public and MIT.
- `VERSION`, `CHANGELOG.md`: the release version and its notes. `packaging/homebrew/`: the cask template for `ealexisaraujo/homebrew-tap`.
- `docs/assets/`: README images (icon, popover capture from the window harness).
- `tests/AgentSoundsBarTests/`, `tests/test-play-sound.sh`: Swift and shell tests.
- `.context/`: project context docs.

## Rules
- **Never change the user's live hook files** (`~/.claude/settings.json`, `~/.codex/hooks.json`) without a `--dry-run` first and explicit approval. Codex pins a `trusted_hash` per hook, so changing its hooks can trigger re-approval.
- **`play-sound` must always exit 0 and stay fast.** A broken sound must never break an agent. Keep the exit-0 behavior and the existing tests passing.
- **Experiment safely:** set `AGENT_SOUNDS_HOME` to a temp directory and `AGENT_SOUNDS_PLAYER` to a fake player (such as `/usr/bin/true`). Both the script and the app honor them, so the real config and speakers stay untouched.
- After editing `scripts/play-sound`, bump its version header, run `./build.sh` and relaunch the app (it upgrades the installed copy at launch), then run both test suites.
- Hook files are edited as text by `JSONTextEditor`/`HookConnector`, never re-serialized. Keep the safety checks (result must parse, no unrelated command may disappear) and the byte-identical connect/disconnect round-trip tests passing.
- Use `AGENT_SOUNDS_USER_HOME` (and `AGENT_SOUNDS_RESOURCES` when running the binary outside an `.app`) alongside the other overrides to simulate a new user without touching real agent files.
- The config format is shared by the script and the app (`SoundConfig` in `ConfigStore.swift`). Change both together, keep decoding lenient, and update the architecture doc.
- UI uses Liquid Glass through the helpers in `Theme.swift` (`glassCard`, `glassCapsule`, `glassCircle`) so the pre-macOS 26 fallback keeps working. Do not call `glassEffect` directly in views.
- To look at UI changes, host the real views in a throwaway `NSWindow` harness outside the repo and capture it with `screencapture -l <windowID>`. Do not add debug flags to the shipped app. Say plainly what was and was not visually verified.
- Use `python3 -I` for Python that reads files you did not write.
- **Publishing is outward-facing:** pushing to GitHub, `scripts/release.sh publish` and tap pushes need explicit approval each time. Never push the local `private-history` branch (it contains the Peon audio).

## Git
- Branch: `main`, public at `github.com/ealexisaraujo/agent-sounds-bar`. Commit only when asked.
- End commit messages with `Co-Authored-By: Claude <noreply@anthropic.com>`.
- `build/`, `dist/`, `.build/` and `.serena/` are ignored.
