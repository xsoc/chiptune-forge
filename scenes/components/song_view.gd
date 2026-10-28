class_name SongView
extends Control
## A piano-roll overview of the song: one lane per channel, section markers
## and a playhead. Click to seek.

signal seek_requested(step: float)

const LANE_COLOURS := [
	Color("f5b942"), Color("ffd27a"), Color("52d1c0"), Color("7aa2ff"),
	Color("c792ea"), Color("ff6b6b"), Color("9a9daa"),
]

var song: ChipSong
var playhead_step := -1.0:
	set(v):
		playhead_step = v
		queue_redraw()
## Channels drawn dimmed, such as muted layers.
var dimmed: Dictionary = {}

var _lanes: Array = [] # per channel: Array of [start_step, length, pitch]
var _sections: Array = [] # [start_step, name]
var _total_steps := 1
var _pitch_range := Vector2i(36, 96)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size.y = maxf(custom_minimum_size.y, 120)


func set_song(value: ChipSong) -> void:
	song = value
	_lanes.clear()
	_sections.clear()
	if song == null:
		queue_redraw()
		return
	var data := song.data
	var channel_count: int = data["channels"].size()
	for c in channel_count:
		_lanes.append([])
	var start := 0
	var lo := 127
	var hi := 0
	for index in data["order"]:
		var section: Dictionary = data["sections"][int(index)]
		_sections.append([start, section["name"]])
		var ids: Array = section["patterns"]
		for c in mini(ids.size(), channel_count):
			if int(ids[c]) < 0:
				continue
			for note in data["patterns"][int(ids[c])]["notes"]:
				_lanes[c].append([start + int(note[0]), int(note[1]), int(note[2])])
				if c < 5:
					lo = mini(lo, int(note[2]))
					hi = maxi(hi, int(note[2]))
		start += int(section["length"])
	_total_steps = maxi(start, 1)
	_pitch_range = Vector2i(lo, maxi(hi, lo + 12))
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		seek_requested.emit(clampf(event.position.x / size.x, 0.0, 1.0) * _total_steps)
		accept_event()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("101116"))
	if song == null:
		var font := get_theme_default_font()
		draw_string(font, Vector2(12, size.y / 2), "Press Generate to make a song", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("9a9daa"))
		return
	var lanes := _lanes.size()
	var lane_h := size.y / maxf(lanes, 1)
	var sx := size.x / float(_total_steps)
	for s in _sections:
		var x: float = s[0] * sx
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color(1, 1, 1, 0.08))
	for c in lanes:
		var colour: Color = LANE_COLOURS[c % LANE_COLOURS.size()]
		if dimmed.get(c, false):
			colour = Color(colour, 0.2)
		var top := c * lane_h
		var span := maxf(_pitch_range.y - _pitch_range.x, 1)
		for note in _lanes[c]:
			var x: float = note[0] * sx
			var w := maxf(note[1] * sx - 0.5, 1.0)
			var y := top + 2.0
			var h := lane_h - 4.0
			if c < 5:
				var t := clampf((note[2] - _pitch_range.x) / span, 0.0, 1.0)
				y = top + (1.0 - t) * (lane_h - 4.0) + 1.0
				h = maxf(lane_h / 10.0, 2.0)
			draw_rect(Rect2(x, y, w, h), colour)
	if playhead_step >= 0.0:
		var px := playhead_step * sx
		draw_line(Vector2(px, 0), Vector2(px, size.y), Color.WHITE, 2.0)
