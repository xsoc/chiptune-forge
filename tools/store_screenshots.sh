#!/usr/bin/env bash
# Takes the store listing screenshots: four screens at each size the app
# stores ask for, into store/screenshots/<device>/. Needs Godot and, on a
# machine without a display, xvfb-run.
#
#   bash tools/store_screenshots.sh [godot]
set -euo pipefail

godot="${1:-godot}"
root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/store/screenshots"
run=()
if [ -z "${DISPLAY:-}" ] && command -v xvfb-run > /dev/null; then
	run=(xvfb-run -a)
fi

# device, width, height, UI scale
devices=(
	"android-phone 1080 1920 3"
	"android-tablet 1920 1200 2"
	"ios-6.9 1320 2868 3"
	"ios-6.5 1284 2778 3"
	"ipad-13 2064 2752 2"
	"desktop 1920 1080 1.5"
)
# file, mode or target, screen, scroll on portrait screens (to the presets)
shots=(
	"1-generate music GenerateScreen 0"
	"2-layers music LayersScreen 0"
	"3-sfx sfx SfxScreen 520"
	"4-export nes ExportScreen 0"
)

for device in "${devices[@]}"; do
	read -r name width height scale <<< "$device"
	mkdir -p "$out/$name"
	for shot in "${shots[@]}"; do
		read -r file mode screen scroll <<< "$shot"
		if (( width > height )); then
			scroll=0
		fi
		"${run[@]}" "$godot" --path "$root" --rendering-driver opengl3 --audio-driver Dummy \
			-s tools/screenshot.gd -- "$width" "$height" "$scale" "$out/$name/$file.png" "$mode" "$screen" "$scroll" < /dev/null > /dev/null 2>&1
		test -s "$out/$name/$file.png"
	done
	echo "$name: ${#shots[@]} screenshots"
done
