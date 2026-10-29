extends Control
## Root scene: header with the Music / Sound FX switch, navigation, the
## screens, and the player bar. Picks the phone, tablet or desktop layout from
## the window width, and wires the screens to the autoloads.

enum Layout { PHONE, TABLET, DESKTOP }

const PHONE_MAX := 600.0
const TABLET_MAX := 1100.0

## Navigation per mode: [label, screen node name].
const NAV := {
	"music": [["Generate", "GenerateScreen"], ["Layers", "LayersScreen"], ["Export", "ExportScreen"], ["Library", "LibraryScreen"]],
	"sfx": [["Create", "SfxScreen"], ["Kit", "KitScreen"], ["Export", "ExportScreen"], ["Library", "LibraryScreen"]],
}

var layout := Layout.DESKTOP
var _screen := {"music": "GenerateScreen", "sfx": "SfxScreen"}
var _ui_scale := 1.0


func _ready() -> void:
	_ui_scale = _detect_ui_scale()
	get_tree().root.size_changed.connect(_on_window_resized)
	_on_window_resized()

	%MusicMode.pressed.connect(func() -> void: AppState.mode = "music")
	%SfxMode.pressed.connect(func() -> void: AppState.mode = "sfx")
	AppState.mode_changed.connect(_on_mode_changed)
	AppState.song_changed.connect(_on_song_changed)
	AppState.settings_changed.connect(_on_settings_changed)

	%PlayerBar.play_toggled.connect(_on_play_toggled)
	%PlayerBar.seek_requested.connect(_on_seek_fraction)
	%PlayerBar.loop_toggled.connect(func(on: bool) -> void: AudioService.music.loop = on)
	%GenerateScreen.seek_requested.connect(_play_from_step)
	%LibraryScreen.entry_opened.connect(func(kind: String) -> void:
		_show_screen("GenerateScreen" if kind == "song" else "SfxScreen"))
	AudioService.playback_started.connect(func() -> void: %PlayerBar.set_playing(true))
	AudioService.playback_stopped.connect(func() -> void: %PlayerBar.set_playing(false))

	if not AudioService.audio_unlocked:
		%SoundPrompt.visible = true
		%SoundPrompt.pressed.connect(func() -> void:
			AudioService.audio_unlocked = true
			%SoundPrompt.visible = false)

	_on_mode_changed(AppState.mode)
	_on_settings_changed()
	if AppState.song == null:
		AppState.generate()


func _process(_delta: float) -> void:
	var music: ChipMusicPlayer = AudioService.music
	var song: ChipSong = AppState.song
	if song == null:
		return
	if music.is_playing():
		var seconds := music.get_position()
		var step := seconds / song.get_step_seconds()
		%GenerateScreen.set_playhead(step)
		%LayersScreen.set_playhead(step)
		%PlayerBar.set_time(seconds, song.get_length_seconds())
	else:
		%GenerateScreen.set_playhead(-1.0)
		%LayersScreen.set_playhead(-1.0)


func _detect_ui_scale() -> float:
	var scale := DisplayServer.screen_get_scale()
	if OS.has_feature("mobile"):
		scale = maxf(scale, DisplayServer.screen_get_dpi() / 160.0)
	if OS.has_feature("web"):
		var ratio: Variant = JavaScriptBridge.eval("window.devicePixelRatio || 1", true)
		if ratio != null:
			scale = float(ratio)
	return clampf(scale, 1.0, 4.0)


## Overrides the detected UI scale, for tests and screenshots.
func set_ui_scale(value: float) -> void:
	_ui_scale = clampf(value, 1.0, 4.0)
	_on_window_resized()


func _on_window_resized() -> void:
	# Keep logical pixels equal to physical pixels divided by the UI scale, so
	# breakpoints mean the same thing on every screen density.
	var window := get_window()
	var physical := Vector2(window.size)
	window.content_scale_size = Vector2i((physical / _ui_scale).round())
	var width := physical.x / _ui_scale
	var next := Layout.DESKTOP
	if width < PHONE_MAX:
		next = Layout.PHONE
	elif width < TABLET_MAX:
		next = Layout.TABLET
	if next != layout or not is_node_ready():
		layout = next
		_apply_layout()


func _apply_layout() -> void:
	var phone := layout == Layout.PHONE
	%TopNav.visible = not phone
	%BottomNav.visible = phone
	%AppName.text = "Forge" if phone else "Chiptune Forge"
	%SfxMode.text = "SFX" if phone else "Sound FX"
	%PlayerBar.set_compact(phone)


func _on_mode_changed(mode: String) -> void:
	%MusicMode.set_pressed_no_signal(mode == "music")
	%SfxMode.set_pressed_no_signal(mode == "sfx")
	%PlayerBar.visible = mode == "music"
	_build_nav(mode)
	_show_screen(_screen[mode])


func _build_nav(mode: String) -> void:
	for row in [%TopNav, %Row]:
		for child in row.get_children():
			child.queue_free()
	var group := ButtonGroup.new()
	var bottom_group := ButtonGroup.new()
	for entry in NAV[mode]:
		for target in [[%TopNav, group], [%Row, bottom_group]]:
			var button := Button.new()
			button.text = entry[0]
			button.toggle_mode = true
			button.button_group = target[1]
			button.theme_type_variation = &"NavButton" if mode == "music" else &"SfxNavButton"
			button.custom_minimum_size.y = 44
			button.set_meta("screen", entry[1])
			if target[0] == %Row:
				button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.pressed.connect(_show_screen.bind(entry[1]))
			target[0].add_child(button)


func _show_screen(screen_name: String) -> void:
	_screen[AppState.mode] = screen_name
	for child in %Screens.get_children():
		child.visible = child.name == screen_name
	for row in [%TopNav, %Row]:
		for button in row.get_children():
			if button is Button and not button.is_queued_for_deletion():
				button.set_pressed_no_signal(button.get_meta("screen") == screen_name)


func _on_song_changed(song: ChipSong) -> void:
	var meta: Dictionary = song.data["meta"]
	%PlayerBar.set_song_info(song.get_title(), "%s · %d BPM · seed %s" % [meta.get("key", ""), int(song.get_bpm()), meta.get("seed", "")])
	%PlayerBar.set_time(0.0, song.get_length_seconds())
	# Keep playing through edits, from about the same place.
	if AudioService.is_playing():
		var step := AudioService.music.get_position() / song.get_step_seconds()
		AudioService.play_song(song, fmod(step, maxf(song.get_length_steps(), 1)))


## With no vibe picked there is no music: stop it and turn off Play.
func _on_settings_changed() -> void:
	var can_play := AppState.can_make_music()
	%PlayerBar.set_play_enabled(can_play)
	if not can_play and AudioService.is_playing():
		AudioService.stop_song()


func _on_play_toggled() -> void:
	if AudioService.is_playing():
		AudioService.stop_song()
	elif AppState.song and AppState.can_make_music():
		AudioService.music.loop = %PlayerBar.is_loop_on()
		AudioService.play_song(AppState.song)


func _on_seek_fraction(fraction: float) -> void:
	if AppState.song:
		_play_from_step(fraction * AppState.song.get_length_steps())


func _play_from_step(step: float) -> void:
	if AppState.song and AppState.can_make_music():
		# Snap to the beat so playback starts cleanly.
		var spb := AppState.song.get_steps_per_beat()
		AudioService.play_song(AppState.song, floorf(step / spb) * spb)
