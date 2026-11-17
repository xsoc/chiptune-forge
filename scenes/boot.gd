extends Node
## The first scene. With command line arguments for the CLI (see
## [CliRunner]) it runs the command and quits without loading the UI;
## otherwise it opens the app.

const MAIN := "res://scenes/main.tscn"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if CliRunner.wants_cli(args) and not OS.has_feature("web") and not OS.has_feature("mobile"):
		var code := CliRunner.new().run(args)
		get_tree().quit(code)
		return
	get_tree().change_scene_to_file.call_deferred(MAIN)
