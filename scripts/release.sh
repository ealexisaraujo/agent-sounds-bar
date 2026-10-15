#!/bin/bash
# Release Agent Sounds Bar in two steps, so the artifact can be checked before anything is public.
#
#   scripts/release.sh build      tests, universal build, Developer ID signing, notarization,
#                                 stapling -> dist/AgentSoundsBar-<version>.zip (nothing is published)
#   scripts/release.sh publish    GitHub release v<version> with the zip, then the Homebrew cask
#                                 (stable versions only; a version with "-" is a beta prerelease)
#
# The version is the VERSION file. Release notes are its section in CHANGELOG.md.
# One-time setup: store notarization credentials in the keychain:
#   xcrun notarytool store-credentials agent-sounds-bar --apple-id <apple id> --team-id PN2FR53G7Y
set -euo pipefail
cd "$(dirname "$0")/.."

REPO="ealexisaraujo/agent-sounds-bar"
TAP="ealexisaraujo/homebrew-tap"
SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application: Enrique Alexis Araujo (PN2FR53G7Y)}"
TEAM_ID="${TEAM_ID:-PN2FR53G7Y}"
NOTARY_PROFILE="${NOTARY_PROFILE:-agent-sounds-bar}"

VERSION="$(tr -d '[:space:]' < VERSION)"
TAG="v$VERSION"
APP="build/AgentSoundsBar.app"
ZIP="dist/AgentSoundsBar-$VERSION.zip"
PRERELEASE=false; [[ "$VERSION" == *-* ]] && PRERELEASE=true

die() { echo "error: $*" >&2; exit 1; }
say() { echo "==> $*"; }

notes() { # The CHANGELOG section for VERSION, without its heading.
  awk -v v="$VERSION" '
    /^## / { if (found) exit; if (index($0, "[" v "]") || $2 == v) { found = 1; next } }
    found { print }' CHANGELOG.md
}

build() {
  [ -z "$(git status --porcelain)" ] || die "working tree is not clean"
  [ -n "$(notes | tr -d '[:space:]')" ] || die "CHANGELOG.md has no section for $VERSION"
  security find-identity -v -p codesigning | grep -q "$SIGN_IDENTITY" || die "signing identity not found: $SIGN_IDENTITY"

  say "Tests"
  swift test >/dev/null
  tests/test-play-sound.sh >/dev/null

  say "Universal build, signed with $SIGN_IDENTITY"
  UNIVERSAL=1 SIGN_IDENTITY="$SIGN_IDENTITY" ./build.sh
  codesign --verify --deep --strict "$APP"
  codesign -dvv "$APP" 2>&1 | grep -q "TeamIdentifier=$TEAM_ID" || die "signature is not from team $TEAM_ID"

  say "Notarize (this takes a few minutes)"
  mkdir -p dist
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  # Re-zip so the stapled ticket ships inside the archive and works offline.
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"

  say "Gatekeeper check"
  spctl --assess --type execute --verbose=2 "$APP"
  shasum -a 256 "$ZIP" | tee "$ZIP.sha256"
  say "Ready: $ZIP. Run 'scripts/release.sh publish' to release it."
}

publish() {
  [ -f "$ZIP" ] && [ -f "$ZIP.sha256" ] || die "run 'scripts/release.sh build' first"
  local sha; sha="$(cut -d' ' -f1 "$ZIP.sha256")"
  [ "$(shasum -a 256 "$ZIP" | cut -d' ' -f1)" = "$sha" ] || die "$ZIP changed since it was built"
  gh release view "$TAG" -R "$REPO" >/dev/null 2>&1 && die "release $TAG already exists"

  say "GitHub release $TAG"
  git tag -a "$TAG" -m "Agent Sounds Bar $VERSION" 2>/dev/null || true
  git push origin "$TAG"
  local flags=(); $PRERELEASE && flags=(--prerelease)
  notes > dist/notes.md
  gh release create "$TAG" "$ZIP" -R "$REPO" --title "Agent Sounds Bar $VERSION" \
    --notes-file dist/notes.md --verify-tag ${flags[@]+"${flags[@]}"}

  if $PRERELEASE; then
    say "Beta release: the Homebrew cask stays on the last stable version"
    return
  fi

  say "Homebrew cask $TAP"
  local tap="build/homebrew-tap"
  rm -rf "$tap"
  gh repo clone "$TAP" "$tap" -- --quiet
  mkdir -p "$tap/Casks"
  sed -e "s/__VERSION__/$VERSION/" -e "s/__SHA256__/$sha/" packaging/homebrew/agent-sounds-bar.rb \
    | grep -v '^# Template for\|^# scripts/release.sh fills' > "$tap/Casks/agent-sounds-bar.rb"
  git -C "$tap" add Casks/agent-sounds-bar.rb
  git -C "$tap" commit -q -m "agent-sounds-bar $VERSION"
  git -C "$tap" push -q
  say "Done: brew install --cask ealexisaraujo/tap/agent-sounds-bar"
}

case "${1:-}" in
  build) build ;;
  publish) publish ;;
  *) sed -n '2,11p' "$0"; exit 2 ;;
esac
