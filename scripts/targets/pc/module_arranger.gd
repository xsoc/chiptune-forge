class_name ModuleArranger
extends RefCounted
## Sets a song up for a MIDI sound module: the Roland MT-32 (LA synthesis,
## 1987) or a General MIDI module such as the Roland Sound Canvas (1991).
##
## Each part gets the program closest to its sound (the MT-32's own 128
## presets, or General MIDI's), its volume and pan, and its own MIDI
## channel: on the MT-32 parts 1 to 8 on channels 2 to 9 and the rhythm part
## on 10, as it starts up. SysEx at the start sets the module up (the MT-32's
## reverb, partial reserve and display; GM System On and the Sound Canvas's
## GS reset). Chords are trimmed when they would need more than the module
## can play at once: 32 partials on the MT-32 (about two a note), 24 voices
## on the Sound Canvas.

const PART_LAYERS: PackedStringArray = ["Lead", "Harmony", "Arp", "Pad", "Bass"]
const LIMITS := {"mt32": 32, "gm": 24}
## Partials (MT-32) or voices (Sound Canvas) per note.
const COST := {"mt32": 2, "gm": 1}
const MAX_PARTS := {"mt32": 8, "gm": 15}

## Programs by sound and part: General MIDI's and the MT-32's presets.
const GM := {
	"Lead": {"square": 80, "saw": 81, "soft": 73, "keys": 4, "strings": 48, "brass": 61, "bell": 11, "pluck": 25},
	"Arp": {"square": 80, "saw": 81, "soft": 11, "keys": 4, "strings": 45, "brass": 61, "bell": 11, "pluck": 25},
	"Pad": {"square": 90, "saw": 90, "soft": 89, "keys": 89, "strings": 48, "brass": 61, "bell": 88, "pluck": 48},
	"Bass": {"square": 38, "saw": 38, "soft": 33, "keys": 33, "strings": 32, "brass": 38, "bell": 33, "pluck": 34},
}
const MT32 := {
	"Lead": {"square": 47, "saw": 44, "soft": 72, "keys": 3, "strings": 48, "brass": 95, "bell": 38, "pluck": 59},
	"Arp": {"square": 47, "saw": 44, "soft": 97, "keys": 3, "strings": 51, "brass": 95, "bell": 38, "pluck": 59},
	"Pad": {"square": 37, "saw": 37, "soft": 34, "keys": 34, "strings": 48, "brass": 95, "bell": 36, "pluck": 48},
	"Bass": {"square": 28, "saw": 28, "soft": 66, "keys": 66, "strings": 64, "brass": 29, "bell": 66, "pluck": 66},
}
const GM_NAMES := {
	4: "Electric Piano 1", 11: "Vibraphone", 25: "Steel Guitar", 32: "Acoustic Bass", 33: "Fingered Bass",
	34: "Picked Bass", 38: "Synth Bass 1", 45: "Pizzicato Strings", 48: "String Ensemble 1", 61: "Brass Section",
	73: "Flute", 80: "Square Lead", 81: "Saw Lead", 88: "New Age Pad", 89: "Warm Pad", 90: "Polysynth Pad",
}
const MT32_NAMES := {
	3: "Elec Piano 1", 28: "Syn Bass 1", 29: "Syn Bass 2", 34: "Chorale", 36: "Soundtrack", 37: "Atmosphere",
	38: "Warm Bell", 44: "Doctor Solo", 47: "Square Wave", 48: "Str Sect 1", 51: "Pizzicato", 59: "Guitar 1",
	64: "Acou Bass 1", 66: "Elec Bass 1", 72: "Flute 1", 95: "Brs Sect 1", 97: "Vibe 1",
}
## The preview's engine (and sample) for each sound.
const PREVIEW := {
	"square": ["analog", ""], "saw": ["analog", ""], "soft": ["wavetable", ""],
	"keys": ["sampled", "epiano"], "strings": ["sampled", "strings"], "brass": ["sampled", "brass"],
	"bell": ["sampled", "bell"], "pluck": ["sampled", "pluck"],
}
## MT-32 partial reserve weights per part, before scaling to 32.
const RESERVE := {"Lead": 4, "Harmony": 3, "Arp": 3, "Pad": 8, "Bass": 3}


static func arrange(song: ChipSong, card := "mt32") -> ModuleSong:
	var out := ModuleSong.new()
	out.card = card
	out.title = song.get_title()
	out.source = song
	var mt := card == "mt32"
	var data := song.data
	var channels: Array = data["channels"]
	var instruments: Array = data.get("instruments", [])
	var lines := PackedStringArray()
	var midi_channel := 1 if mt else 0
	var dropped: Array = []
	var program_lines: Array = []
	var preview_engines := {}
	var preview_samples := {}
	for c in channels.size():
		var ch: Dictionary = channels[c]
		var drum := str(ch.get("layer", "")) == "Drums"
		var name := str(ch.get("name", "Part %d" % (c + 1)))
		var volume := clampi(roundi(float(ch.get("volume", 1.0)) * 100.0), 1, 127)
		var pan := clampi(64 + roundi(float(ch.get("pan", 0.0)) * 63.0), 0, 127)
		if drum:
			out.parts[c] = {"midi": 9, "volume": volume, "pan": pan, "reverb": 40, "setup_tick": 0}
			continue
		var count := 0
		for p in out.parts.values():
			if int(p["midi"]) != 9:
				count += 1
		if count >= int(MAX_PARTS[card]):
			dropped.append(name)
			continue
		var layer := name if PART_LAYERS.has(name) else "Lead"
		var table_layer := "Lead" if layer == "Harmony" else layer
		var inst: Dictionary = GbArranger._instrument_of(instruments, channels, c)
		var sound := sound_of(inst, layer)
		var program: int = (MT32 if mt else GM)[table_layer][sound]
		var program_name: String = (MT32_NAMES if mt else GM_NAMES)[program]
		out.parts[c] = {"midi": midi_channel, "program": program, "program_name": program_name, "volume": volume, "pan": pan, "reverb": 40, "chorus": 30 if layer == "Pad" else 0, "setup_tick": 0}
		program_lines.append("%s: %s (%d) on channel %d" % [name, program_name, program + 1, midi_channel + 1])
		var engine: Array = PREVIEW[sound]
		if layer == "Bass" and sound in ["soft", "keys", "bell"]:
			engine = ["sampled", "pluck"]
		preview_engines[layer] = engine[0]
		if engine[1] != "":
			preview_samples[layer] = engine[1]
		midi_channel += 1
		if midi_channel == 9:
			midi_channel = 10
	preview_engines["Drums"] = "sampled"
	# Polyphony: trim the pad's chords until the peak fits.
	var budget: int = LIMITS[card]
	out.peak = peak_of(song, out.parts, {}, COST[card])
	var pad := _channel_named(channels, "Pad")
	var trimmed := 0
	if out.peak > budget and pad >= 0 and out.parts.has(pad):
		var size := _largest_chord(song, pad)
		while size > 1 and out.peak > budget:
			size -= 1
			out.chord_limit[pad] = size
			out.peak = peak_of(song, out.parts, out.chord_limit, COST[card])
		trimmed = size
	out.lead_in = MidiWriter.PPQ
	if mt:
		out.sysex = mt32_setup(out, channels)
		var n := program_lines.size()
		lines.append("The MT-32's parts 1 to %d on MIDI channels 2 to %d and the rhythm part on channel 10, as it starts up." % [n, n + 1])
		lines.append("SysEx at the start sets the reverb (Room), each part's partial reserve and the MIDI channels, and shows the title on the MT-32's display.")
		lines.append("At most %d of the 32 partials sound at once (about two a note)." % out.peak)
	else:
		out.sysex = [PackedByteArray([0xF0, 0x7E, 0x7F, 0x09, 0x01, 0xF7]), roland_sysex(0x42, [0x40, 0x00, 0x7F], [0x00])]
		lines.append("General MIDI: GM System On and the Sound Canvas's GS reset at the start, then %d parts from channel 1 and the drums on channel 10." % program_lines.size())
		lines.append("At most %d of the Sound Canvas's 24 voices sound at once." % out.peak)
	for line in program_lines:
		lines.append(line + ".")
	if trimmed > 0:
		lines.append("Pad chords cut to %d notes to stay within the %s." % [trimmed, "32 partials" if mt else "24 voices"])
	for name in dropped:
		lines.append("%s dropped: the %s has %d parts." % [name, PcCards.name_of(card), MAX_PARTS[card]])
	lines.append("A beat of silence first, while the module takes the SysEx.")
	lines.append("The preview is an approximation on the app's sampled and analog engines; the %s isn't emulated." % PcCards.name_of(card))
	out.report = lines
	out.preview = _preview(song, preview_engines, preview_samples, mt)
	return out


## The sound a part's instrument is closest to: square, saw, soft, keys,
## strings, brass, bell or pluck.
static func sound_of(inst: Dictionary, layer: String) -> String:
	var engine := str(inst.get("engine", "chip"))
	if engine == "sampled":
		var sample := str(inst.get("sample", ""))
		match sample:
			"epiano":
				return "keys"
			"strings", "brass", "bell", "pluck":
				return sample
	if engine == "fm":
		return "bell" if layer == "Arp" else "keys"
	if engine == "wavetable":
		return "soft"
	var wave := str(inst.get("wave", "pulse"))
	if engine == "analog":
		return "square" if wave == "pulse" else "saw"
	match wave:
		"saw":
			return "saw"
		"triangle", "sine", "wave":
			return "soft"
	return "square"


## The most partials or voices sounding at once, with chords cut to
## [param chord_limit].
static func peak_of(song: ChipSong, parts: Dictionary, chord_limit: Dictionary, cost: int) -> int:
	var data := song.data
	var changes := {}
	var section_start := 0
	for index in data["order"]:
		var section: Dictionary = data["sections"][int(index)]
		var ids: Array = section["patterns"]
		for c in ids.size():
			if int(ids[c]) < 0 or not parts.has(c):
				continue
			var each := 1 if int(parts[c]["midi"]) == 9 else cost
			for note in data["patterns"][int(ids[c])]["notes"]:
				var count := 1
				if note.size() > 5 and note[5] is Array:
					count = (note[5] as Array).size()
					if chord_limit.has(c):
						count = mini(count, int(chord_limit[c]))
				var start := section_start + int(note[0])
				var end := start + maxi(int(note[1]), 1)
				changes[start] = int(changes.get(start, 0)) + count * each
				changes[end] = int(changes.get(end, 0)) - count * each
		section_start += int(section["length"])
	var steps := changes.keys()
	steps.sort()
	var now := 0
	var peak := 0
	for s in steps:
		now += int(changes[s])
		peak = maxi(peak, now)
	return peak


## Roland's checksum: the address and data bytes plus it sum to a multiple
## of 128.
static func roland_checksum(bytes: Array) -> int:
	var total := 0
	for b in bytes:
		total += int(b)
	return (128 - total % 128) % 128


## A Roland DT1 (data set) message for device 0x10 and [param model].
static func roland_sysex(model: int, address: Array, payload: Array) -> PackedByteArray:
	var body: Array = address.duplicate()
	body.append_array(payload)
	var out := PackedByteArray([0xF0, 0x41, 0x10, model, 0x12])
	for b in body:
		out.append(int(b) & 0x7F)
	out.append(roland_checksum(body))
	out.append(0xF7)
	return out


## The MT-32's setup: the display, the reverb, the partial reserve and the
## MIDI channels.
static func mt32_setup(out: ModuleSong, channels: Array) -> Array:
	var messages: Array = []
	var text := ("Chiptune Forge: " + out.title).substr(0, 20)
	var chars: Array = []
	for i in 20:
		var code := text.unicode_at(i) if i < text.length() else 0x20
		chars.append(code if code >= 0x20 and code < 0x7F else 0x20)
	messages.append(roland_sysex(0x16, [0x20, 0x00, 0x00], chars))
	messages.append(roland_sysex(0x16, [0x10, 0x00, 0x01], [0, 5, 4]))
	# Partial reserve for parts 1 to 8 and the rhythm part: 32 in all.
	var weights: Array = []
	for i in 8:
		weights.append(0)
	for c in out.parts:
		var midi := int(out.parts[c]["midi"])
		if midi >= 1 and midi <= 8:
			weights[midi - 1] = int(RESERVE.get(str(channels[c].get("name", "")), 2))
	var reserve: Array = []
	var total := 0
	for w in weights:
		total += int(w)
	var rhythm := 6
	var left := 32 - rhythm
	var used := 0
	for w in weights:
		var share := int(floor(float(w) * left / maxf(total, 1)))
		reserve.append(share)
		used += share
	# Whatever rounding leaves goes to the first part that has any.
	for i in reserve.size():
		if weights[i] > 0:
			reserve[i] += left - used
			break
	reserve.append(rhythm)
	messages.append(roland_sysex(0x16, [0x10, 0x00, 0x04], reserve))
	messages.append(roland_sysex(0x16, [0x10, 0x00, 0x0D], [1, 2, 3, 4, 5, 6, 7, 8, 9]))
	return messages


static func _channel_named(channels: Array, name: String) -> int:
	for c in channels.size():
		if str(channels[c].get("name", "")) == name:
			return c
	return -1


static func _largest_chord(song: ChipSong, channel: int) -> int:
	var largest := 1
	for section in song.data["sections"]:
		var ids: Array = section["patterns"]
		if channel >= ids.size() or int(ids[channel]) < 0:
			continue
		for note in song.data["patterns"][int(ids[channel])]["notes"]:
			if note.size() > 5 and note[5] is Array:
				largest = maxi(largest, (note[5] as Array).size())
	return largest


## The song on the app's engines, picked to sound like the module's
## programs, with a room's echo for its reverb.
static func _preview(song: ChipSong, engines: Dictionary, samples: Dictionary, mt: bool) -> ChipSong:
	var copy := ChipSong.new()
	copy.data = song.data.duplicate(true)
	var plain: Array = []
	for inst in song.data.get("instruments", []):
		plain.append(SynthEngines.chip_instrument(inst))
	var applied := SynthEngines.apply(plain, "chip", engines)
	for i in mini(applied.size(), SynthEngines.LAYER_OF.size()):
		var layer: String = SynthEngines.LAYER_OF[i]
		if samples.has(layer) and str(applied[i].get("engine", "")) == "sampled":
			applied[i]["sample"] = samples[layer]
	copy.data["instruments"] = applied
	var fx: Dictionary = copy.data.get("effects", {})
	fx["echo"] = maxf(float(fx.get("echo", 0.0)), 0.22 if mt else 0.16)
	fx["echo_feedback"] = 0.5 if mt else 0.4
	fx["echo_beats"] = 0.125
	copy.data["effects"] = fx
	return copy
