class_name PianoRoll
extends Control
## A piano roll for one part of one section: a column per step, a row per
## pitch (or drum), with a keyboard down the left, a bar ruler along the top
## and a velocity lane along the bottom.
##
## Mouse and touch: with the Draw tool, tap to add a note and drag to set its
## length; drag a note to move it, drag its right end to change its length,
## tap it to remove it. The Select tool selects notes (drag a box, or tap)
## and moves or stretches all of them. The Erase tool removes what it
## touches. A right click erases with any tool. Drag across the ruler to pick
## whole bars. Two fingers pan and pinch to zoom; the mouse wheel scrolls
## (Shift for sideways, Ctrl to zoom).
##
## The roll edits a working copy of the notes and sends the whole list with
## [signal notes_edited] when a gesture ends, so one gesture is one undo step.

signal notes_edited(notes: Array)
## A key on the keyboard, or a note being placed, wants to be heard.
signal row_pressed(row: int)
signal row_released(row: int)
## The bars picked on the ruler changed (from step, to step; -1 for none).
signal range_changed(from: int, to: int)
signal selection_changed(count: int)
## A tap on an empty cell, where step input goes next.
signal cursor_changed(step: int)

enum Tool { DRAW, SELECT, ERASE }

const KEYS_WIDTH := 52.0
const RULER_HEIGHT := 22.0
const VELOCITY_HEIGHT := 48.0
const BAR := 12.0
const EDGE := 8.0
const MIN_CELL := 8.0
const MAX_CELL := 64.0

const BACKGROUND := Color("101116")
const BLACK_ROW := Color(0, 0, 0, 0.22)
const MARKED_ROW := Color(1, 1, 1, 0.05)
const LINE := Color(1, 1, 1, 0.06)
const BEAT_LINE := Color(1, 1, 1, 0.12)
const BAR_LINE := Color(1, 1, 1, 0.3)
const MUTED := Color("9a9daa")
const RANGE := Color(0.96, 0.73, 0.26, 0.12)
const SELECT_BOX := Color(1, 1, 1, 0.5)

var tool := Tool.DRAW
## Rows top to bottom: {label, black, marked}.
var rows: Array = []
var steps := 16
var steps_per_beat := 4
var beats_per_bar := 4
## Notes: {step, len, row, vel, src} where src is the song note it came from.
var notes: Array = []
## Other parts' notes, drawn faintly: {step, len, row}.
var ghost_notes: Array = []
var colour := Color("f5b942")
var cell := Vector2(22, 18)
## Length of notes the Draw tool adds, in steps.
var draw_length := 1
var show_velocity := true:
	set(v):
		show_velocity = v
		_layout()
## Indexes into [member notes].
var selected: Dictionary = {}
var range_from := -1
var range_to := -1
var cursor_step := 0
var scroll := Vector2.ZERO
var playhead_step := -1.0:
	set(v):
		if v != playhead_step:
			playhead_step = v
			queue_redraw()
## Keys lit by live playing, by row.
var lit_rows: Dictionary = {}

enum _Drag { NONE, NEW, MOVE, RESIZE, BOX, ERASE, RANGE, VELOCITY, KEY, PAN }

var _drag := _Drag.NONE
var _press_pos := Vector2.ZERO
var _press_cell := Vector2i.ZERO
var _moved := false
var _snapshot: Array = []
var _box_end := Vector2.ZERO
var _active_note := -1
var _key_row := -1
var _touches: Dictionary = {}
var _pinch_distance := 0.0
var _changed := false

var _hbar: HScrollBar
var _vbar: VScrollBar


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_CLICK
	clip_contents = true
	_hbar = HScrollBar.new()
	_vbar = VScrollBar.new()
	add_child(_hbar, false, Node.INTERNAL_MODE_FRONT)
	add_child(_vbar, false, Node.INTERNAL_MODE_FRONT)
	_hbar.value_changed.connect(func(v: float) -> void:
		scroll.x = v
		queue_redraw())
	_vbar.value_changed.connect(func(v: float) -> void:
		scroll.y = v
		queue_redraw())
	resized.connect(_layout)
	_layout()


## Shows a new part or section. Keeps the scroll position.
func set_view(row_list: Array, step_count: int, spb: int, bpb: int, note_list: Array, tint: Color) -> void:
	rows = row_list
	steps = maxi(step_count, 1)
	steps_per_beat = maxi(spb, 1)
	beats_per_bar = maxi(bpb, 1)
	notes = note_list
	colour = tint
	selected.clear()
	if range_to > steps:
		set_range(-1, -1)
	cursor_step = clampi(cursor_step, 0, steps - 1)
	_drag = _Drag.NONE
	_layout()
	queue_redraw()


func set_range(from: int, to: int) -> void:
	if from >= 0 and to > from:
		range_from = clampi(from, 0, steps)
		range_to = clampi(to, range_from + 1, steps)
	else:
		range_from = -1
		range_to = -1
	range_changed.emit(range_from, range_to)
	queue_redraw()


func set_zoom(width: float) -> void:
	var centre := (scroll.x + _grid_size().x * 0.5) / cell.x
	cell.x = clampf(width, MIN_CELL, MAX_CELL)
	_layout()
	_set_scroll(Vector2(centre * cell.x - _grid_size().x * 0.5, scroll.y))


## Scrolls so [param row] is in the middle.
func centre_on_row(row: int) -> void:
	_layout()
	_set_scroll(Vector2(scroll.x, (row + 0.5) * cell.y - _grid_size().y * 0.5))


func select_all() -> void:
	selected.clear()
	for i in notes.size():
		selected[i] = true
	selection_changed.emit(selected.size())
	queue_redraw()


func clear_selection() -> void:
	if selected.is_empty():
		return
	selected.clear()
	selection_changed.emit(0)
	queue_redraw()


## The selected notes' indexes, or every note in the picked bars, or none.
func target_indexes() -> Array:
	if not selected.is_empty():
		return selected.keys()
	var out: Array = []
	if range_from >= 0:
		for i in notes.size():
			if int(notes[i]["step"]) >= range_from and int(notes[i]["step"]) < range_to:
				out.append(i)
	return out


## Applies [param change] (takes a note dictionary) to the given notes and
## reports the edit.
func change_notes(indexes: Array, change: Callable) -> void:
	if indexes.is_empty():
		return
	for i in indexes:
		change.call(notes[i])
	_emit_edit()


func delete_notes(indexes: Array) -> void:
	if indexes.is_empty():
		return
	indexes.sort()
	for k in range(indexes.size() - 1, -1, -1):
		notes.remove_at(int(indexes[k]))
	selected.clear()
	selection_changed.emit(0)
	_emit_edit()


# Geometry --------------------------------------------------------------------

func _grid_origin() -> Vector2:
	return Vector2(KEYS_WIDTH, RULER_HEIGHT)


func _grid_size() -> Vector2:
	var bar := BAR
	return Vector2(maxf(size.x - KEYS_WIDTH - bar, 1.0), maxf(size.y - RULER_HEIGHT - _velocity_height() - bar, 1.0))


func _velocity_height() -> float:
	return VELOCITY_HEIGHT if show_velocity else 0.0


func _content_size() -> Vector2:
	return Vector2(steps * cell.x, rows.size() * cell.y)


func _layout() -> void:
	if _hbar == null:
		return
	var grid := _grid_size()
	var content := _content_size()
	_hbar.position = Vector2(KEYS_WIDTH, size.y - BAR)
	_hbar.size = Vector2(grid.x, BAR)
	_vbar.position = Vector2(size.x - BAR, RULER_HEIGHT)
	_vbar.size = Vector2(BAR, grid.y)
	_hbar.max_value = content.x
	_hbar.page = grid.x
	_vbar.max_value = content.y
	_vbar.page = grid.y
	_hbar.visible = content.x > grid.x
	_vbar.visible = content.y > grid.y
	_set_scroll(scroll)


func _set_scroll(value: Vector2) -> void:
	var grid := _grid_size()
	var content := _content_size()
	scroll = Vector2(clampf(value.x, 0.0, maxf(content.x - grid.x, 0.0)), clampf(value.y, 0.0, maxf(content.y - grid.y, 0.0)))
	if _hbar:
		_hbar.set_value_no_signal(scroll.x)
		_vbar.set_value_no_signal(scroll.y)
	queue_redraw()


## Step and row under a point in the grid (may be outside the content).
func _cell_at(point: Vector2) -> Vector2i:
	var p := point - _grid_origin() + scroll
	return Vector2i(floori(p.x / cell.x), floori(p.y / cell.y))


func _area_at(point: Vector2) -> String:
	var grid := _grid_size()
	if point.y < RULER_HEIGHT:
		return "ruler" if point.x >= KEYS_WIDTH else "corner"
	if point.y < RULER_HEIGHT + grid.y:
		if point.x < KEYS_WIDTH:
			return "keys"
		return "grid" if point.x < KEYS_WIDTH + grid.x else ""
	if show_velocity and point.y < RULER_HEIGHT + grid.y + VELOCITY_HEIGHT and point.x >= KEYS_WIDTH:
		return "velocity"
	return ""


func _note_rect(n: Dictionary) -> Rect2:
	var origin := _grid_origin() - scroll
	return Rect2(origin.x + int(n["step"]) * cell.x + 1.0, origin.y + int(n["row"]) * cell.y + 2.0,
		maxf(int(n["len"]) * cell.x - 2.0, 3.0), cell.y - 4.0)


## The topmost note under a point, or -1.
func note_at(point: Vector2) -> int:
	for i in range(notes.size() - 1, -1, -1):
		if _note_rect(notes[i]).grow(1.0).has_point(point):
			return i
	return -1


func _on_edge(i: int, point: Vector2) -> bool:
	var rect := _note_rect(notes[i])
	return point.x >= rect.end.x - minf(EDGE, rect.size.x * 0.4)


# Input -----------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_on_touch(event)
		return
	if event is InputEventScreenDrag:
		_on_screen_drag(event)
		return
	if _drag == _Drag.PAN:
		return
	if event is InputEventMouseButton:
		_on_mouse_button(event)
	elif event is InputEventMouseMotion and _drag != _Drag.NONE:
		_on_drag(event.position)
		accept_event()
	elif event is InputEventPanGesture:
		_set_scroll(scroll + event.delta * 12.0)
		accept_event()
	elif event is InputEventMagnifyGesture:
		set_zoom(cell.x * event.factor)
		accept_event()
	elif event is InputEventKey and event.pressed:
		_on_key(event)


func _on_mouse_button(event: InputEventMouseButton) -> void:
	if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
		var amount := (1.0 if event.button_index in [MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_RIGHT] else -1.0) * maxf(event.factor, 1.0)
		var sideways: bool = event.shift_pressed or event.button_index in [MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]
		if event.ctrl_pressed or event.meta_pressed:
			set_zoom(cell.x * (0.9 if amount > 0.0 else 1.1))
		elif sideways:
			_set_scroll(scroll + Vector2(amount * cell.x * 2.0, 0.0))
		else:
			_set_scroll(scroll + Vector2(0.0, amount * cell.y * 2.0))
		accept_event()
		return
	if event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed and _area_at(event.position) == "grid":
			_begin(event.position, _Drag.ERASE)
			_erase_at(event.position)
		elif not event.pressed and _drag == _Drag.ERASE:
			_end()
		accept_event()
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.pressed:
		if is_inside_tree():
			grab_focus()
		_on_press(event.position, event.shift_pressed or event.ctrl_pressed or event.meta_pressed)
	else:
		_end()
	accept_event()


func _on_press(point: Vector2, add: bool) -> void:
	var area := _area_at(point)
	var at := _cell_at(point)
	match area:
		"keys":
			if at.y >= 0 and at.y < rows.size():
				_begin(point, _Drag.KEY)
				_key_row = at.y
				row_pressed.emit(at.y)
		"ruler":
			_begin(point, _Drag.RANGE)
			_update_range(point)
		"velocity":
			_begin(point, _Drag.VELOCITY)
			_set_velocity_at(point)
		"grid":
			if at.x < 0 or at.x >= steps or at.y < 0 or at.y >= rows.size():
				return
			var hit := note_at(point)
			match tool:
				Tool.ERASE:
					_begin(point, _Drag.ERASE)
					_erase_at(point)
				Tool.DRAW:
					if hit >= 0:
						_begin(point, _Drag.RESIZE if _on_edge(hit, point) else _Drag.MOVE)
						_active_note = hit
						selected = {hit: true}
						row_pressed.emit(int(notes[hit]["row"]))
					else:
						_begin(point, _Drag.NEW)
						notes.append({"step": at.x, "len": mini(draw_length, steps - at.x), "row": at.y, "vel": 100, "src": []})
						_active_note = notes.size() - 1
						selected = {_active_note: true}
						_changed = true
						row_pressed.emit(at.y)
					queue_redraw()
				Tool.SELECT:
					if hit >= 0:
						if add:
							if selected.has(hit):
								selected.erase(hit)
							else:
								selected[hit] = true
						elif not selected.has(hit):
							selected = {hit: true}
						_begin(point, _Drag.RESIZE if _on_edge(hit, point) else _Drag.MOVE)
						_active_note = hit
						row_pressed.emit(int(notes[hit]["row"]))
					else:
						if not add:
							selected.clear()
						_begin(point, _Drag.BOX)
						_box_end = point
					selection_changed.emit(selected.size())
					queue_redraw()


func _begin(point: Vector2, kind: _Drag) -> void:
	_drag = kind
	_press_pos = point
	_press_cell = _cell_at(point)
	_moved = false
	_changed = false
	_snapshot = notes.duplicate(true)


func _on_drag(point: Vector2) -> void:
	if point.distance_to(_press_pos) > 6.0:
		_moved = true
	var at := _cell_at(point)
	var delta := at - _press_cell
	match _drag:
		_Drag.KEY:
			var row := clampi(at.y, 0, rows.size() - 1)
			if row != _key_row:
				row_released.emit(_key_row)
				_key_row = row
				row_pressed.emit(row)
		_Drag.RANGE:
			_update_range(point)
		_Drag.VELOCITY:
			_set_velocity_at(point)
		_Drag.ERASE:
			_erase_at(point)
		_Drag.BOX:
			_box_end = point
			queue_redraw()
		_Drag.NEW:
			if _moved and _active_note >= 0:
				var n: Dictionary = notes[_active_note]
				n["len"] = clampi(at.x - int(n["step"]) + 1, 1, steps - int(n["step"]))
				queue_redraw()
		_Drag.RESIZE:
			if not _moved:
				return
			for i in _drag_set():
				var before: Dictionary = _snapshot[i]
				notes[i]["len"] = clampi(int(before["len"]) + delta.x, 1, steps - int(before["step"]))
			_changed = true
			queue_redraw()
		_Drag.MOVE:
			if not _moved:
				return
			var set := _drag_set()
			# Keep the whole group inside the grid.
			var dx := delta.x
			var dy := delta.y
			for i in set:
				var before: Dictionary = _snapshot[i]
				dx = clampi(dx, -int(before["step"]), steps - int(before["step"]) - 1)
				dy = clampi(dy, -int(before["row"]), rows.size() - 1 - int(before["row"]))
			var row_moved := false
			for i in set:
				var before: Dictionary = _snapshot[i]
				var new_row := int(before["row"]) + dy
				if new_row != int(notes[i]["row"]) and i == _active_note:
					row_moved = true
				notes[i]["step"] = int(before["step"]) + dx
				notes[i]["row"] = new_row
				notes[i]["len"] = mini(int(before["len"]), steps - int(notes[i]["step"]))
			if row_moved:
				row_pressed.emit(int(notes[_active_note]["row"]))
			_changed = true
			queue_redraw()


func _drag_set() -> Array:
	if selected.has(_active_note):
		return selected.keys()
	return [_active_note]


func _end() -> void:
	match _drag:
		_Drag.KEY:
			row_released.emit(_key_row)
			_key_row = -1
		_Drag.RANGE:
			if not _moved:
				# A tap on the picked bars clears them; elsewhere picks one bar.
				var bar := beats_per_bar * steps_per_beat
				var step := _cell_at(_press_pos).x
				if range_from >= 0 and step >= range_from and step < range_to and range_to - range_from == bar:
					set_range(-1, -1)
		_Drag.BOX:
			var rect := Rect2(_press_pos, _box_end - _press_pos).abs()
			if _moved:
				for i in notes.size():
					if rect.intersects(_note_rect(notes[i])):
						selected[i] = true
			else:
				cursor_step = clampi(_press_cell.x, 0, steps - 1)
				cursor_changed.emit(cursor_step)
			selection_changed.emit(selected.size())
			queue_redraw()
		_Drag.MOVE, _Drag.RESIZE:
			if _active_note >= 0:
				row_released.emit(int(notes[_active_note]["row"]))
			if not _moved and tool == Tool.DRAW and _active_note >= 0:
				# A tap on a note with the Draw tool removes it.
				notes.remove_at(_active_note)
				selected.clear()
				_changed = true
		_Drag.NEW:
			if _active_note >= 0:
				row_released.emit(int(notes[_active_note]["row"]))
	var was := _drag
	_drag = _Drag.NONE
	_active_note = -1
	if _changed and was != _Drag.PAN:
		_emit_edit()
	queue_redraw()


func _emit_edit() -> void:
	_changed = false
	notes_edited.emit(notes.duplicate(true))


func _erase_at(point: Vector2) -> void:
	var hit := note_at(point)
	if hit >= 0:
		notes.remove_at(hit)
		selected.clear()
		_changed = true
		queue_redraw()


func _update_range(point: Vector2) -> void:
	var bar := beats_per_bar * steps_per_beat
	var a := clampi(_press_cell.x, 0, steps - 1)
	var b := clampi(_cell_at(point).x, 0, steps - 1)
	var from := mini(a, b) / bar * bar
	var to := mini((maxi(a, b) / bar + 1) * bar, steps)
	if from != range_from or to != range_to:
		set_range(from, to)


func _set_velocity_at(point: Vector2) -> void:
	var step := _cell_at(point).x
	var top := RULER_HEIGHT + _grid_size().y + 4.0
	var value := clampi(int(roundf((1.0 - (point.y - top) / (VELOCITY_HEIGHT - 8.0)) * 127.0)), 1, 127)
	var any_selected := false
	for i in selected:
		if int(notes[i]["step"]) == step:
			any_selected = true
	for i in notes.size():
		var n: Dictionary = notes[i]
		if int(n["step"]) == step and (not any_selected or selected.has(i)) and int(n["vel"]) != value:
			n["vel"] = value
			_changed = true
	queue_redraw()


func _on_key(event: InputEventKey) -> void:
	var keys := target_indexes() if not selected.is_empty() else []
	match event.keycode:
		KEY_DELETE, KEY_BACKSPACE:
			delete_notes(selected.keys())
		KEY_A:
			if event.ctrl_pressed or event.meta_pressed:
				select_all()
			else:
				return
		KEY_UP, KEY_DOWN:
			var by := (-12 if event.shift_pressed else -1) * (1 if event.keycode == KEY_UP else -1)
			change_notes(keys, func(n: Dictionary) -> void: n["row"] = clampi(int(n["row"]) + by, 0, rows.size() - 1))
		KEY_LEFT, KEY_RIGHT:
			var by := 1 if event.keycode == KEY_RIGHT else -1
			change_notes(keys, func(n: Dictionary) -> void: n["step"] = clampi(int(n["step"]) + by, 0, steps - 1))
		KEY_ESCAPE:
			clear_selection()
			set_range(-1, -1)
		_:
			return
	accept_event()


func _on_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_touches[event.index] = event.position
	else:
		_touches.erase(event.index)
	if _touches.size() >= 2 and _drag != _Drag.PAN:
		# A second finger: undo what the first one started and pan instead.
		if _drag != _Drag.NONE:
			notes = _snapshot
			if _key_row >= 0:
				row_released.emit(_key_row)
				_key_row = -1
		_drag = _Drag.PAN
		_changed = false
		_pinch_distance = _touch_spread()
		queue_redraw()
	elif _touches.is_empty() and _drag == _Drag.PAN:
		_drag = _Drag.NONE
	accept_event()


func _on_screen_drag(event: InputEventScreenDrag) -> void:
	if not _touches.has(event.index):
		return
	_touches[event.index] = event.position
	if _drag != _Drag.PAN:
		return
	_set_scroll(scroll - event.relative / float(maxi(_touches.size(), 1)))
	var spread := _touch_spread()
	if _pinch_distance > 20.0 and spread > 20.0 and absf(spread - _pinch_distance) > 12.0:
		set_zoom(cell.x * spread / _pinch_distance)
		_pinch_distance = spread
	accept_event()


func _touch_spread() -> float:
	var points := _touches.values()
	if points.size() < 2:
		return 0.0
	return absf((points[0] as Vector2).x - (points[1] as Vector2).x)


# Drawing ---------------------------------------------------------------------

func _draw() -> void:
	var font := get_theme_default_font()
	var origin := _grid_origin()
	var grid := _grid_size()
	var grid_rect := Rect2(origin, grid)
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND)
	var first_row := maxi(int(scroll.y / cell.y), 0)
	var last_row := mini(int((scroll.y + grid.y) / cell.y) + 1, rows.size())
	var first_step := maxi(int(scroll.x / cell.x), 0)
	var last_step := mini(int((scroll.x + grid.x) / cell.x) + 1, steps)
	var bar_len := steps_per_beat * beats_per_bar
	var content_right := minf(origin.x + steps * cell.x - scroll.x, origin.x + grid.x)

	# Rows.
	for r in range(first_row, last_row):
		var y := origin.y + r * cell.y - scroll.y
		var info: Dictionary = rows[r]
		var row_rect := Rect2(origin.x, y, content_right - origin.x, cell.y).intersection(grid_rect)
		if info.get("black", false):
			draw_rect(row_rect, BLACK_ROW)
		if info.get("marked", false):
			draw_rect(row_rect, MARKED_ROW)
		draw_line(Vector2(origin.x, maxf(y, origin.y)), Vector2(content_right, maxf(y, origin.y)), LINE)
	# Picked bars.
	if range_from >= 0:
		var x0 := maxf(origin.x + range_from * cell.x - scroll.x, origin.x)
		var x1 := minf(origin.x + range_to * cell.x - scroll.x, content_right)
		if x1 > x0:
			draw_rect(Rect2(x0, origin.y, x1 - x0, grid.y), RANGE)
	# Columns.
	for s in range(first_step, last_step + 1):
		var x := origin.x + s * cell.x - scroll.x
		if x < origin.x or x > origin.x + grid.x:
			continue
		var c := LINE
		if s % bar_len == 0:
			c = BAR_LINE
		elif s % steps_per_beat == 0:
			c = BEAT_LINE
		draw_line(Vector2(x, origin.y), Vector2(x, origin.y + grid.y), c)
	# Ghost notes, then notes.
	var ghost := Color(1, 1, 1, 0.1)
	for n in ghost_notes:
		var rect := _note_rect(n).intersection(grid_rect)
		if rect.has_area():
			draw_rect(rect, ghost)
	for i in notes.size():
		var n: Dictionary = notes[i]
		var full := _note_rect(n)
		var rect := full.intersection(grid_rect)
		if not rect.has_area():
			continue
		var c := colour
		c.a = 0.45 + 0.55 * float(n["vel"]) / 127.0
		draw_rect(rect, c)
		if selected.has(i):
			draw_rect(rect, Color.WHITE, false, 2.0)
		else:
			draw_rect(rect, colour.darkened(0.4), false, 1.0)
		if full.size.x > 34.0 and cell.y >= 14.0 and rect.size.x > 30.0:
			draw_string(font, Vector2(rect.position.x + 3.0, rect.end.y - 3.0), str(rows[int(n["row"])].get("label", "")) if int(n["row"]) < rows.size() else "",
				HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 4.0, 10, Color(0, 0, 0, 0.75))
	# Cursor and playhead.
	var cx := origin.x + cursor_step * cell.x - scroll.x
	if cx >= origin.x and cx <= origin.x + grid.x:
		draw_line(Vector2(cx, origin.y), Vector2(cx, origin.y + grid.y), Color(0.32, 0.82, 0.75, 0.6), 1.0)
	if playhead_step >= 0.0 and playhead_step < steps:
		var px := origin.x + playhead_step * cell.x - scroll.x
		if px >= origin.x and px <= origin.x + grid.x:
			draw_line(Vector2(px, 0), Vector2(px, origin.y + grid.y + _velocity_height()), Color.WHITE, 2.0)
	if _drag == _Drag.BOX and _moved:
		draw_rect(Rect2(_press_pos, _box_end - _press_pos).abs(), SELECT_BOX, false, 1.0)

	# Keyboard.
	draw_rect(Rect2(0, origin.y, KEYS_WIDTH, grid.y), Color("16171e"))
	for r in range(first_row, last_row):
		var y := origin.y + r * cell.y - scroll.y
		var info: Dictionary = rows[r]
		var key_rect := Rect2(0, y, KEYS_WIDTH - 2.0, cell.y - 1.0).intersection(Rect2(0, origin.y, KEYS_WIDTH, grid.y))
		if not key_rect.has_area():
			continue
		var key_colour := Color("2a2c36") if info.get("black", false) else Color("d8dae2")
		if lit_rows.has(r) or (_drag == _Drag.KEY and _key_row == r):
			key_colour = colour
		draw_rect(key_rect, key_colour)
		if cell.y >= 11.0 and (info.get("marked", false) or not info.get("black", false) or cell.y >= 16.0):
			var text_colour := Color.WHITE if info.get("black", false) else Color("101116")
			draw_string(font, Vector2(4, y + cell.y - maxf((cell.y - 10.0) * 0.5, 2.0)), str(info.get("label", "")),
				HORIZONTAL_ALIGNMENT_LEFT, KEYS_WIDTH - 8, 10, text_colour)

	# Ruler.
	draw_rect(Rect2(0, 0, size.x, RULER_HEIGHT), Color("16171e"))
	for s in range(first_step, last_step):
		if s % bar_len != 0:
			continue
		var x := origin.x + s * cell.x - scroll.x
		if x < origin.x - 1.0:
			continue
		draw_line(Vector2(x, 4), Vector2(x, RULER_HEIGHT), BAR_LINE)
		draw_string(font, Vector2(x + 4, RULER_HEIGHT - 6), str(s / bar_len + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, MUTED)
	if range_from >= 0:
		var x0 := maxf(origin.x + range_from * cell.x - scroll.x, origin.x)
		var x1 := minf(origin.x + range_to * cell.x - scroll.x, content_right)
		if x1 > x0:
			draw_rect(Rect2(x0, RULER_HEIGHT - 4, x1 - x0, 4), colour)

	# Velocity lane.
	if show_velocity:
		var top := origin.y + grid.y
		draw_rect(Rect2(0, top, size.x, VELOCITY_HEIGHT), Color("14151b"))
		draw_line(Vector2(0, top), Vector2(size.x, top), BAR_LINE)
		draw_string(font, Vector2(4, top + 16), "Vel", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, MUTED)
		var lane := VELOCITY_HEIGHT - 8.0
		for i in notes.size():
			var n: Dictionary = notes[i]
			var x := origin.x + int(n["step"]) * cell.x - scroll.x + 2.0
			if x < origin.x or x > origin.x + grid.x:
				continue
			var h := lane * float(n["vel"]) / 127.0
			var c := Color.WHITE if selected.has(i) else colour
			draw_rect(Rect2(x, top + 4.0 + lane - h, maxf(minf(cell.x - 4.0, 6.0), 2.0), h), c)
