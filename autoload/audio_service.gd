extends Node
## Preview playback for the app: one music player and one SFX player.

signal playback_started
signal playback_stopped

var music: ChipMusicPlayer
var sfx: ChipSfxPlayer
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
	music.finished.connect(func() -> void: playback_stopped.emit())


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
	if sound:
		sfx.play_sfx(sound)
