# Changelog

All notable changes to Agent Sounds Bar. Versions follow [Semantic Versioning](https://semver.org); a version with a suffix such as `-beta.1` is a prerelease on the Beta channel.

## [1.0.0] - 2026-10-15

First public release.

### Highlights
- One volume, one mute and one sound per event for Claude Code, Codex and any agent with hooks, from the menu bar.
- A first-launch setup guide installs the `play-sound` command, connects Claude Code and Codex (showing every change first, with a backup), and confirms that a real event arrives.
- Five events: session start, prompt sent, task complete, rate limit / error (detected from the transcript), and needs attention.
- Defaults are the sounds built into macOS; add your own from any event's menu.
- Updates from the menu bar: Stable and Beta channels, a daily check, and a one-click upgrade for Homebrew installs.
- Configuration window with health checks, per-agent hook status and a log of every hook call.
- Command line mode: `status`, `setup`, `connect`, `disconnect`, `version`, `check-update`, each previewable with `--dry-run`.
- Universal app (Apple silicon and Intel), signed with a Developer ID and notarized. New Liquid Glass app icon.
- Install with `brew install --cask ealexisaraujo/tap/agent-sounds-bar`.
