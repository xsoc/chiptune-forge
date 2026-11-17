class_name AboutDialog
extends Control
## About Chiptune Forge, shown over the app: the version, the project's
## licence, who owns the music, every third-party component with its licence
## (read from THIRD_PARTY.md, which exports include), and the accessibility
## settings. A plain Control rather than a Window, so it lays out the same on
## phones, desktop and the web.

const NOTICES_PATH := "res://THIRD_PARTY.md"


func _ready() -> void:
	%Version.text = "Chiptune Forge %s" % BuildInfo.label()
	%ReduceMotion.button_pressed = AppState.reduce_motion
	%ReduceMotion.toggled.connect(func(on: bool) -> void: AppState.reduce_motion = on)
	%Close.pressed.connect(hide)
	%Dim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			hide())
	%Notices.text = notices_bbcode(FileAccess.get_file_as_string(NOTICES_PATH))


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		hide()
		get_viewport().set_input_as_handled()


## Shows the panel at a size that fits the window, phone or desktop.
func open() -> void:
	var area := get_viewport_rect().size
	%Panel.custom_minimum_size = Vector2(minf(560.0, area.x - 24.0), minf(640.0, area.y * 0.9))
	show()
	%Close.grab_focus.call_deferred()


## The third-party table of THIRD_PARTY.md as BBCode: each component in bold
## with its licence. Falls back to a pointer at the file when it is missing.
static func notices_bbcode(markdown: String) -> String:
	var lines := PackedStringArray()
	for row in markdown.split("\n"):
		if not row.begins_with("| ") or row.begins_with("| Component") or row.begins_with("|---"):
			continue
		var cells := row.split("|")
		if cells.size() < 5:
			continue
		lines.append("[b]%s[/b]: %s" % [_plain(cells[1].strip_edges()), _plain(cells[3].strip_edges())])
	if lines.is_empty():
		return "See THIRD_PARTY.md in the source repository."
	return "\n".join(lines)


static func _plain(cell: String) -> String:
	return cell.replace("`", "").replace("[", "[lb]")
