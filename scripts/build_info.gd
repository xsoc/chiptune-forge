class_name BuildInfo
extends RefCounted
## The app version and build number shown in the header. CI writes the build
## number (the workflow run number, which goes up on every build) into
## project.godot with tools/stamp_build.sh. Builds made anywhere else have no
## number and show as "dev".

const BUILD_SETTING := "application/config/build_number"


static func version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))


## The build number, or 0 for a local build.
static func build_number() -> int:
	return int(ProjectSettings.get_setting(BUILD_SETTING, 0))


## "v0.1.0 · build 42", or just "build 42" when compact. Local builds say
## "dev" in place of the number.
static func label(compact: bool = false) -> String:
	var number := build_number()
	var build := "build %d" % number if number > 0 else "dev build"
	return build if compact else "v%s · %s" % [version(), build]
