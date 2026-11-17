extends Control
## Export flow: 1 target, 2 limits check, 3 formats. Works for the song in
## Music mode and for the kit (or the current sound) in Sound FX mode.

var _job: ExportJob
var _card: OptionButton


func _ready() -> void:
	set_process(false)
	_build_targets()
	%Export.pressed.connect(_on_export)
	%Wav.toggled.connect(func(on: bool) -> void:
		%WavOptions.visible = on and AppState.mode == "music"
		%RateRow.visible = on)
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
	var genesis := AppState.target == "genesis"
	var snes := AppState.target == "snes"
	var pce := AppState.target == "pce"
	var msx := AppState.target == "msx"
	var c64 := AppState.target == "c64"
	var gba := AppState.target == "gba"
	var pc := AppState.target == "pc"
	var card := PcCards.name_of(AppState.pc_card)
	var console := gameboy or nes or sms or genesis or snes or pce or msx or c64 or gba or pc
	%Export.theme_type_variation = &"PrimaryButton" if music else &"SfxPrimaryButton"
	%Midi.visible = music
	%WavOptions.visible = music and %Wav.button_pressed
	%RateRow.visible = %Wav.button_pressed
	%Stems.visible = not console
	%Console.visible = console
	%Console.text = "Game Boy: C project for GBDK-2020 and hUGEDriver"
	if nes:
		%Console.text = "NES: ca65 assembly for FamiStudio's sound engine, with a ROM project"
	elif sms:
		%Console.text = "Master System: PSGlib data for devkitSMS, and VGM"
	elif genesis:
		%Console.text = "Mega Drive: VGM for SGDK's XGM driver, with an example program" if music else "Mega Drive: 8-bit WAVs for SGDK's XGM driver"
	elif snes:
		%Console.text = "SNES: Impulse Tracker module for PVSnesLib, with a ROM project" if music else "SNES: BRR samples for PVSnesLib's sound driver"
	elif pce:
		%Console.text = "PC Engine: data and a small C player for HuCC, with a ROM project" if music else "PC Engine: sound data for the same C player"
	elif msx:
		%Console.text = "MSX / Spectrum: data and a small Z80 player, with cartridge and tape projects, and VGM" if music else "MSX / Spectrum: sound data for the same Z80 player"
	elif gba:
		%Console.text = "Game Boy Advance: Impulse Tracker module for Maxmod, with a ROM project" if music else "Game Boy Advance: 8-bit WAVs for Maxmod"
	elif c64:
		%Console.text = "Commodore 64: a .sid file and a small 6502 player, with an example program" if music else "Commodore 64: sound data for the same 6502 player"
	elif pc:
		match AppState.pc_card:
			"speaker":
				%Console.text = "PC speaker: C data and a small DOS player, with an example program" if music else "PC speaker: C data for the same DOS player"
			"tandy":
				%Console.text = "Tandy 1000: VGM files for the SN76496"
			"mt32":
				%Console.text = "MT-32: a MIDI file with the SysEx that sets it up" if music else "MT-32: sounds as Creative Voice files for a Sound Blaster beside it"
			"gus":
				%Console.text = "Gravis Ultrasound: an Impulse Tracker module with 16-bit samples" if music else "Gravis Ultrasound: 16-bit WAVs"
			"gm":
				%Console.text = "Sound Canvas: a General MIDI file with a GS reset" if music else "Sound Canvas: sounds as Creative Voice files for a Sound Blaster beside it"
			_:
				var names := Array(PcCards.music_formats(AppState.pc_card)).map(func(f: String) -> String: return f.to_upper())
				var formats := "%s and %s" % [", ".join(names.slice(0, -1)), names[-1]]
				var sfx_text := "FM sounds as DRO and IMF files" if AppState.pc_card == "adlib" else ("16-bit WAVs" if AppState.pc_card == "sb16" else "Creative Voice files (.voc)")
				%Console.text = ("%s: %s files for DOS players and trackers" % [card, formats]) if music else ("%s: %s" % [card, sfx_text])
	%Godot.visible = not console
	_card.visible = pc
	_card.select(maxi(PcCards.CARDS.find(AppState.pc_card), 0))
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
		elif genesis:
			%Wav.text = "Audio: Mega Drive WAV, loop points included"
			%Midi.text = "MIDI: the Mega Drive's ten parts"
		elif snes:
			%Wav.text = "Audio: SNES WAV, loop points included"
			%Midi.text = "MIDI: the SNES's seven parts"
		elif pce:
			%Wav.text = "Audio: PC Engine WAV, loop points included"
			%Midi.text = "MIDI: the PC Engine's six parts"
		elif msx:
			%Wav.text = "Audio: AY-3-8910 WAV, loop points included"
			%Midi.text = "MIDI: the four AY parts"
		elif gba:
			%Wav.text = "Audio: GBA WAV, loop points included"
			%Midi.text = "MIDI: the GBA's seven parts"
		elif c64:
			%Wav.text = "Audio: SID WAV, loop points included"
			%Midi.text = "MIDI: the four SID parts"
		elif pc:
			%Wav.text = "Audio: %s WAV, loop points included" % card
			%Midi.text = "MIDI: the arranged parts"
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
			%Wav.text = "Audio: one WAV per sound, as the %s plays it" % ("NES" if nes else "Master System" if sms else "Mega Drive" if genesis else "SNES" if snes else "PC Engine" if pce else "AY-3-8910" if msx else "SID" if c64 else card if pc else "Game Boy Advance" if gba else "Game Boy")
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
	_card = OptionButton.new()
	_card.name = "Card"
	_card.custom_minimum_size.y = 44
	for card in PcCards.CARDS:
		_card.add_item("Sound card: %s (%d)" % [PcCards.name_of(card), PcCards.INFO[card]["year"]])
	_card.item_selected.connect(func(index: int) -> void: AppState.set_pc_card(PcCards.CARDS[index]))
	%Targets.add_child(_card)
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
	var music := AppState.mode == "music"
	if music and AppState.song == null:
		%Report.text = "\n".join(lines)
		return
	var arranged: Variant = AppState.get_arranged_song() if music else null
	lines.append_array(TargetReport.lines(AppState.target, music, AppState.song, arranged, _sounds(), AppState.pc_card))
	%Report.text = "\n".join(lines)


func _sounds() -> Dictionary:
	var sounds: Dictionary = AppState.kit.sounds.duplicate()
	if sounds.is_empty() and AppState.sfx:
		sounds[ExportJob.sanitize(AppState.sfx.get_sound_name())] = AppState.sfx
	return sounds


func _on_export() -> void:
	var prefix: String = %Prefix.text if %Prefix.text.strip_edges() != "" else %Prefix.placeholder_text
	var options := {
		"prefix": prefix,
		"godot": %Godot.button_pressed,
		"plugin": %Plugin.button_pressed,
		"wav": %Wav.button_pressed,
		"loops": %Loops.get_selected_id(),
		"rate": %Rate.get_selected_id(),
		"stems": %Stems.button_pressed,
		"midi": %Midi.button_pressed,
		"console": %Console.button_pressed,
		"card": AppState.pc_card,
	}
	if AppState.mode == "music":
		if AppState.song == null:
			return
		options["project"] = ProjectFile.for_song(AppState.song, AppState.settings, AppState.target, AppState.gameboy_options.merged({"card": AppState.pc_card}) if AppState.target == "pc" else AppState.gameboy_options)
		_job = ExportJob.for_target_song(AppState.target, AppState.song, options, AppState.get_arranged_song())
	else:
		options["project"] = ProjectFile.for_kit(prefix, _sounds(), AppState.target, AppState.pc_card)
		_job = ExportJob.for_target_sfx(AppState.target, _sounds(), prefix, options)
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
