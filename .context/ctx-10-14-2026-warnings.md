# Warnings

Things that are fragile, unverified, or easy to get wrong. Read before changing hooks, packaging or UI.

## Live files this project edits
- `~/.claude/settings.json` and `~/.codex/hooks.json` were rewired to call `play-sound`. Backups: `~/.claude/settings.json.bak-agent-sounds-20261014-124346` and `~/.codex/hooks.json.bak-agent-sounds-20261014-124610`.
- Never rewire without `--dry-run` first and the user's explicit go-ahead. These are the user's live agent configs.
- `settings.json` is also rewritten by plugins and Orca (its mtime changed during a session without our involvement). Do not replace it wholesale, and re-run the Agents tab or `install.sh --rewire claude --dry-run` if hooks seem to have reverted.
- `HookConnector.classify` recognizes legacy hooks by pattern (`afplay` plus `PeonReady1|PeonYes3|PeonWhat3.wav`, `stop-sound.sh`). Other `afplay` hooks are left alone with a warning, so a user with their own sound hook may hear both. Renaming sounds or hooks breaks the legacy match silently.
- Disconnect on hooks written by the first version (no `connections.json` record) removes them instead of restoring `afplay`; the backups next to the hook files hold the originals.

## Codex trusts hooks by hash
`~/.codex/config.toml` has `[hooks.state."...hooks.json:<event>:<n>:<n>"]` entries with a `trusted_hash` per hook. Changing a Codex hook command probably invalidates that trust and Codex may ask to re-approve (or skip) the three rewired hooks (SessionStart, Stop, UserPromptSubmit). This had not been observed yet when written. If Codex sounds go quiet, check this first. Claude Code has no such pinning.

## Peon sounds are Warcraft audio
The app and the repo bundle `Resources/sounds/*.wav` (the Peon files). Fine for personal use. Do not publish the repo or distribute the app with them; swap the folder first (system sounds are the easy alternative).

## Other agents are unverified
Gemini CLI, Cursor and opencode hook formats were only seen in web search summaries (Gemini needs hooks enabled in its settings and uses other event names; Cursor uses `~/.cursor/hooks.json` with its own event names; opencode uses JS plugins). The app only offers copy-paste commands for them. Codex may need `features.codex_hooks = true` on some versions (not needed on this machine); the wizard only hints at it.

## Not covered
- Project-level Codex hooks, for example `~/Documents/gbr/data-eng-airflow-server-config/.codex/hooks.json`, were not touched. Any sound hooks there still call `afplay` directly.
- Other agents only join if their hook runs `~/.config/agent-sounds/bin/play-sound <event>`.
- The old `~/.claude/hooks/stop-sound.sh` and `~/.codex/hooks/stop-sound.sh` and the duplicate sound files are still on disk, unused.

## Unverified at the time of writing (10-14-2026)
- **Menu bar icon in the real menu bar.** (still unconfirmed after the onboarding work) The user's menu bar is crowded and has a "•••" item that looks like a menu bar manager; the equalizer icon was not seen there. The icon's drawing was verified by rendering PNGs of every state, and the app does own a window, but visibility in their bar is unconfirmed.
- **The real `MenuBarExtra` popover chrome.** Screenshots came from the same views hosted in a normal `NSWindow`. System border, corner radius and background behind the aurora may differ in the real popover.
- **Audio.** Tests use a fake player. Nobody has confirmed by ear that volume changes are audible in live Claude/Codex sessions.
- **Config window tabs other than Overview** were not screenshotted (the Agents tab now uses the same `AgentCard` seen in the wizard).
- **Real-account run (10-14-2026).** After a verified backup and removing the app's hooks and settings, the wizard was driven end to end on the author's real account with the Orca computer-use tool (by process id, since the app has no Dock icon): Welcome, Install, Connect for Claude Code and Codex, Test, Finish. Install, both Connects, the backups, valid JSON and the completion flag were all checked afterwards. This was a clean state in an existing account, not a brand-new macOS user.
- **"Heard from <agent>" was simulated, but real Claude events were later seen.** The Test step's detection was verified by running the written Stop commands by hand. Afterwards `history.log` showed a real `stop` (13:34:37) and `user_prompt_submit` (13:34:46) with `agent=claude` that no command of ours produced, so Claude Code fires the connected hooks, and picked up the changed hooks without a restart. Codex still has only the simulated event.
- The 25-second "nothing yet" hint and the launch-at-login switch were not exercised.
- **macOS 14** (no `/usr/bin/jq`) has not been tried; the jq check and message exist but are untested there.
- **Codex re-approval** after Connect is still unobserved.
- Hover lift and switch/button springs were not exercised, only the play-triggered glow.

## Platform
- Glass look needs macOS 26. Older versions use the fallback material, which has not been looked at.
- The `.app` is ad-hoc signed and unsigned for distribution. First launch can need right-click, Open (Gatekeeper). "Launch at login" (`SMAppService`) only works from the built bundle, not from `swift run`.
- The app launched from `build/` is a single running instance; quit it before rebuilding and relaunching (`pkill -x AgentSoundsBar`).

## Gotchas in the code
- `play-sound` must always exit 0 and stay fast; a failing or slow hook degrades the agent itself. Keep jq/awk calls few.
- jq treats `false // x` as `x`, so `enabled` is tested with `!= false`, not `// true`.
- Appending to `history.log` does not fire directory watcher events, which is why `ActivityStore` polls.
- `ActivityStore` only animates for entries newer than 5 s, so stale log lines do not trigger an animation on launch.
- Tests wait 0.4 s after each call because the player runs in the background; shorter waits made the first case flaky.
- `AGENT_SOUNDS_HOME` is honored by both the script and the app. Use it (plus `AGENT_SOUNDS_PLAYER`) for any experiment so the real config and speakers stay untouched.

- The app has no Dock icon, so a window opened at launch can land behind other apps (activation is only a request since macOS 14). The first real run on the author's account showed the wizard hidden behind the terminal. `OnboardingWindow.show` now calls `orderFrontRegardless()`. Check any new launch-time window the same way (capture by window id and look at which app is frontmost).

## App icon (10-14-2026)
- `actool` needs full Xcode (26.6 here), not just the Command Line Tools. Without it, `build.sh` prints a warning and the app has no icon.
- `actool` resolves relative paths against its helper daemon's working directory, not the caller's, so it failed with "output directory does not exist". `build.sh` passes absolute paths; keep it that way.
- Verified on macOS 26 only, by asking `NSWorkspace` for the built app's icon and rendering it at 800/128/64/32/16 px. The pre-26 path (`AppIcon.icns`) was checked as an image (256 px max), not in Finder on macOS 14 or 15. Dark, tinted and clear icon modes were not checked.
- Finder caches icons. After changing the icon, `touch` the app or re-register it (`lsregister -f build/AgentSoundsBar.app`) if the old one still shows.

## Tooling notes from this machine
- A global hook rewrites shell commands through `rtk` and another (Sage) screens commands; one early `grep` with "say " in a pattern was blocked. `screencapture` commands were flagged and approved by the user. Expect similar prompts.
- When reading downloaded or untrusted files with Python, use `python3 -I`.

## Update 10-15-2026: public release
- The Peon warning above is resolved for the repo and release: `Resources/sounds` was removed and the public history starts without it. The old private history is kept only in the local branch `private-history`; never push it.
- `HookConnector.classify` still recognizes the legacy Peon `afplay` hooks by file name. Harmless for other users, needed for this machine.
- This machine's `~/.config/agent-sounds/config.json` still names the Peon files, which remain in `~/.config/agent-sounds/sounds`, so they keep playing here.
- Update checks are unauthenticated GitHub API calls (60 per hour per IP). Fine at one a day; a 403 or 429 shows as "rate limiting" only on a manual check.
- The Homebrew in-app upgrade runs brew from a GUI app with a minimal PATH (brew's own bin plus the system dirs). Not yet exercised against a real second release: verify it when 1.0.1 ships.
- `brew style` could not run on this machine (gem install fails with an SSL certificate error against rubygems.org). The cask was only syntax-checked with Homebrew's Ruby; installing it from the tap is the real test.
- Visual checks of the update UI (10-15-2026): the popover banner was captured in the window harness with an injected "available" state. The gear-menu items and the configuration window's Updates section were not captured.
