#!/bin/sh
# Builds the evaluation tool into .build/evaluate/ (macOS with Xcode): the app's analysis code,
# optimised, with KaliberfinderTests/Evaluation.swift (the scoring GoldenSetTests uses) and
# main.swift. It takes every Services file that needs no UIKit, so new analysis code comes along.
# `build.sh --typecheck` only checks that it compiles (the Build workflow does that).
set -eu
cd "$(dirname "$0")/../.."
SOURCES="tools/evaluate/main.swift tools/evaluate/terms.swift KaliberfinderTests/Evaluation.swift Kaliberfinder/Models/*.swift
  $(grep -L -E '^import (UIKit|SwiftUI|AVFoundation|CoreMotion)' Kaliberfinder/Services/*.swift || true)"
if [ "${1:-}" = --typecheck ]; then
  # shellcheck disable=SC2086 # the file list is split on purpose
  exec xcrun swiftc -typecheck -swift-version 5 $SOURCES
fi
mkdir -p .build/evaluate
# shellcheck disable=SC2086
xcrun swiftc -O -swift-version 5 -module-name evaluate -o .build/evaluate/evaluate $SOURCES
# CartridgeCatalog reads the calibres from the tool's own folder (Bundle.main).
cp Kaliberfinder/Resources/Cartridges.json .build/evaluate/
echo "built .build/evaluate/evaluate"
