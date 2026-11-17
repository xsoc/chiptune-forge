class_name SynthEngines
extends RefCounted
## Sets each instrument's synth engine (see [ChipVoice] and [ChipEngines]).
##
## An engine only adds keys to an instrument: its chip settings stay, so the
## console arrangers see the same instruments whatever engine is picked, and
## changing the engine never changes the notes. No randomness is used, so
## seeds give the same song as before.

## Engines in the order the app lists them.
const ENGINES: PackedStringArray = ["chip", "analog", "fm", "wavetable", "sampled"]
## What a song or layer can be set to: "auto" is the style's own engine.
const CHOICES: PackedStringArray = ["chip", "auto", "analog", "fm", "wavetable", "sampled"]
const NAMES := {
	"chip": "Classic chip",
	"auto": "Style's pick",
	"analog": "Analog",
	"fm": "FM",
	"wavetable": "Wavetable",
	"sampled": "Sampled",
}
const DESCRIPTIONS := {
	"chip": "Pulse, triangle, saw and noise, as the chips make them.",
	"auto": "The engine that suits the style.",
	"analog": "Two detuned oscillators through a resonant filter.",
	"fm": "Two-operator FM, bright at the start of each note.",
	"wavetable": "Sweeps through a bank of waves as each note plays.",
	"sampled": "Plucked strings, piano, ensembles and real drums, made in the app.",
}
## Each style group's engine, for styles that don't name their own.
const GROUP_DEFAULTS := {
	"Electronic": "analog",
	"Dance and club": "analog",
	"Jazz and lounge": "fm",
	"Orchestral and film": "sampled",
	"Chill and ambient": "wavetable",
	"Pop, soul and hip hop": "fm",
	"World and folk": "sampled",
	"Rock and metal": "analog",
	"Game genres": "chip",
}
## Instrument order from [SoundDesigner]: the five tonal layers, then drums.
const LAYER_OF := ["Lead", "Harmony", "Arp", "Pad", "Bass"]
const DRUM_SAMPLES := ["kick", "snare", "hat", "open_hat", "crash", "tom", "hat"]
## Keys an engine adds. Removing them gives the chip instrument back.
const ENGINE_KEYS: PackedStringArray = [
	"engine", "detune", "cutoff", "resonance", "env_amount", "filter_decay", "key_track",
	"ratio", "index", "index_end", "index_decay", "feedback",
	"bank", "wt_from", "wt_to", "wt_time", "sample",
]
## The chip settings an engine replaced, kept here to put back.
const SAVED_KEY := "chip"


## The style's engine: its own, or its group's.
static func style_engine(style: Style) -> String:
	if style == null:
		return "chip"
	if style.engine in ENGINES:
		return style.engine
	return str(GROUP_DEFAULTS.get(style.group, "chip"))


## The engine a song uses, from a setting that may be "auto".
static func resolve(choice: String, style: Style) -> String:
	if choice == "auto":
		return style_engine(style)
	return choice if choice in ENGINES else "chip"


## The engine of each instrument: [param song_engine] (already resolved),
## except layers named in [param layer_engines] ({layer: choice}).
static func layer_engine(layer: String, song_engine: String, layer_engines: Dictionary, style: Style) -> String:
	var choice := str(layer_engines.get(layer, ""))
	if choice == "":
		return song_engine
	return resolve(choice, style)


## [param instruments] with their engines set. Drums change only with the
## sampled engine.
static func apply(instruments: Array, song_engine: String, layer_engines: Dictionary = {}, style: Style = null) -> Array:
	var out: Array = []
	for i in instruments.size():
		var inst: Dictionary = chip_instrument(instruments[i])
		var layer: String = LAYER_OF[i] if i < LAYER_OF.size() else "Drums"
		var engine := layer_engine(layer, song_engine, layer_engines, style)
		if engine != "chip":
			if layer == "Drums":
				if engine == "sampled":
					_set_drum(inst, DRUM_SAMPLES[mini(i - LAYER_OF.size(), DRUM_SAMPLES.size() - 1)])
			else:
				_set_tonal(inst, layer, engine)
		out.append(inst)
	return out


## An instrument with no engine: its own chip settings.
static func chip_instrument(source: Dictionary) -> Dictionary:
	var inst := source.duplicate(true)
	if inst.has(SAVED_KEY):
		var saved: Dictionary = inst[SAVED_KEY]
		for key in saved:
			if saved[key] == null:
				inst.erase(key)
			else:
				inst[key] = saved[key]
		inst.erase(SAVED_KEY)
	for key in ENGINE_KEYS:
		inst.erase(key)
	return inst


## [param song] as the classic chip would play it, for the console
## arrangers. The same song when no instrument has an engine.
static func chip_song(song: ChipSong) -> ChipSong:
	if song == null:
		return null
	var instruments: Array = song.data.get("instruments", [])
	var any := false
	for inst in instruments:
		if inst is Dictionary and inst.has("engine"):
			any = true
			break
	var volumes := _channel_volumes(song)
	if not any and volumes.is_empty():
		return song
	var copy := ChipSong.new()
	copy.data = song.data.duplicate()
	if any:
		var plain: Array = []
		for inst in instruments:
			plain.append(chip_instrument(inst))
		copy.data["instruments"] = plain
	if not volumes.is_empty():
		_fold_volumes(copy, volumes)
	return copy


## {channel index: volume} for channels whose volume is not 1.
static func _channel_volumes(song: ChipSong) -> Dictionary:
	var result := {}
	var channels: Array = song.data.get("channels", [])
	for c in channels.size():
		var volume := float(channels[c].get("volume", 1.0))
		if not is_equal_approx(volume, 1.0):
			result[c] = volume
	return result


## Console arrangers read velocities, not channel volumes, so a layer
## volume set in the Advanced controls is folded into its notes'
## velocities (a channel at 0 goes silent).
static func _fold_volumes(copy: ChipSong, volumes: Dictionary) -> void:
	var channels: Array = copy.data["channels"].duplicate(true)
	var patterns: Array = copy.data["patterns"].duplicate(true)
	var sections: Array = copy.data["sections"].duplicate(true)
	var scaled := {} # "pattern:channel" -> new pattern index
	for section in sections:
		var ids: Array = section["patterns"]
		for c in ids.size():
			if not volumes.has(c) or int(ids[c]) < 0:
				continue
			var volume := float(volumes[c])
			if volume <= 0.0:
				ids[c] = -1
				continue
			var key := "%d:%d" % [int(ids[c]), c]
			if not scaled.has(key):
				var notes: Array = patterns[int(ids[c])]["notes"].duplicate(true)
				for note in notes:
					note[3] = clampi(roundi(float(note[3]) * volume), 1, 127)
				scaled[key] = patterns.size()
				patterns.append({"notes": notes})
			ids[c] = scaled[key]
	for c in volumes:
		channels[c]["volume"] = 1.0
	copy.data["channels"] = channels
	copy.data["patterns"] = patterns
	copy.data["sections"] = sections


## The engine each layer of [param song] plays with, as {layer: engine}.
static func song_engines(song: ChipSong) -> Dictionary:
	var result := {}
	var instruments: Array = song.data.get("instruments", []) if song else []
	for i in mini(instruments.size(), LAYER_OF.size()):
		result[LAYER_OF[i]] = str(instruments[i].get("engine", "chip"))
	var drums := "chip"
	for i in range(LAYER_OF.size(), instruments.size()):
		if instruments[i].has("engine"):
			drums = str(instruments[i]["engine"])
	result["Drums"] = drums
	return result


static func _replace(inst: Dictionary, changes: Dictionary) -> void:
	var saved: Dictionary = inst.get(SAVED_KEY, {})
	for key in changes:
		if not saved.has(key):
			saved[key] = inst.get(key)
		inst[key] = changes[key]
	inst[SAVED_KEY] = saved


static func _set_tonal(inst: Dictionary, layer: String, engine: String) -> void:
	var wave := str(inst.get("wave", "pulse"))
	var volume := float(inst.get("volume", 0.5))
	inst["engine"] = engine
	match engine:
		"analog":
			var patch: Dictionary = {
				"Lead": {"detune": 7.0, "cutoff": 900.0, "resonance": 0.35, "env_amount": 2.5, "filter_decay": 0.3, "key_track": 0.6},
				"Harmony": {"detune": 10.0, "cutoff": 700.0, "resonance": 0.2, "env_amount": 1.5, "filter_decay": 0.4, "key_track": 0.5},
				"Arp": {"detune": 4.0, "cutoff": 1100.0, "resonance": 0.5, "env_amount": 3.0, "filter_decay": 0.12, "key_track": 0.5},
				"Pad": {"detune": 14.0, "cutoff": 450.0, "resonance": 0.15, "env_amount": 1.0, "filter_decay": 1.2, "key_track": 0.3},
				"Bass": {"detune": 3.0, "cutoff": 220.0, "resonance": 0.45, "env_amount": 3.0, "filter_decay": 0.15, "key_track": 0.3},
			}[layer]
			inst.merge(patch, true)
			# Pulse leads and arps keep their duty; everything else is a saw.
			var keep_pulse := wave == "pulse" and layer in ["Lead", "Arp"]
			var changes := {"wave": "pulse" if keep_pulse else "saw", "volume": volume * 1.25}
			if layer == "Pad":
				changes["volume"] = volume * 1.5
			elif layer == "Bass":
				changes["volume"] = 0.75
			_replace(inst, changes)
		"fm":
			var patch: Dictionary = {
				"Lead": {"ratio": 1.0, "index": 3.0, "index_end": 1.0, "index_decay": 0.4, "feedback": 0.2},
				"Harmony": {"ratio": 2.0, "index": 1.5, "index_end": 0.5, "index_decay": 0.5, "feedback": 0.0},
				"Arp": {"ratio": 4.0, "index": 2.5, "index_end": 0.3, "index_decay": 0.15, "feedback": 0.0},
				"Pad": {"ratio": 1.0, "index": 1.2, "index_end": 0.8, "index_decay": 1.5, "feedback": 0.3},
				"Bass": {"ratio": 1.0, "index": 2.5, "index_end": 0.8, "index_decay": 0.12, "feedback": 0.2},
			}[layer]
			inst.merge(patch, true)
			_replace(inst, {"volume": volume * (1.0 if layer != "Bass" else 1.1)})
		"wavetable":
			var patch: Dictionary = {
				"Lead": {"bank": "bright", "wt_from": 0.3, "wt_to": 0.9, "wt_time": 0.4},
				"Harmony": {"bank": "vocal", "wt_from": 0.0, "wt_to": 0.7, "wt_time": 0.6},
				"Arp": {"bank": "metal", "wt_from": 1.0, "wt_to": 0.2, "wt_time": 0.2},
				"Pad": {"bank": "vocal", "wt_from": 0.0, "wt_to": 1.0, "wt_time": 2.0},
				"Bass": {"bank": "soft", "wt_from": 0.6, "wt_to": 0.1, "wt_time": 0.3},
			}[layer]
			inst.merge(patch, true)
			_replace(inst, {"volume": volume * (1.2 if layer == "Pad" else 1.0)})
		"sampled":
			var sample: String = {
				"Lead": "brass" if wave in ["pulse", "saw", "wave"] else "epiano",
				"Harmony": "strings",
				"Arp": "pluck",
				"Pad": "strings",
				"Bass": "pluck",
			}[layer]
			inst["sample"] = sample
			var changes := {"volume": volume * (1.7 if layer == "Pad" else 1.3)}
			if sample == "pluck" or sample == "epiano":
				# Let the sample's own decay shape the note.
				changes["sustain"] = 1.0
				changes["decay"] = 0.5
				changes["release"] = maxf(float(inst.get("release", 0.05)), 0.12)
			if layer == "Bass":
				changes["volume"] = 0.8
			_replace(inst, changes)


static func _set_drum(inst: Dictionary, sample: String) -> void:
	inst["engine"] = "sampled"
	inst["sample"] = sample
	var length := ChipEngines.sample(sample).size() / ChipEngines.SAMPLE_RATE
	var volume := float(inst.get("volume", 0.5))
	_replace(inst, {
		"attack": 0.001,
		"decay": length,
		"sustain": 1.0,
		"release": length,
		"pitch_drop": 0.0,
		"volume": minf(volume * (1.4 if sample in ["hat", "open_hat", "crash"] else 1.2), 1.0),
	})
