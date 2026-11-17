#!/bin/sh
# Runs Chiptune Forge's command line from the project in the image, with
# relative paths starting from the folder the command runs in.
CHIPTUNE_FORGE_CWD="$(pwd)"
export CHIPTUNE_FORGE_CWD
# Godot keeps its settings under $HOME: use /tmp when running as a user
# (docker run -u) whose home is not writable.
if [ ! -w "${HOME:-/nonexistent}" ]; then
	HOME=/tmp
	export HOME
fi
exec godot --headless --audio-driver Dummy --path /opt/chiptune-forge -- "$@"
