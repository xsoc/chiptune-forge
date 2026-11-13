extends Control
## Export flow: 1 target, 2 limits check, 3 formats. Works for the song in
## Music mode and for the kit (or the current sound) in Sound FX mode.

## Songs at least this long get a note about WAV size and render time.
const LONG_SONG_SECONDS := 270.0

var _job: ExportJob
# PSGlib data size per Master System arrangement, for the report.
var _psg_sizes := {}


func _ready() -> void:
	set_process(false)
	_build_targets()
	%Export.pressed.connect(_on_export)
	%Wav.toggled.connect(func(on: bool) -> void: %WavOptions.visible = on and AppState.mode == "music")
	%Godot.toggled.connect(func(on: bool) -> void: %Plugin.disabled = not on)
	AppState.mode_changed.connect(func(_m: String) -> void: refresh())
	AppState.song_changed.connect(func(_s: ChipSong) -> void: refresh())
	AppState.kit_changed.connect(refresh)
	AppState.target_changed.connect(func(_t: String) -> void: refresh())
	%SfxChannel.item_selected.connect(func(index: int) -> void:
		var channel: int = %SfxChannel.get_item_id(index)
		%SfxFree.disabled = channel < 0
		AppState.set_gameboy_option("sfx_channel", channel))
	%SfxFree.toggled.connect(func(on: bool) -> void: AppState.set_gameboy_option("sfx_free", on))
	visibility_changed.connect(func() -> void:
		if visible:
			refresh())
	refresh()


func refresh() -> void:
	var music := AppState.mode == "music"
	var gameboy := AppState.target == "gameboy"
	var nes := AppState.target == "nes"
	var sms := AppState.target == "sms"
	var console := gameboy or nes or sms
	%Export.theme_type_variation = &"PrimaryButton" if music else &"SfxPrimaryButton"
	%Midi.visible = music
	%WavOptions.visible = music and %Wav.button_pressed
	%Stems.visible = not console
	%Console.visible = console
	%Console.text = "Game Boy: C project for GBDK-2020 and hUGEDriver"
	if nes:
		%Console.text = "NES: FamiStudio project (for its sound engine, NSF or ROM)"
	elif sms:
		%Console.text = "Master System: PSGlib data for devkitSMS, and VGM"
	%Godot.visible = not console
	%Plugin.visible = not console
	%GbOptions.visible = gameboy and music
	for button in %Targets.get_children():
		if button is Button:
			button.set_pressed_no_signal(button.get_meta("target", "") == AppState.target)
	if music:
		var song: ChipSong = AppState.song
		%What.text = "Exporting the current song." if song else "Generate a song first."
		%Prefix.placeholder_text = ExportJob.sanitize(song.get_title()) if song else "song"
		%Godot.text = "Godot: .chipsong for the Chiptune Forge plugin"
		%Wav.text = "Audio: WAV, 44.1 kHz, loop points included"
		if gameboy:
			%Wav.text = "Audio: WAV of the Game Boy version, loop points included"
			%Midi.text = "MIDI: the four Game Boy parts"
		elif nes:
			%Wav.text = "Audio: WAV of the NES version, loop points included"
			%Midi.text = "MIDI: the four NES parts"
		elif sms:
			%Wav.text = "Audio: WAV of the SMS version, loop points included"
			%Midi.text = "MIDI: the four Master System parts"
		else:
			%Midi.text = "MIDI: one track per channel"
		%Export.disabled = song == null
	else:
		var count := AppState.kit.sounds.size()
		%What.text = "Exporting the kit (%d sounds)." % count if count > 0 else "The kit is empty, so this exports the current sound."
		%Prefix.placeholder_text = ExportJob.sanitize(AppState.kit.kit_name)
		%Godot.text = "Godot: .chipkit and .chipsfx for the plugin"
		%Wav.text = "Audio: one WAV per sound"
		if console:
			%Wav.text = "Audio: one WAV per sound, as the %s plays it" % ("NES" if nes else "Master System" if sms else "Game Boy")
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
		button.button_pressed = id == AppState.target
		button.set_meta("target", id)
		button.pressed.connect(func() -> void: AppState.set_target(id))
		%Targets.add_child(button)
	var more := Label.new()
	more.text = "With a console picked, previews play through that console's emulated sound chip."
	more.theme_type_variation = &"MutedLabel"
	more.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	%Targets.add_child(more)


func _update_report() -> void:
	var chip: ChipProfile = AppState.catalog.chips.get(AppState.target)
	var lines: Array[String] = []
	if chip:
		lines.append("[b]%s[/b]: %s" % [chip.display_name, chip.description])
	if AppState.target == "gameboy":
		lines.append_array(_gameboy_report())
	elif AppState.target == "nes":
		lines.append_array(_nes_report())
	elif AppState.target == "sms":
		lines.append_array(_sms_report())
	elif AppState.mode == "music" and AppState.song:
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


func _gameboy_report() -> Array[String]:
	var lines: Array[String] = [""]
	if AppState.mode == "music":
		var gb := AppState.get_gameboy_song()
		if gb == null:
			return lines
		var size := gb.data_size()
		if size <= GbSong.BANK_BYTES:
			lines.append("[color=#52d1c0]Fits[/color] after arranging for 4 channels.")
		else:
			lines.append("[color=#f0a050]Too big for one ROM bank.[/color] Shorten the song or pick fewer sections.")
		for line in gb.report:
			lines.append("•  " + line)
		return lines
	var sounds := _sounds()
	lines.append("[color=#52d1c0]Fits.[/color] Each sound plays on one channel, one register update per frame.")
	var ids := sounds.keys()
	ids.sort()
	for id in ids:
		var gb_sfx := GbSfx.from_sfx(sounds[id], str(id))
		var text := "•  %s: %s, %.2f s" % [id, "Pulse 2" if gb_sfx.channel == GbSfx.PULSE else "Noise", gb_sfx.frame_count() / GbSfx.FRAME_HZ]
		if not gb_sfx.notes.is_empty():
			text += " (%s)" % ", ".join(gb_sfx.notes)
		lines.append(text)
	lines.append("Sounds play over the music by pausing that channel's part, so reserve the channel your sounds use when you export the song.")
	return lines


func _nes_report() -> Array[String]:
	var lines: Array[String] = [""]
	if AppState.mode == "music":
		var nes := AppState.get_nes_song()
		if nes == null:
			return lines
		if nes.pattern_chunks().size() <= NesSong.MAX_PATTERNS:
			lines.append("[color=#52d1c0]Fits[/color] after arranging for 4 channels.")
		else:
			lines.append("[color=#f0a050]Too long for one FamiStudio song.[/color] Shorten the song or pick fewer sections.")
		for line in nes.report:
			lines.append("•  " + line)
		return lines
	var sounds := _sounds()
	lines.append("[color=#52d1c0]Fits.[/color] Each sound is one FamiStudio instrument, its envelopes updated once per frame.")
	var ids := sounds.keys()
	ids.sort()
	for id in ids:
		var nes_sfx := NesSfx.from_sfx(sounds[id], str(id))
		var text := "•  %s: %s, %.2f s" % [id, "Pulse 2" if nes_sfx.channel == NesSong.PULSE2 else "Noise", nes_sfx.frame_count() / NesApu.FRAME_HZ]
		if not nes_sfx.notes.is_empty():
			text += " (%s)" % ", ".join(nes_sfx.notes)
		lines.append(text)
	lines.append("FamiStudio's engine plays sounds over the music and gives the channel back when they end.")
	return lines


func _sms_report() -> Array[String]:
	var lines: Array[String] = [""]
	if AppState.mode == "music":
		var sms := AppState.get_sms_song()
		if sms == null:
			return lines
		var key := sms.get_instance_id()
		if not _psg_sizes.has(key):
			_psg_sizes = {key: PsgWriter.song_bytes(sms).size()}
		var size: int = _psg_sizes[key]
		if size <= 16384:
			lines.append("[color=#52d1c0]Fits[/color] after arranging for 4 channels: %.1f KB of PSGlib data, in one ROM bank." % (size / 1024.0))
		else:
			lines.append("[color=#f0a050]%.1f KB of PSGlib data, more than one 16 KB ROM bank.[/color] Compress it with PSGlib's psgcomp (about half the size) or build PSGlib with PSGLIB_MULTIBANK." % (size / 1024.0))
		for line in sms.report:
			lines.append("•  " + line)
		return lines
	var sounds := _sounds()
	lines.append("[color=#52d1c0]Fits.[/color] Each sound is PSGlib data on one channel, one register update per frame.")
	var ids := sounds.keys()
	ids.sort()
	for id in ids:
		var sms_sfx := SmsSfx.from_sfx(sounds[id], str(id))
		var text := "•  %s: %s, %.2f s" % [id, "Square 3" if sms_sfx.channel == SmsSong.SQUARE3 else "Noise", sms_sfx.frame_count() / SmsSong.FRAME_HZ]
		if not sms_sfx.notes.is_empty():
			text += " (%s)" % ", ".join(sms_sfx.notes)
		lines.append(text)
	lines.append("PSGlib plays sounds over the music and gives the channel back when they end.")
	return lines


func _sounds() -> Dictionary:
	var sounds: Dictionary = AppState.kit.sounds.duplicate()
	if sounds.is_empty() and AppState.sfx:
		sounds[ExportJob.sanitize(AppState.sfx.get_sound_name())] = AppState.sfx
	return sounds


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
		match AppState.target:
			"gameboy":
				_job = ExportJob.for_gameboy_song(AppState.get_gameboy_song(), options)
			"nes":
				_job = ExportJob.for_nes_song(AppState.get_nes_song(), options)
			"sms":
				_job = ExportJob.for_sms_song(AppState.get_sms_song(), options)
			_:
				_job = ExportJob.for_song(AppState.song, options)
	else:
		var sounds := _sounds()
		match AppState.target:
			"gameboy":
				_job = ExportJob.for_gameboy_sfx(sounds, prefix, options)
			"nes":
				_job = ExportJob.for_nes_sfx(sounds, prefix, options)
			"sms":
				_job = ExportJob.for_sms_sfx(sounds, prefix, options)
			_:
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
