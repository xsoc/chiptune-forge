#!/usr/bin/env bash
# Writes a build number into project.godot, so the app can show which build it
# is (see scripts/build_info.gd). CI runs this before every export with the
# workflow run number; it edits the working copy only.
#
#   bash tools/stamp_build.sh 42
set -euo pipefail

number="${1:?usage: stamp_build.sh BUILD_NUMBER}"
if [[ ! "$number" =~ ^[1-9][0-9]*$ ]]; then
	echo "Build number '$number' is not a positive whole number" >&2
	exit 1
fi

root="$(cd "$(dirname "$0")/.." && pwd)"
project="$root/project.godot"

if grep -q '^config/build_number=' "$project"; then
	sed -i "s/^config\/build_number=.*/config\/build_number=$number/" "$project"
else
	sed -i "/^config\/version=/a config\/build_number=$number" "$project"
fi
grep -q "^config/build_number=$number\$" "$project"

echo "Stamped build number $number"
