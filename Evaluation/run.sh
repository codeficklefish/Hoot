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
OUT=$(mktemp -d)/evaluate
swiftc -O -o "$OUT" \
  Sources/Hoot/Models/*.swift \
  Sources/Hoot/AI/*.swift \
  Sources/Hoot/Services/Classifier/*.swift \
  Sources/Hoot/Services/Curation/*.swift \
  Sources/Hoot/Services/FileAnalyzer/*.swift \
  Sources/Hoot/Services/Grouping/*.swift \
  Sources/Hoot/Services/History/*.swift \
  Sources/Hoot/Services/Organizer/*.swift \
  Sources/Hoot/Services/TextExtractor/*.swift \
  Sources/Hoot/Utilities/FilenameTokenizer.swift \
  Sources/Hoot/Utilities/ZipReader.swift \
  Evaluation/main.swift
exec "$OUT"
