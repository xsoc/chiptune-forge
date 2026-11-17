@icon("res://addons/chipforge/icons/chip_music_player.svg")
class_name ChipMusicPlayer
extends Node
## Plays a [ChipSong] live, with adaptive layers and quantised transitions.
##
## Add it to a scene, assign a song and call [method play]. For adaptive
## music, set [member intensity] (0 to 1) or call [method set_state] with one
## of the song's states, such as [code]"combat"[/code]. The song's transition
## rules decide when the change lands (now, or on the next beat, bar or
## phrase) and how (crossfade, cut, or a stinger over the music).
## [method play_stinger] plays a stinger on demand, and
## [method transition_to] jumps to a section on the next beat, bar or phrase.

signal beat(index: int)
signal bar(index: int)
signal section_changed(section_name: String)
signal cue_reached(cue_name: String)
## A state change has landed (after its quantise wait).
signal state_changed(state_name: String)
signal looped
signal finished

const LEVELS := {"off": 0.0, "low": 0.35, "mid": 0.65, "full": 1.0}

@export var song: ChipSong:
	set(value):
		song = value
		if is_inside_tree() and is_playing():
			play()
@export var autoplay := false
## Loop the song's loop region. Off plays it once, with its outro.
@export var loop := true
@export_range(-60.0, 12.0, 0.1, "suffix:dB") var volume_db := 0.0:
	set(value):
		volume_db = value
		if _player:
			_player.volume_db = value
@export var bus: StringName = &"Master"
## Adaptive mode: when on, [member intensity] and [method set_state] control
## the layers. When off, the song plays exactly as arranged.
@export var adaptive := false
## Game intensity from 0 to 1. Each song state covers a band of it.
@export_range(0.0, 1.0, 0.01) var intensity := 0.0:
	set(value):
		intensity = clampf(value, 0.0, 1.0)
		if adaptive and song:
			var state := state_for_intensity(intensity)
			if state == _state:
				_pending_state = []
			elif state != "" and (_pending_state.is_empty() or _pending_state[0] != state):
				set_state(state)
@export_group("Advanced")
@export var mix_rate := 44100
## Mix rate used in web builds, where CPU time is tighter.
@export var web_mix_rate := 32000
@export_range(0.05, 1.0, 0.01, "suffix:s") var buffer_length := 0.12
## Render the whole song once into a looping stream instead of synthesising
## it live. Uses more memory and disables adaptive layers.
@export var prerender := false
## Optional: builds the sequencer instead of a [ChipSongSequencer]. Called
## with the song and mix rate; must return a [ChipSongSequencer] (or a
## subclass, such as one that emulates a console's sound chip).
var sequencer_factory: Callable

var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _sequencer: ChipSongSequencer
var _state := ""
var _pending_section := -1
var _pending_quantize := "bar"
## A state change waiting for its beat, bar or phrase: [name, rule].
var _pending_state: Array = []
var _stinger: ChipSongSequencer
var _stinger_left := 0


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.name = "Output"
	_player.bus = bus
	_player.volume_db = volume_db
	add_child(_player, false, Node.INTERNAL_MODE_FRONT)
	if autoplay and song:
		play()


func _process(_delta: float) -> void:
	if _playback == null or (_sequencer == null and _stinger == null):
		return
	var frames := _playback.get_frames_available()
	if frames <= 0:
		return
	var buffer := PackedVector2Array()
	if _sequencer:
		buffer = _sequencer.render(frames)
	else:
		buffer.resize(mini(frames, _stinger_left))
	if _stinger:
		var extra := _stinger.render(mini(frames, _stinger_left))
		for i in extra.size():
			buffer[i] += extra[i]
		_stinger_left -= extra.size()
		if _stinger_left <= 0 or extra.is_empty():
			_stinger = null
	_playback.push_buffer(buffer)
	if _sequencer:
		_dispatch(_sequencer.events)
	elif _stinger == null:
		# A stinger played on its own has finished.
		_playback = null


## Starts playing from [param from_step] (16th-note steps by default).
func play(from_step := 0.0) -> void:
	if song == null:
		push_warning("ChipMusicPlayer: no song assigned.")
		return
	stop()
	if song.prerendered and not adaptive and not sequencer_factory.is_valid():
		var stream: AudioStreamOggVorbis = song.prerendered.duplicate()
		stream.loop = stream.loop and loop
		_player.stream = stream
		_player.play(from_step * song.get_step_seconds())
		return
	var rate := web_mix_rate if OS.has_feature("web") else mix_rate
	if sequencer_factory.is_valid():
		_sequencer = sequencer_factory.call(song, rate)
	else:
		_sequencer = ChipSongSequencer.new(song, rate)
	_sequencer.looping = loop and _sequencer.looping and bool(song.data.get("timing", {}).get("loop", true))
	_sequencer.seek_step(from_step)
	if prerender:
		var frames := _sequencer.render_all(1)
		var loop_begin := _sequencer.get_loop_start_frame() if _sequencer.looping else -1
		var loop_end := _sequencer.get_loop_end_frame() if _sequencer.looping else -1
		_player.stream = ChipAudio.stereo_to_stream(frames, rate, loop_begin, loop_end)
		_sequencer = null
		_player.play()
		return
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = rate
	generator.buffer_length = maxf(buffer_length, 0.25) if OS.has_feature("web") else buffer_length
	_player.stream = generator
	if adaptive:
		var state := _state if _state != "" else state_for_intensity(intensity)
		if state != "":
			_apply_state(state, 0)
	_player.play()
	_playback = _player.get_stream_playback()


func stop() -> void:
	if _player:
		_player.stop()
	_playback = null
	_sequencer = null
	_stinger = null
	_pending_section = -1
	_pending_state = []


func is_playing() -> bool:
	return _player != null and _player.playing


## Position in seconds from the start of the song.
func get_position() -> float:
	if _sequencer == null:
		return _player.get_playback_position() if _player and _player.playing else 0.0
	return float(_sequencer.position) / float(_sequencer.mix_rate)


func get_current_state() -> String:
	return _state


## Returns the name of the state whose intensity band holds [param value].
func state_for_intensity(value: float) -> String:
	var best := ""
	var best_min := -1.0
	for state in song.data.get("states", []):
		var lowest := float(state.get("min_intensity", 0.0))
		if lowest <= value and lowest > best_min:
			best = str(state.get("name", ""))
			best_min = lowest
	return best


## Switches to a named state, such as [code]"combat"[/code]. With
## [param fade_beats] left out, the song's transition rule for this route
## decides when and how (see [method transition_for]); with it, layers fade
## over that many beats straight away.
func set_state(state_name: String, fade_beats := -1.0) -> void:
	adaptive = true
	if fade_beats >= 0.0 or _sequencer == null:
		_pending_state = []
		_land_state(state_name, _beats_to_frames(maxf(fade_beats, 0.0)) if _sequencer else 0)
		return
	var rule := transition_for(_state, state_name)
	if str(rule.get("when", "beat")) == "now":
		_run_transition(state_name, rule)
	else:
		_pending_state = [state_name, rule]


## The transition rule for going from [param from_state] to
## [param to_state]: {when, how, stinger?}. An exact route beats "*" to a
## state, which beats a state to "*", which beats "*" to "*". With no rule
## the change crossfades on the next beat.
func transition_for(from_state: String, to_state: String) -> Dictionary:
	var best := {}
	var best_score := -1
	for rule in song.data.get("transitions", []) if song else []:
		var rule_from := str(rule.get("from", "*")).to_lower()
		var rule_to := str(rule.get("to", "*")).to_lower()
		var from_ok := rule_from == "*" or rule_from == from_state.to_lower()
		var to_ok := rule_to == "*" or rule_to == to_state.to_lower()
		if not from_ok or not to_ok:
			continue
		var score := (2 if rule_to != "*" else 0) + (1 if rule_from != "*" else 0)
		if score > best_score:
			best = rule
			best_score = score
	return best if best_score >= 0 else {"when": "beat", "how": "crossfade"}


## Plays one of the song's stingers (such as "rise") over the music, from
## now. Returns false when the song has no stinger by that name.
func play_stinger(stinger_name: String) -> bool:
	var data := stinger_song(stinger_name)
	if data == null:
		push_warning("ChipMusicPlayer: no stinger named %s." % stinger_name)
		return false
	var rate := _sequencer.mix_rate if _sequencer else (web_mix_rate if OS.has_feature("web") else mix_rate)
	_stinger = ChipSongSequencer.new(data, rate)
	_stinger.looping = false
	_stinger_left = _stinger.get_length_frames() + int(rate * 0.6)
	if _sequencer == null and _player:
		# Nothing playing: the stinger plays on its own.
		var generator := AudioStreamGenerator.new()
		generator.mix_rate = rate
		generator.buffer_length = maxf(buffer_length, 0.25) if OS.has_feature("web") else buffer_length
		_player.stream = generator
		_player.play()
		_playback = _player.get_stream_playback()
	return true


## The stinger as a playable one-section song, or null.
func stinger_song(stinger_name: String) -> ChipSong:
	if song == null:
		return null
	for stinger in song.data.get("stingers", []):
		if str(stinger.get("name", "")).to_lower() != stinger_name.to_lower():
			continue
		var data := song.data.duplicate()
		var channel_count: int = song.data.get("channels", []).size()
		var per_channel: Array = []
		for c in channel_count:
			per_channel.append([])
		for note in stinger.get("notes", []):
			var c := int(note[0])
			if c >= 0 and c < channel_count:
				per_channel[c].append(note.slice(1))
		var patterns: Array = []
		var ids: Array = []
		for c in channel_count:
			if per_channel[c].is_empty():
				ids.append(-1)
			else:
				ids.append(patterns.size())
				patterns.append({"notes": per_channel[c]})
		var length := int(stinger.get("length", 16))
		data["patterns"] = patterns
		data["sections"] = [{"name": str(stinger["name"]), "length": length, "patterns": ids}]
		data["order"] = [0]
		var timing: Dictionary = song.data.get("timing", {}).duplicate()
		timing["loop"] = false
		timing["loop_start"] = 0
		timing["loop_end"] = length
		data["timing"] = timing
		data["cues"] = []
		var result := ChipSong.new()
		result.data = data
		return result
	return null


func get_stinger_names() -> PackedStringArray:
	var names := PackedStringArray()
	for stinger in song.data.get("stingers", []) if song else []:
		names.append(str(stinger.get("name", "")))
	return names


func _run_transition(state_name: String, rule: Dictionary) -> void:
	_pending_state = []
	match str(rule.get("how", "crossfade")):
		"cut":
			_land_state(state_name, 0)
		"stinger":
			play_stinger(str(rule.get("stinger", "rise")))
			_land_state(state_name, 0)
		_:
			_land_state(state_name, _beats_to_frames(float(rule.get("fade_beats", 2.0))))


func _land_state(state_name: String, fade_frames: int) -> void:
	_state = state_name
	if _sequencer:
		_apply_state(state_name, fade_frames)
	state_changed.emit(state_name)


## Leaves adaptive mode and fades every layer back to full.
func clear_state(fade_beats := 1.0) -> void:
	adaptive = false
	_state = ""
	if _sequencer:
		for c in _sequencer.get_channel_count():
			_sequencer.set_channel_gain(c, 1.0, _beats_to_frames(fade_beats))


## Sets one layer's level (0 to 1, or "off", "low", "mid", "full").
func set_layer(layer_name: String, level: Variant, fade_beats := 1.0) -> void:
	adaptive = true
	if _sequencer == null:
		return
	var value: float = LEVELS.get(str(level).to_lower(), 0.0) if level is String else float(level)
	for layer in song.data.get("layers", []):
		if str(layer.get("name", "")).to_lower() == layer_name.to_lower():
			for channel in layer.get("channels", []):
				_sequencer.set_channel_gain(int(channel), value, _beats_to_frames(fade_beats))


## Mutes a channel, for previews and debugging.
func set_channel_muted(channel: int, muted: bool) -> void:
	if _sequencer:
		_sequencer.set_channel_muted(channel, muted)


func get_channel_level(channel: int) -> float:
	return _sequencer.get_channel_level(channel) if _sequencer else 0.0


## Jumps to the first section named [param section_name] when the next
## [param quantize] boundary arrives: "now", "beat", "bar" or "phrase".
func transition_to(section_name: String, quantize := "bar") -> void:
	var step := 0
	var order: Array = song.data.get("order", [])
	for index in order:
		var section: Dictionary = song.data["sections"][int(index)]
		if str(section.get("name", "")) == section_name:
			_pending_section = step
			_pending_quantize = quantize
			if quantize == "now":
				_do_transition()
			return
		step += int(section.get("length", 0))
	push_warning("ChipMusicPlayer: no section named %s." % section_name)


func _do_transition() -> void:
	if _sequencer and _pending_section >= 0:
		_sequencer.seek_step(_pending_section, false)
	_pending_section = -1


func _apply_state(state_name: String, fade_frames: int) -> void:
	for state in song.data.get("states", []):
		if str(state.get("name", "")).to_lower() != state_name.to_lower():
			continue
		var levels: Dictionary = state.get("levels", {})
		for layer in song.data.get("layers", []):
			var level: Variant = levels.get(layer.get("name", ""), "full")
			var value: float = LEVELS.get(str(level).to_lower(), 1.0) if level is String else float(level)
			for channel in layer.get("channels", []):
				_sequencer.set_channel_gain(int(channel), value, fade_frames)
		return


func _beats_to_frames(beats: float) -> int:
	if _sequencer == null:
		return 0
	return int(beats * song.get_steps_per_beat() * _sequencer.get_step_frames())


func _dispatch(events: Array) -> void:
	for event in events:
		match event[0]:
			ChipSongSequencer.EventType.BEAT:
				beat.emit(event[1])
				if _pending_section >= 0 and _pending_quantize == "beat":
					_do_transition()
				if not _pending_state.is_empty() and str(_pending_state[1].get("when", "beat")) == "beat":
					_run_transition(_pending_state[0], _pending_state[1])
			ChipSongSequencer.EventType.BAR:
				bar.emit(event[1])
				if _pending_section >= 0 and (_pending_quantize == "bar" or (_pending_quantize == "phrase" and int(event[1]) % 4 == 0)):
					_do_transition()
				if not _pending_state.is_empty():
					var when := str(_pending_state[1].get("when", "beat"))
					if when == "bar" or (when == "phrase" and int(event[1]) % 4 == 0):
						_run_transition(_pending_state[0], _pending_state[1])
			ChipSongSequencer.EventType.SECTION:
				section_changed.emit(event[1])
			ChipSongSequencer.EventType.CUE:
				cue_reached.emit(event[1])
			ChipSongSequencer.EventType.LOOPED:
				looped.emit()
			ChipSongSequencer.EventType.FINISHED:
				finished.emit()
