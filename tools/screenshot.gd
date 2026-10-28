extends SceneTree
## Captures the app at a given window size, for checking layouts.
##   godot --path . -s tools/screenshot.gd -- 390 844 2 out.png [sfx] [ScreenName]

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var w := int(args[0])
	var h := int(args[1])
	var out := args[3]
	DisplayServer.window_set_size(Vector2i(w, h))
	root.size = Vector2i(w, h)
	var main: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.set_ui_scale(float(args[2]))
	for i in 10:
		await process_frame
	if args.size() > 4 and args[4] == "sfx":
		root.get_node("AppState").mode = "sfx"
	if args.size() > 5:
		main._show_screen(args[5])
	for i in 30:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out)
	print("saved ", out)
	quit()
