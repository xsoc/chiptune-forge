extends "res://tests/test_case.gd"


## The header label shows the version and the stamped build number, and falls
## back to "dev" when no build number was stamped.
func test_build_label() -> void:
	var saved: Variant = ProjectSettings.get_setting(BuildInfo.BUILD_SETTING, null)
	var version := BuildInfo.version()

	ProjectSettings.set_setting(BuildInfo.BUILD_SETTING, null)
	check_eq(BuildInfo.build_number(), 0, "no build number locally")
	check_eq(BuildInfo.label(), "v%s · dev build" % version)
	check_eq(BuildInfo.label(true), "dev build")

	ProjectSettings.set_setting(BuildInfo.BUILD_SETTING, 42)
	check_eq(BuildInfo.build_number(), 42)
	check_eq(BuildInfo.label(), "v%s · build 42" % version)
	check_eq(BuildInfo.label(true), "build 42")

	ProjectSettings.set_setting(BuildInfo.BUILD_SETTING, saved)
