#!/usr/bin/env bash
# Prints the notes for a GitHub Release. CI runs this when a tag is pushed.
#
#   bash tools/release_notes.sh VERSION release|debug
set -euo pipefail

version="${1:?usage: release_notes.sh VERSION release|debug}"
signing="${2:?usage: release_notes.sh VERSION release|debug}"

cat <<NOTES
Chiptune Forge $version. You can also play it in your browser at
https://xsoc.github.io/chiptune-forge/.

| Platform | Download |
| --- | --- |
| macOS (Intel and Apple Silicon) | \`chiptune-forge-$version-macos.zip\` |
| Windows (64-bit) | \`chiptune-forge-$version-windows-x86_64.zip\` |
| Linux (64-bit) | \`chiptune-forge-$version-linux-x86_64.tar.gz\` |
| Android (arm64) | \`chiptune-forge-$version-android.apk\` |
| Web (for self-hosting) | \`chiptune-forge-$version-web.zip\` |

### These builds are not signed yet

Your system will warn you the first time you open them.

- **macOS:** unzip, then right-click **Chiptune Forge.app** and choose
  **Open**, then **Open** again. If macOS says the app is damaged, run
  \`xattr -dr com.apple.quarantine "Chiptune Forge.app"\` in Terminal.
- **Windows:** if SmartScreen says it protected your PC, click
  **More info**, then **Run anyway**.
- **Linux:** extract the archive, then run \`./chiptune-forge.x86_64\`.
- **Android:** allow your browser or file manager to install unknown apps
  when Android asks.
NOTES

if [ "$signing" = "debug" ]; then
	cat <<NOTES
  This APK is signed with a debug key, so a later release signed with the
  real key will not install over it. Uninstall it first in that case.
NOTES
fi
