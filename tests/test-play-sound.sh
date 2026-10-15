#!/bin/bash
# Tests for scripts/play-sound using a fake player that logs its arguments.
# Never touches the real ~/.config/agent-sounds and makes no noise.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/scripts/play-sound"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

export AGENT_SOUNDS_HOME="$TMP/home"
export AGENT_SOUNDS_PLAYER="$TMP/fake-player"
LOG="$TMP/player.log"
mkdir -p "$AGENT_SOUNDS_HOME/sounds"
: > "$AGENT_SOUNDS_HOME/sounds/custom.wav"
# Defaults are the built-in macOS sounds, which exist on every Mac (and CI runner).
SYS=/System/Library/Sounds
printf '#!/bin/bash\necho "$@" >> "%s"\n' "$LOG" > "$AGENT_SOUNDS_PLAYER"
chmod +x "$AGENT_SOUNDS_PLAYER"

PASS=0; FAIL=0
run() { : > "$LOG"; "$SCRIPT" "$@" < /dev/null; echo $? > "$TMP/rc"; sleep 0.4; }
check() { # name, expected log content ("" = silent)
  local got; got=$(sed "s#$AGENT_SOUNDS_HOME/sounds/##" "$LOG" | tr -d '\n')
  if [ "$got" = "$2" ] && [ "$(cat "$TMP/rc")" = "0" ]; then PASS=$((PASS+1)); echo "ok   $1"
  else FAIL=$((FAIL+1)); echo "FAIL $1: expected [$2] got [$got] rc=$(cat "$TMP/rc")"; fi
}

# 1. Missing config -> defaults at full volume
rm -f "$AGENT_SOUNDS_HOME/config.json"
run stop;                check "missing config uses default sound/volume" "-v 1.000 $SYS/Glass.aiff"

# 2. Volume + custom sound from config
cat > "$AGENT_SOUNDS_HOME/config.json" <<'EOF'
{ "muted": false, "volume": 0.25,
  "events": { "stop": {"enabled": true, "sound": "custom.wav"},
              "notification": {"enabled": false, "sound": "custom.wav"} } }
EOF
run stop;                check "volume and custom sound applied" "-v 0.250 custom.wav"
run notification;        check "disabled event is silent" ""
run user_prompt_submit;  check "event absent from config falls back to default" "-v 0.250 $SYS/Tink.aiff"

# 3. Mute
cat > "$AGENT_SOUNDS_HOME/config.json" <<'EOF'
{ "muted": true, "volume": 1 }
EOF
run stop;                check "muted is silent" ""

# 4. Volume 0 and out-of-range
echo '{ "volume": 0 }' > "$AGENT_SOUNDS_HOME/config.json"
run stop;                check "volume 0 is silent" ""
echo '{ "volume": 7 }' > "$AGENT_SOUNDS_HOME/config.json"
run stop;                check "volume above 1 is clamped" "-v 1.000 $SYS/Glass.aiff"
echo '{ "volume": "loud" }' > "$AGENT_SOUNDS_HOME/config.json"
run stop;                check "non-numeric volume falls back to 1" "-v 1.000 $SYS/Glass.aiff"

# 5. Corrupt config / missing sound file / unknown event / no args
echo 'not json {{{' > "$AGENT_SOUNDS_HOME/config.json"
run stop;                check "corrupt config falls back to defaults" "-v 1.000 $SYS/Glass.aiff"
echo '{ "events": { "stop": {"sound": "nope.wav"} } }' > "$AGENT_SOUNDS_HOME/config.json"
run stop;                check "missing sound file is silent" ""
run bogus_event;         check "unknown event is silent" ""
run;                     check "no args is silent" ""

# 6. Absolute sound path
echo "{ \"events\": { \"stop\": {\"sound\": \"$TMP/abs.wav\"} } }" > "$AGENT_SOUNDS_HOME/config.json"
: > "$TMP/abs.wav"
: > "$LOG"; "$SCRIPT" stop < /dev/null; echo $? > "$TMP/rc"; sleep 0.4
[ "$(cat "$LOG")" = "-v 1.000 $TMP/abs.wav" ] && { PASS=$((PASS+1)); echo "ok   absolute sound path"; } || { FAIL=$((FAIL+1)); echo "FAIL absolute sound path: $(cat "$LOG")"; }

# 7. stop with rate-limit transcript -> stop_error sound; clean transcript -> stop sound
echo '{}' > "$AGENT_SOUNDS_HOME/config.json"
echo '{"error":"rate_limit_error"}' > "$TMP/bad.jsonl"
echo '{"ok":true}' > "$TMP/good.jsonl"
: > "$LOG"; echo "{\"transcript_path\":\"$TMP/bad.jsonl\"}" | "$SCRIPT" stop; echo $? > "$TMP/rc"; sleep 0.4
check "stop + rate-limit transcript plays stop_error" "-v 1.000 $SYS/Basso.aiff"
: > "$LOG"; echo "{\"transcript_path\":\"$TMP/good.jsonl\"}" | "$SCRIPT" stop; echo $? > "$TMP/rc"; sleep 0.4
check "stop + clean transcript plays stop" "-v 1.000 $SYS/Glass.aiff"

# 8. History log records every outcome
rm -f "$AGENT_SOUNDS_HOME/history.log"
export AGENT_SOUNDS_AGENT=claude
echo '{ "muted": true }' > "$AGENT_SOUNDS_HOME/config.json"; run stop
echo '{ "events": { "notification": {"enabled": false} } }' > "$AGENT_SOUNDS_HOME/config.json"; run notification
echo '{}' > "$AGENT_SOUNDS_HOME/config.json"; run user_prompt_submit
got=$(cut -f2- "$AGENT_SOUNDS_HOME/history.log" | tr '\t' ':' | tr '\n' ' ')
unset AGENT_SOUNDS_AGENT
[ "$got" = "stop:muted::claude notification:disabled::claude user_prompt_submit:played:$SYS/Tink.aiff:claude " ] \
  && { PASS=$((PASS+1)); echo "ok   history log records muted/disabled/played"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL history log: [$got]"; }
for i in $(seq 1 310); do echo "1\tstop\tplayed\tx" >> "$AGENT_SOUNDS_HOME/history.log"; done
run stop
n=$(wc -l < "$AGENT_SOUNDS_HOME/history.log" | tr -d ' ')
[ "$n" -le 201 ] && { PASS=$((PASS+1)); echo "ok   history log is trimmed ($n lines)"; } || { FAIL=$((FAIL+1)); echo "FAIL history not trimmed: $n"; }

echo; echo "passed=$PASS failed=$FAIL"
[ "$FAIL" -eq 0 ]
