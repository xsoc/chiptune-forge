extends Node
## Preview playback for the app: one music player and one SFX player. When
## the export target is the Game Boy, both play through the emulated Game Boy
## sound chip instead, so the preview is what the console will play.

signal playback_started
signal playback_stopped

var music: ChipMusicPlayer
var sfx: ChipSfxPlayer
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
	if AppState.target == "gameboy":
		var rate := 32000 if OS.has_feature("web") else 44100
		var samples := GbSfx.from_sfx(sound).render(rate)
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
	return ChipSongSequencer.new(song, rate)


## Restarts the song where it was, on the new target's sound.
func _on_target_changed(_target: String) -> void:
	if music.is_playing() and music.song:
		var step := music.get_position() / music.song.get_step_seconds()
		music.play(fmod(step, maxf(music.song.get_length_steps(), 1)))
