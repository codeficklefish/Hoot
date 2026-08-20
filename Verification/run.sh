#!/bin/bash
# Compiles Hoot's non-UI services together with the verification harness and
# runs them against a throwaway sandbox folder. No user files are touched.
set -e
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)/verify
swiftc -o "$OUT" \
  Sources/Hoot/Models/*.swift \
  Sources/Hoot/Services/Classifier/*.swift \
  Sources/Hoot/Services/Curation/*.swift \
  Sources/Hoot/Services/FileAnalyzer/*.swift \
  Sources/Hoot/Services/Grouping/*.swift \
  Sources/Hoot/Services/History/*.swift \
  Sources/Hoot/Services/Learning/*.swift \
  Sources/Hoot/Services/Organizer/*.swift \
  Sources/Hoot/Utilities/FilenameTokenizer.swift \
  Sources/Hoot/AI/*.swift \
  Sources/Hoot/Services/TextExtractor/*.swift \
  Sources/Hoot/Utilities/ZipReader.swift \
  Verification/stage3.swift \
  Verification/stage4.swift \
  Verification/main.swift
exec "$OUT"
