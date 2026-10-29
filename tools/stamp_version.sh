#!/usr/bin/env bash
# Writes a release tag's version into project.godot and the export presets,
# so the builds report the version they were released as. CI runs this on
# tag pushes; it edits the working copy only.
#
#   bash tools/stamp_version.sh v1.2.3[-beta.1]
set -euo pipefail

tag="${1:?usage: stamp_version.sh vMAJOR.MINOR.PATCH[-suffix]}"
version="${tag#v}"
if [[ ! "$version" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)(-.*)?$ ]]; then
	echo "Tag '$tag' is not vMAJOR.MINOR.PATCH" >&2
	exit 1
fi
major="${BASH_REMATCH[1]}"
minor="${BASH_REMATCH[2]}"
patch="${BASH_REMATCH[3]}"
if (( minor > 99 || patch > 99 )); then
	echo "Minor and patch must be below 100 for the Android version code" >&2
	exit 1
fi
numeric="$major.$minor.$patch"
# Android needs a whole number that grows with every release.
code=$(( major * 10000 + minor * 100 + patch ))

root="$(cd "$(dirname "$0")/.." && pwd)"

sed -i "s/^config\/version=.*/config\/version=\"$version\"/" "$root/project.godot"

# Add the version options straight after each preset's options header.
awk -v name="$version" -v numeric="$numeric" -v code="$code" '
	/^\[preset\.[0-9]+\]$/ { platform = "" }
	/^platform=/ { platform = $0; sub(/^platform="/, "", platform); sub(/"$/, "", platform) }
	{ print }
	/^\[preset\.[0-9]+\.options\]$/ {
		if (platform == "Android") {
			print "version/code=" code
			print "version/name=\"" name "\""
		} else if (platform == "macOS") {
			print "application/short_version=\"" numeric "\""
			print "application/version=\"" numeric "\""
		} else if (platform == "Windows Desktop") {
			print "application/file_version=\"" numeric ".0\""
			print "application/product_version=\"" numeric ".0\""
		}
	}
' "$root/export_presets.cfg" > "$root/export_presets.cfg.tmp"
mv "$root/export_presets.cfg.tmp" "$root/export_presets.cfg"

echo "Stamped version $version (Android code $code)"
