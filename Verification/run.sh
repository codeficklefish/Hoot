#!/bin/bash
# Runs Hoot's behaviour and safety checks against a throwaway sandbox folder.
#
# Built as a package target, so it links the same HootKit and HootPlatformMac
# the app ships — and cannot quietly drift from them.
#
# Touches nothing outside a temporary directory.
set -e
cd "$(dirname "$0")/.."
exec swift run -c release Verification "$@"
