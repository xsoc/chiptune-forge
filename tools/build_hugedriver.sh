#!/usr/bin/env bash
# Builds hUGEDriver as a GBDK-2020 library, so Game Boy exports include a
# prebuilt driver and users only need GBDK to make a ROM.
#   tools/build_hugedriver.sh /path/to/gbdk
# Needs rgbasm from RGBDS 0.6.x (rgb2sdas reads its object format) and Python 3.
set -euo pipefail
GBDK_HOME="${1:?usage: build_hugedriver.sh GBDK_HOME}"
DRIVER="$(cd "$(dirname "$0")/../assets/gameboy/hUGEDriver" && pwd)"
mkdir -p "$DRIVER/lib"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
rgbasm -DGBDK -i"$DRIVER/" -o "$work/hUGEDriver.obj" "$DRIVER/hUGEDriver.asm"
python3 -I "$DRIVER/tools/rgb2sdas.py" -o "$work/hUGEDriver.o" "$work/hUGEDriver.obj"
rm -f "$DRIVER/lib/hUGEDriver.lib"
"$GBDK_HOME/bin/sdar" -ru "$DRIVER/lib/hUGEDriver.lib" "$work/hUGEDriver.o"
echo "Built $DRIVER/lib/hUGEDriver.lib"
