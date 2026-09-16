#!/bin/bash
# One accuracy run, appended to a log you can read back over time.
#
# Driven by launchd every three hours (~/Library/LaunchAgents/com.hoot.accuracy.plist)
# and perfectly safe to run by hand. The point of logging rather than printing
# is that a single accuracy number says very little — what says something is
# the same number before and after a change.
#
# Reads your files. Moves nothing, writes nothing except the log.

# Deliberately not `set -e`: a run that fails is the run most worth recording,
# and exiting early would leave nothing in the log to explain why.
set -uo pipefail
cd "$(dirname "$0")/.."

LOG="${HOOT_ACCURACY_LOG:-$HOME/Library/Logs/Hoot/accuracy.log}"
mkdir -p "$(dirname "$LOG")"

{
    echo
    echo "======================================================================"
    echo "$(date '+%Y-%m-%d %H:%M:%S %Z')  ·  $(git rev-parse --short HEAD 2>/dev/null || echo 'not a checkout')"
    echo "======================================================================"

    # Both accuracy questions, and the false-positive scan that costs nothing.
    # 40 files is the naming cap — every one of those is a model round trip.
    ./Evaluation/run.sh folders meaningless names 40 2>&1
    status=$?
    echo
    echo "[exit $status]"

    # A run that finds nothing to measure is almost always a permissions
    # problem rather than an empty folder: launchd has no way to answer a
    # macOS access prompt, so reading ~/Downloads can simply be refused.
    if [ "$status" -ne 0 ]; then
        echo "[note] If this says there is nothing to measure, grant Full Disk"
        echo "       Access to /bin/bash in System Settings → Privacy & Security,"
        echo "       or run this script once by hand to answer the prompt."
    fi
} >> "$LOG" 2>&1

# Keep the log readable rather than letting it grow without end. Trimmed from
# the front, so the most recent runs are always the ones kept.
if [ "$(wc -l < "$LOG" 2>/dev/null || echo 0)" -gt 6000 ]; then
    tail -n 4000 "$LOG" > "$LOG.trimmed" && mv "$LOG.trimmed" "$LOG"
fi
