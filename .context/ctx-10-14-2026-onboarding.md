# Onboarding and empty states

How a new user gets from "app downloaded" to "sounds play", and what every empty state shows. Last verified 10-14-2026 (screenshots of each state in a throwaway window harness; see warnings for what was not clicked through).

## Self-contained app
The `.app` carries `play-sound` and the five starter sounds in `Contents/Resources`. Nothing from the repo is needed at runtime. The starter sounds are the Peon (Warcraft) files the author already used; see warnings.

## Launch behavior (`AppDelegate`)
1. `SetupModel.selfHeal()`: if the bundled `play-sound` version is newer than the installed one, replace it silently.
2. Not installed -> open the wizard at Welcome.
3. Installed, wizard never completed: if there are installed agents but none connected -> wizard at Connect; otherwise mark completed silently (so an already-configured machine never sees the wizard).
`onboardingCompleted` lives in UserDefaults (`local.agent-sounds-bar`).

## Wizard steps
1. Welcome. 2. Install (animated checklist from `SetupInstaller.install()`, retry on failure, blocks if `jq` is missing). 3. Connect (an `AgentCard` per agent: state, per-hook status, "Will add N hooks", exact diff on demand, Connect/Reconnect/Disconnect, backup name; plus copy-paste commands for other agents). 4. Test (preview each event; live "Heard from <agent>" from `history.log` using the agent tag; hint after 25 s). 5. Done (icon tips, launch at login).
Reopen it from the popover gear menu ("Set up again...") or the Agents tab.

## Empty and edge states
| State | Where it shows | What the user sees |
|---|---|---|
| `play-sound` not installed | Popover | "Finish setup" card, title says "Not set up", controls dimmed and disabled |
| Installed, no agent connected | Popover | "Connect your agents" card |
| Agent hooks wiped by another tool | Popover | "<Agent> was reset" card with Reconnect (one click, no wizard) |
| Agent not installed | Wizard, Agents tab | Card says so, no Connect button |
| Agent file is not valid JSON | Wizard, Agents tab | Warning with the reason; Connect disabled; file untouched |
| Agent already has its own `afplay` hook | Connect preview | Warning that you may hear both; the hook is left alone |
| Another agent (Gemini, Cursor, opencode) | Wizard, Agents tab | Copy buttons for `play-sound <event>`; no automatic wiring |
| No sound files | Sound menu | "No sounds yet" and "Add sound..." |
| `jq` missing (macOS < 15) | Wizard install, Config Health | Explains `brew install jq` |
| No activity yet | Popover, Activity tab | "Nothing yet" with what to do |

## Connect / Disconnect semantics
- Connect adds a hook group as the first element of each event array (creating the `hooks` section or the file if needed), or takes over a recognized legacy command (`afplay ...PeonX.wav`, `stop-sound.sh`), or updates an existing play-sound command. A timestamped `.bak-agent-sounds-*` copy is saved first and permissions are preserved.
- Disconnect restores any command it replaced (from `connections.json`) and otherwise removes its hook, then removes event keys and the `hooks` object if they ended up empty. For files that only had other hooks, connect then disconnect is byte-identical (tested). A file the app created is left as `{}`.
- Hooks written by the first version (no `connections.json` entry) are removed on Disconnect rather than restored to `afplay`; the backups hold the originals.

## Accessibility
Every button has an explicit `accessibilityLabel` (the custom button styles did not expose their text, so a screen reader heard only "button"). Switches take a `label` and report On/Off as their value. The Orca GUI driver's tree view does not print labels; verify them with the Accessibility API (`AXDescription`) or VoiceOver. "Show exact changes" lists one readable line per hook (Add/Replace/Update, command with `~`), in a scrolling box capped at 150 pt. The raw line diff is still printed by `connect --dry-run`.

## Driving the real UI
The app has no Dock icon, so `orca computer list-apps` does not list it. Find the pid with `pgrep -x AgentSoundsBar`, then `orca computer list-windows --app pid:<pid>` and pass `--window-id`.

## Simulating a new user (no GUI needed)
```bash
F=$(mktemp -d); mkdir -p $F/home/.claude
export AGENT_SOUNDS_HOME=$F/cfg AGENT_SOUNDS_USER_HOME=$F/home AGENT_SOUNDS_PLAYER=/usr/bin/true
BIN=build/AgentSoundsBar.app/Contents/MacOS/AgentSoundsBar
$BIN status; $BIN setup; $BIN connect all --dry-run; $BIN connect claude
```
Then run the written Stop command with `sh -c` to hear (or log) it end to end. `AGENT_SOUNDS_RESOURCES` overrides where the CLI finds bundled files when run outside an `.app`.
