#!/bin/bash
# Measures Hoot against folders you organized yourself.
#
# Ground truth is your own filing. The folder a file already sits in is where
# it belongs, because you put it there; a filename you have kept is a name
# worth keeping, for the same reason.
#
#   ./Evaluation/run.sh                 all three
#   ./Evaluation/run.sh folders         does a file end up where you would put it?
#   ./Evaluation/run.sh meaningless     which kept names would Hoot overwrite?
#   ./Evaluation/run.sh names 20        can it recover a name you chose? (20 files)
#
# Reads your files; moves nothing and writes nothing.
set -e
cd "$(dirname "$0")/.."

# Xcode's Swift, never whatever happens to be first on PATH — see
# Packaging/find-swift.sh for what goes wrong when it is not.
source Packaging/find-swift.sh
SWIFT="$(find_swift)"

exec "$SWIFT" run -c release Evaluation "$@"
