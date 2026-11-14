extends Node
## Preview playback for the app: one music player and one SFX player. When
## the export target is a console (Game Boy or NES), both play through that
## console's emulated sound chip instead, so the preview is what the console
## will play.

signal playback_started
signal playback_stopped

var music: ChipMusicPlayer
var sfx: ChipSfxPlayer
## Plays console sound effects, rendered through the emulated chip.
var gb_sfx: AudioStreamPlayer
## Web browsers block audio until the user taps. The UI shows a prompt and
## sets this once the user has.
var audio_unlocked := not OS.has_feature("web")


func _ready() -> void:
	music = ChipMusicPlayer.new()
	music.name = "Music"
	add_child(music)
	sfx = ChipSfxPlayer.new()
	sfx.name = "Sfx"
	sfx.polyphony = 6
	add_child(sfx)
	gb_sfx = AudioStreamPlayer.new()
	gb_sfx.name = "GameBoySfx"
	add_child(gb_sfx)
	music.finished.connect(func() -> void: playback_stopped.emit())
	music.sequencer_factory = _make_sequencer
	AppState.target_changed.connect(_on_target_changed)


func play_song(song: ChipSong, from_step := 0.0) -> void:
	music.song = song
	music.adaptive = false
	music.play(from_step)
	playback_started.emit()


func stop_song() -> void:
	music.stop()
	playback_stopped.emit()


func is_playing() -> bool:
	return music.is_playing()


func play_sfx(sound: ChipSfx) -> void:
	if sound == null:
		return
	if AppState.is_console_target():
		var rate := 32000 if OS.has_feature("web") else 44100
		var samples: PackedFloat32Array
		match AppState.target:
			"nes":
				samples = NesSfx.from_sfx(sound).render(rate)
			"sms":
				samples = SmsSfx.from_sfx(sound).render(rate)
			"genesis":
				samples = MdSfx.from_sfx(sound).render(rate)
			_:
				samples = GbSfx.from_sfx(sound).render(rate)
		gb_sfx.stream = ChipAudio.mono_to_stream(samples, rate)
		gb_sfx.play()
	else:
		sfx.play_sfx(sound)


func is_gameboy_preview() -> bool:
	return AppState.target == "gameboy"


func _make_sequencer(song: ChipSong, rate: int) -> ChipSongSequencer:
	if AppState.target == "gameboy" and song == AppState.song:
		var gb := AppState.get_gameboy_song()
		if gb:
			return GbSequencer.new(gb, rate, song.data["channels"].size())
	if AppState.target == "nes" and song == AppState.song:
		var nes := AppState.get_nes_song()
		if nes:
			return NesSequencer.new(nes, rate, song.data["channels"].size())
	if AppState.target == "sms" and song == AppState.song:
		var sms := AppState.get_sms_song()
		if sms:
			return SmsSequencer.new(sms, rate, song.data["channels"].size())
	if AppState.target == "genesis" and song == AppState.song:
		var md := AppState.get_md_song()
		if md:
			return MdSequencer.new(md, rate, song.data["channels"].size())
	return ChipSongSequencer.new(song, rate)


## Restarts the song where it was, on the new target's sound.
func _on_target_changed(_target: String) -> void:
	if music.is_playing() and music.song:
		var step := music.get_position() / music.song.get_step_seconds()
		music.play(fmod(step, maxf(music.song.get_length_steps(), 1)))
