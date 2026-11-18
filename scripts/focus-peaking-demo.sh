#!/bin/bash
# Usage: scripts/focus-peaking-demo.sh /path/to/photo.CR3 [output-folder]
# Reads ONE photo and writes three new JPEGs (focus peaking at low/mid/high sensitivity).
# Never modifies the photo. Default output: ~/Desktop/Gallra-peaking-demo
set -e
[ -f "$1" ] || { echo "Give the path to a photo, e.g. scripts/focus-peaking-demo.sh ~/Pictures/IMG_0001.CR3"; exit 1; }
cd "$(dirname "$0")/../GallraCore"
GALLRA_PEAKING_INPUT="$1" GALLRA_PEAKING_OUTPUT="${2:-$HOME/Desktop/Gallra-peaking-demo}" \
  swift test --filter FocusPeakingDemo 2>&1 | grep -E "PEAKING|error|failed|passed"
