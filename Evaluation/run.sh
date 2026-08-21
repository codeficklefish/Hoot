#!/bin/bash
# Measures Hoot against folders you organized yourself.
#
# Ground truth is the folder each file already sits in: you put it there, so
# that is the right answer. Reports accuracy and — more usefully — whether
# Hoot's stated confidence matches how often it is actually right.
#
# Reads your files; moves nothing.
set -e
cd "$(dirname "$0")/.."
exec swift run -c release Evaluation "$@"
