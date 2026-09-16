#!/bin/bash
# Runs Hoot's behaviour and safety checks against a throwaway sandbox folder.
#
# Built as a package target, so it links the same HootKit and HootPlatformMac
# the app ships — and cannot quietly drift from them.
#
# Touches nothing outside a temporary directory.
set -e
cd "$(dirname "$0")/.."

# Xcode's Swift, never whatever happens to be first on PATH — see
# Packaging/find-swift.sh for what goes wrong when it is not.
source Packaging/find-swift.sh
SWIFT="$(find_swift)"

exec "$SWIFT" run -c release Verification "$@"
