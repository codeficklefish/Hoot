#!/bin/bash
# Runs Hoot with the notch HUD explaining itself, and follows the log.
#
# The panel at the camera housing is the one surface in this project that
# cannot be looked at from outside. Screen-capture tooling filters to the
# applications it has been granted, and an LSUIElement app running out of a
# build directory cannot be granted — so the panel is absent from any capture,
# and a screenshot proves nothing about it. It has to say what happened.
#
# Use it to answer the interactions no check covers: whether the triangle and
# the row take their own clicks, whether a drag survives leaving the panel,
# whether Quick Look appears from a window that is not key.
#
#     ./Packaging/trace-hud.sh
#
# Then point at the notch and use it. Ctrl-C stops following; Hoot keeps
# running. Quit and reopen it normally and the tracing stops.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Hoot.app"
LOG="${TMPDIR:-/tmp}/hoot-hud.log"

if [ ! -x "$APP/Contents/MacOS/Hoot" ]; then
    echo "==> No build yet — run ./Packaging/build-app.sh release first." >&2
    exit 1
fi

echo "==> Stopping any running Hoot"
osascript -e 'tell application "Hoot" to quit' 2>/dev/null || true
sleep 1
pkill -f "$APP/Contents/MacOS/Hoot" 2>/dev/null || true
sleep 1

echo "==> Starting with HOOT_TRACE_HUD=1"
: > "$LOG"
HOOT_TRACE_HUD=1 nohup "$APP/Contents/MacOS/Hoot" > "$LOG" 2>&1 &
sleep 2

echo "==> Following $LOG — point at the notch. Ctrl-C to stop watching."
exec tail -f "$LOG"
