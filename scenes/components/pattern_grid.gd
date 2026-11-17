class_name PatternGrid
extends Control
## A note grid for one part of one section: a column per step, a row per
## pitch (or drum), the notes as bars. Tap a cell to add or remove a note.

signal cell_pressed(step: int, row: int)

const CELL := Vector2(26, 22)
const LABEL_WIDTH := 64.0
const BACKGROUND := Color("101116")
const BEAT_SHADE := Color(1, 1, 1, 0.035)
const LINE := Color(1, 1, 1, 0.07)
const BAR_LINE := Color(1, 1, 1, 0.22)
const MUTED := Color("9a9daa")

## Row labels, top to bottom.
var row_labels: PackedStringArray = []
## Rows drawn a little lighter, such as the C of each octave.
var marked_rows: PackedInt32Array = []
var steps := 16
var steps_per_beat := 4
var beats_per_bar := 4
var colour := Color("f5b942")
## Notes as [first_step, length, row].
var notes: Array = []
## The step playing, or -1.
var playhead_step := -1.0:
	set(v):
		if v != playhead_step:
			playhead_step = v
			queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_resize()


func set_view(labels: PackedStringArray, step_count: int, spb: int, bpb: int, note_rows: Array, tint: Color, marked: PackedInt32Array = []) -> void:
	row_labels = labels
	steps = maxi(step_count, 1)
	steps_per_beat = maxi(spb, 1)
	beats_per_bar = maxi(bpb, 1)
	notes = note_rows
	colour = tint
	marked_rows = marked
	_resize()
	queue_redraw()


## The cell under a point, as Vector2i(step, row), or (-1, -1).
func cell_at(point: Vector2) -> Vector2i:
	var x := point.x - LABEL_WIDTH
	if x < 0.0 or point.y < 0.0:
		return Vector2i(-1, -1)
	var step := int(x / CELL.x)
	var row := int(point.y / CELL.y)
	if step >= steps or row >= row_labels.size():
		return Vector2i(-1, -1)
	return Vector2i(step, row)


func _resize() -> void:
	custom_minimum_size = Vector2(LABEL_WIDTH + steps * CELL.x, maxi(row_labels.size(), 1) * CELL.y)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cell := cell_at(event.position)
		if cell.x >= 0:
			cell_pressed.emit(cell.x, cell.y)
			accept_event()


func _draw() -> void:
	var rows := row_labels.size()
	var height := rows * CELL.y
	var width := steps * CELL.x
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND)
	var font := get_theme_default_font()
	for r in rows:
		var y := r * CELL.y
		if marked_rows.has(r):
			draw_rect(Rect2(LABEL_WIDTH, y, width, CELL.y), Color(1, 1, 1, 0.05))
		draw_string(font, Vector2(6, y + CELL.y - 6), row_labels[r], HORIZONTAL_ALIGNMENT_LEFT, LABEL_WIDTH - 8, 12,
			Color.WHITE if marked_rows.has(r) else MUTED)
		draw_line(Vector2(LABEL_WIDTH, y), Vector2(LABEL_WIDTH + width, y), LINE)
	for s in steps + 1:
		var x := LABEL_WIDTH + s * CELL.x
		if s < steps and (s / steps_per_beat) % 2 == 1:
			draw_rect(Rect2(x, 0, CELL.x, height), BEAT_SHADE)
		var on_bar := s % (steps_per_beat * beats_per_bar) == 0
		draw_line(Vector2(x, 0), Vector2(x, height), BAR_LINE if on_bar else LINE)
	for n in notes:
		var x := LABEL_WIDTH + int(n[0]) * CELL.x + 2.0
		var w := int(n[1]) * CELL.x - 4.0
		var y := int(n[2]) * CELL.y + 3.0
		draw_rect(Rect2(x, y, maxf(w, 4.0), CELL.y - 6.0), colour)
	if playhead_step >= 0.0 and playhead_step < steps:
		var px := LABEL_WIDTH + playhead_step * CELL.x
		draw_line(Vector2(px, 0), Vector2(px, height), Color.WHITE, 2.0)
