extends Control
## Export flow: 1 target, 2 limits check, 3 formats. Works for the song in
## Music mode and for the kit (or the current sound) in Sound FX mode.

## Songs at least this long get a note about WAV size and render time.
const LONG_SONG_SECONDS := 270.0

var _target := "modern"
var _job: ExportJob


func _ready() -> void:
	set_process(false)
	_build_targets()
	%Export.pressed.connect(_on_export)
	%Wav.toggled.connect(func(on: bool) -> void: %WavOptions.visible = on and AppState.mode == "music")
	%Godot.toggled.connect(func(on: bool) -> void: %Plugin.disabled = not on)
	AppState.mode_changed.connect(func(_m: String) -> void: refresh())
	AppState.song_changed.connect(func(_s: ChipSong) -> void: refresh())
	AppState.kit_changed.connect(refresh)
	visibility_changed.connect(func() -> void:
		if visible:
			refresh())
	refresh()


func refresh() -> void:
	var music := AppState.mode == "music"
	%Export.theme_type_variation = &"PrimaryButton" if music else &"SfxPrimaryButton"
	%Midi.visible = music
	%WavOptions.visible = music and %Wav.button_pressed
	if music:
		var song: ChipSong = AppState.song
		%What.text = "Exporting the current song." if song else "Generate a song first."
		%Prefix.placeholder_text = ExportJob.sanitize(song.get_title()) if song else "song"
		%Godot.text = "Godot: .chipsong for the Chiptune Forge plugin"
		%Wav.text = "Audio: WAV, 44.1 kHz, loop points included"
		%Export.disabled = song == null
	else:
		var count := AppState.kit.sounds.size()
		%What.text = "Exporting the kit (%d sounds)." % count if count > 0 else "The kit is empty, so this exports the current sound."
		%Prefix.placeholder_text = ExportJob.sanitize(AppState.kit.kit_name)
		%Godot.text = "Godot: .chipkit and .chipsfx for the plugin"
		%Wav.text = "Audio: one WAV per sound"
		%Export.disabled = AppState.sfx == null and count == 0
	_update_report()


func _build_targets() -> void:
	var chips: Dictionary = AppState.catalog.chips
	var ids := chips.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return chips[a].get_meta("order", 0) < chips[b].get_meta("order", 0))
	var group := ButtonGroup.new()
	for id in ids:
		var chip: ChipProfile = chips[id]
		var button := Button.new()
		button.toggle_mode = true
		button.button_group = group
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size.y = 52
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.text = "%s  ·  %s" % [chip.display_name, chip.chip_name]
		button.tooltip_text = chip.description
		button.disabled = not chip.available
		if not chip.available:
			button.text += "  (phase %d)" % chip.phase
		button.button_pressed = id == _target
		button.pressed.connect(func() -> void:
			_target = id
			_update_report())
		%Targets.add_child(button)
	var more := Label.new()
	more.text = "Console targets follow the project plan: Game Boy next, then NES and Master System."
	more.theme_type_variation = &"MutedLabel"
	more.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	%Targets.add_child(more)


func _update_report() -> void:
	var chip: ChipProfile = AppState.catalog.chips.get(_target)
	var lines: Array[String] = []
	if chip:
		lines.append("[b]%s[/b]: %s" % [chip.display_name, chip.description])
	if AppState.mode == "music" and AppState.song:
		var song: ChipSong = AppState.song
		var used := 0
		for c in song.data["channels"].size():
			if _channel_has_notes(song, c):
				used += 1
		lines.append("")
		lines.append("[color=#52d1c0]Fits.[/color] No limits on this target.")
		lines.append("Uses %d of 7 channels, stereo and echo." % used)
		lines.append("Length %d:%02d, loop from %s to %s." % [int(song.get_length_seconds()) / 60, int(song.get_length_seconds()) % 60, _clock(song, song.get_loop_start_step()), _clock(song, song.get_loop_end_step())])
		var seconds := song.get_length_seconds()
		if seconds >= LONG_SONG_SECONDS:
			var mb := seconds * ExportJob.MIX_RATE * 4 / 1048576.0
			lines.append("Long song: each WAV is about %d MB per loop and can take a few minutes to render, more with stems." % int(mb))
	elif AppState.mode == "sfx":
		lines.append("")
		lines.append("[color=#52d1c0]Fits.[/color] Each sound plays on any voice.")
	%Report.text = "\n".join(lines)


func _channel_has_notes(song: ChipSong, channel: int) -> bool:
	for section in song.data["sections"]:
		var ids: Array = section["patterns"]
		if channel < ids.size() and int(ids[channel]) >= 0:
			return true
	return false


func _clock(song: ChipSong, step: int) -> String:
	var s := int(step * song.get_step_seconds())
	return "%d:%02d" % [s / 60, s % 60]


func _on_export() -> void:
	var prefix: String = %Prefix.text if %Prefix.text.strip_edges() != "" else %Prefix.placeholder_text
	var options := {
		"prefix": prefix,
		"godot": %Godot.button_pressed,
		"plugin": %Plugin.button_pressed,
		"wav": %Wav.button_pressed,
		"loops": %Loops.get_selected_id(),
		"stems": %Stems.button_pressed,
		"midi": %Midi.button_pressed,
	}
	if AppState.mode == "music":
		if AppState.song == null:
			return
		_job = ExportJob.for_song(AppState.song, options)
	else:
		var sounds: Dictionary = AppState.kit.sounds.duplicate()
		if sounds.is_empty() and AppState.sfx:
			sounds[ExportJob.sanitize(AppState.sfx.get_sound_name())] = AppState.sfx
		_job = ExportJob.for_sfx(sounds, prefix, options)
	%Export.disabled = true
	%Progress.visible = true
	%Progress.value = 0.0
	%Status.text = "Preparing..."
	set_process(true)


func _process(_delta: float) -> void:
	if _job == null:
		set_process(false)
		return
	_job.step()
	%Progress.value = _job.progress
	%Status.text = _job.status
	if _job.done:
		set_process(false)
		var bytes := _job.build_zip()
		var prefix: String = %Prefix.text if %Prefix.text.strip_edges() != "" else %Prefix.placeholder_text
		var name := ExportJob.sanitize(prefix) + ".zip"
		_job = null
		%Status.text = "Saving..."
		FileDelivery.deliver(bytes, name, self, func(message: String) -> void:
			%Status.text = message
			%Progress.visible = false
			%Export.disabled = false)
