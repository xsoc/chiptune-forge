extends SceneTree
## Drags every editable slider on the Generate, Layers and Sound FX screens
## with simulated mouse or touch input, pausing mid-drag so debounced
## regeneration runs, and prints PASS or FAIL for each one.
##   godot --headless --path . -s tools/drag_probe.gd -- [mouse|touch]

const W := 390
const H := 844

func _initialize() -> void:
	_run.call_deferred()

func _collect(n: Node, out: Array) -> void:
	if n is Slider and n.is_visible_in_tree():
		out.append(n)
	for c in n.get_children():
		_collect(c, out)

func _scroll_of(n: Node) -> ScrollContainer:
	var p := n.get_parent()
	while p:
		if p is ScrollContainer:
			return p
		p = p.get_parent()
	return null

func _run() -> void:
	var touch := OS.get_cmdline_user_args().has("touch")
	root.size = Vector2i(W, H)
	var main: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame
	for screen in [["music", ""], ["music", "LayersScreen"], ["sfx", ""]]:
		root.get_node("AppState").mode = screen[0]
		if screen[1] != "":
			main._show_screen(screen[1])
		for i in 10:
			await process_frame
		var sliders: Array = []
		_collect(main, sliders)
		for s: Slider in sliders:
			if not s.editable:
				continue
			var path := str(s.get_path()).replace("/root/Main/Layout/", "")
			var sc := _scroll_of(s)
			if sc:
				sc.ensure_control_visible(s)
			for i in 3:
				await process_frame
			s.value = s.min_value
			await process_frame
			var r: Rect2 = s.get_global_rect()
			var y := r.get_center().y
			var x0 := r.position.x + 4
			var x1 := r.position.x + r.size.x * 0.75
			var scroll0 := sc.scroll_vertical if sc else 0
			_press(touch, Vector2(x0, y), true)
			await process_frame
			var ok := true
			for k in 10:
				_move(touch, Vector2(lerpf(x0, x1, (k + 1) / 10.0), y), Vector2((x1 - x0) / 10.0, 0))
				await process_frame
				if k == 4:
					await create_timer(0.6).timeout
					await process_frame
				if not is_instance_valid(s):
					ok = false
					break
			if not ok:
				print("FAIL ", path, " slider freed during drag")
				_press(touch, Vector2(x1, y), false)
				continue
			var during := s.value
			_press(touch, Vector2(x1, y), false)
			await process_frame
			var frac := (during - s.min_value) / (s.max_value - s.min_value)
			print("PASS " if frac > 0.6 else "FAIL ", path, " during=%.2f frac=%.2f scroll %d->%d" % [during, frac, scroll0, sc.scroll_vertical if sc else 0])
	quit()

func _press(touch: bool, p: Vector2, down: bool) -> void:
	if touch:
		var e := InputEventScreenTouch.new()
		e.position = p
		e.pressed = down
		Input.parse_input_event(e)
	else:
		var e := InputEventMouseButton.new()
		e.position = p
		e.global_position = p
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		if down:
			e.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(e)
	Input.flush_buffered_events()

func _move(touch: bool, p: Vector2, rel: Vector2) -> void:
	if touch:
		var e := InputEventScreenDrag.new()
		e.position = p
		e.relative = rel
		Input.parse_input_event(e)
	else:
		var e := InputEventMouseMotion.new()
		e.position = p
		e.global_position = p
		e.relative = rel
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(e)
	Input.flush_buffered_events()
