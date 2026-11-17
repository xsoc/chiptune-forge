class_name TargetReport
extends RefCounted
## What exporting to a target does to a song or a set of sounds: whether it
## fits the chip's limits, what the arranger changed, and data sizes. The
## Export screen shows it and the command line prints it.
##
## Lines carry BBCode colour for the screen: a line that does not fit is
## orange. [method plain] strips it.

## Songs at least this long get a note about WAV size and render time.
const LONG_SONG_SECONDS := 270.0
const WARN := "#f0a050"
## Words in an arranger's report that mean it changed the music, for
## the command line's --strict.
const CHANGE_WORDS: PackedStringArray = ["dropped", "moved", "merged", "removed", "straightened", "cut", "shortened"]

# PSGlib data size per Master System arrangement.
static var _psg_sizes := {}
# VGM size per Mega Drive arrangement.
static var _vgm_sizes := {}


## The report lines for [param target]: for the song in Music mode
## ([param arranged] is the song arranged for the target, or null for
## "modern"), or for [param sounds] in Sound FX mode. [param card] is the
## "pc" target's sound card.
static func lines(target: String, music: bool, song: ChipSong, arranged: Variant, sounds: Dictionary, card := PcCards.DEFAULT) -> Array[String]:
	match target:
		"pc":
			return _pc(music, arranged, sounds, card)
		"gameboy":
			return _gameboy(music, arranged, sounds)
		"nes":
			return _nes(music, arranged, sounds)
		"sms":
			return _sms(music, arranged, sounds)
		"genesis":
			return _md(music, arranged, sounds)
		"snes":
			return _snes(music, arranged, sounds)
		"pce":
			return _pce(music, arranged, sounds)
		"msx":
			return _ay(music, arranged, sounds)
		"c64":
			return _sid(music, arranged, sounds)
		"gba":
			return _gba(music, arranged, sounds)
	return _modern(music, song)


## True when nothing in the report is over a limit.
static func fits(report: Array[String]) -> bool:
	for line in report:
		if line.contains(WARN):
			return false
	return true


## True when the arranger dropped parts, moved notes or otherwise changed
## the music to fit.
static func changed(report: Array[String]) -> bool:
	for line in report:
		var lower := line.to_lower()
		for word in CHANGE_WORDS:
			if lower.contains(word):
				return true
	return false


## The lines without colour tags or bullets, for a terminal.
static func plain(report: Array[String]) -> PackedStringArray:
	var out := PackedStringArray()
	var tag := RegEx.create_from_string("\\[/?(b|color)[^\\]]*\\]")
	for line in report:
		var text := tag.sub(line, "", true).trim_prefix("•  ")
		if text != "":
			out.append(text)
	return out


static func _modern(music: bool, song: ChipSong) -> Array[String]:
	var lines: Array[String] = []
	if music and song:
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
	elif not music:
		lines.append("")
		lines.append("[color=#52d1c0]Fits.[/color] Each sound plays on any voice.")
	return lines


static func _gameboy(music: bool, arranged: Variant, sounds: Dictionary) -> Array[String]:
	var lines: Array[String] = [""]
	if music:
		var gb: GbSong = arranged
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


static func _nes(music: bool, arranged: Variant, sounds: Dictionary) -> Array[String]:
	var lines: Array[String] = [""]
	if music:
		var nes: NesSong = arranged
		if nes == null:
			return lines
		if nes.pattern_chunks().size() <= NesSong.MAX_PATTERNS:
			lines.append("[color=#52d1c0]Fits[/color] after arranging for 4 channels.")
		else:
			lines.append("[color=#f0a050]Too long for one FamiStudio song.[/color] Shorten the song or pick fewer sections.")
		for line in nes.report:
			lines.append("•  " + line)
		return lines
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


static func _sms(music: bool, arranged: Variant, sounds: Dictionary) -> Array[String]:
	var lines: Array[String] = [""]
	if music:
		var sms: SmsSong = arranged
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


static func _md(music: bool, arranged: Variant, sounds: Dictionary) -> Array[String]:
	var lines: Array[String] = [""]
	if music:
		var md: MdSong = arranged
		if md == null:
			return lines
		var key := md.get_instance_id()
		if not _vgm_sizes.has(key):
			_vgm_sizes = {key: MdVgmWriter.vgm_bytes(MdVgmWriter.record(md)).size()}
		lines.append("[color=#52d1c0]Fits[/color] after arranging for 10 channels: a %.1f KB VGM, which SGDK packs into XGM music of about the same size." % (_vgm_sizes[key] / 1024.0))
		for line in md.report:
			lines.append("•  " + line)
		return lines
		lines.append("[color=#52d1c0]Fits.[/color] Each sound is an 8-bit, 14 kHz sample for SGDK's XGM driver, which plays up to four over the music on FM 6.")
	var ids := sounds.keys()
	ids.sort()
	var total := 0
	for id in ids:
		var md_sfx := MdSfx.from_sfx(sounds[id], str(id))
		total += md_sfx.samples.size()
		lines.append("•  %s: %.2f s, %.1f KB" % [id, md_sfx.seconds(), md_sfx.samples.size() / 1024.0])
	lines.append("%.1f KB of samples in all." % (total / 1024.0))
	return lines


static func _snes(music: bool, arranged: Variant, sounds: Dictionary) -> Array[String]:
	var lines: Array[String] = [""]
	if music:
		var snes: SnesSong = arranged
		if snes == null:
			return lines
		var ram := snes.ram_use()
		var patterns: int = ItWriter.pattern_layout(snes)["patterns"].size()
		if int(ram["free"]) > 8192 and patterns <= ItWriter.MAX_PATTERNS:
			lines.append("[color=#52d1c0]Fits[/color] after arranging for 7 voices: %d patterns, and %.1f KB of audio RAM left for them." % [patterns, int(ram["free"]) / 1024.0])
		else:
			lines.append("[color=#f0a050]Tight on SNESMod's limits[/color] (%d of 64 patterns). Shorten the song if smconv says it is too big." % patterns)
		for line in snes.report:
			lines.append("•  " + line)
		return lines
		lines.append("[color=#52d1c0]Fits.[/color] Each sound is a 16 kHz BRR sample that SNESMod plays on voice 8, over the music.")
	var ids := sounds.keys()
	ids.sort()
	var total := 0
	for id in ids:
		var snes_sfx := SnesSfx.from_sfx(sounds[id], str(id))
		var bytes := int(ceil(snes_sfx.pcm.size() / 16.0)) * SnesBrr.BLOCK_BYTES
		total += bytes
		lines.append("•  %s: %.2f s, %.1f KB" % [id, snes_sfx.seconds(), bytes / 1024.0])
	lines.append("%.1f KB of audio RAM in all, on top of the music." % (total / 1024.0))
	return lines


static func _pce(music: bool, arranged: Variant, sounds: Dictionary) -> Array[String]:
	var lines: Array[String] = [""]
	if music:
		var pce: PceSong = arranged
		if pce == null:
			return lines
		var bytes := PceWriter.song_bytes(pce).size()
		lines.append("[color=#52d1c0]Fits[/color] after arranging for 6 channels: %.1f KB of data for the player." % (bytes / 1024.0))
		for line in pce.report:
			lines.append("•  " + line)
		return lines
		lines.append("[color=#52d1c0]Fits.[/color] Each sound plays on channel 5, over the music.")
	var ids := sounds.keys()
	ids.sort()
	for id in ids:
		var pce_sfx := PceSfx.from_sfx(sounds[id], str(id))
		lines.append("•  %s: %.2f s, %s" % [id, pce_sfx.frame_count() / PceSong.FRAME_HZ, "noise" if pce_sfx.noise else pce_sfx.wave.replace("_", " ") + " wave"])
	return lines


static func _ay(music: bool, arranged: Variant, sounds: Dictionary) -> Array[String]:
	var lines: Array[String] = [""]
	if music:
		var ay: AySong = arranged
		if ay == null:
			return lines
		var bytes := AyWriter.song_bytes(ay).size()
		lines.append("[color=#52d1c0]Fits[/color] after arranging for 3 channels: %.1f KB of data for the player." % (bytes / 1024.0))
		for line in ay.report:
			lines.append("•  " + line)
		return lines
		lines.append("[color=#52d1c0]Fits.[/color] Each sound plays on channel B, over the music.")
	var ids := sounds.keys()
	ids.sort()
	for id in ids:
		var ay_sfx := AySfx.from_sfx(sounds[id], str(id))
		lines.append("•  %s: %.2f s, %s" % [id, ay_sfx.frame_count() / AySong.FRAME_HZ, "noise" if ay_sfx.noise else "square"])
	return lines


static func _sid(music: bool, arranged: Variant, sounds: Dictionary) -> Array[String]:
	var lines: Array[String] = [""]
	if music:
		var sid: SidSong = arranged
		if sid == null:
			return lines
		var bytes := SidWriter.song_bytes(sid).size()
		lines.append("[color=#52d1c0]Fits[/color] after arranging for 3 voices: %.1f KB of data for the player." % (bytes / 1024.0))
		for line in sid.report:
			lines.append("•  " + line)
		return lines
		lines.append("[color=#52d1c0]Fits.[/color] Each sound plays on voice 2, over the music.")
	var ids := sounds.keys()
	ids.sort()
	for id in ids:
		var sid_sfx := SidSfx.from_sfx(sounds[id], str(id))
		lines.append("•  %s: %.2f s, %s" % [id, sid_sfx.frame_count() / SidSong.FRAME_HZ, "noise" if sid_sfx.noise else "pulse"])
	return lines


static func _gba(music: bool, arranged: Variant, sounds: Dictionary) -> Array[String]:
	var lines: Array[String] = [""]
	if music:
		var gba: GbaSong = arranged
		if gba == null:
			return lines
		lines.append("[color=#52d1c0]Fits[/color] after arranging for 7 of Maxmod's channels.")
		for line in gba.report:
			lines.append("•  " + line)
		return lines
		lines.append("[color=#52d1c0]Fits.[/color] Each sound plays as an 8-bit sample on Maxmod's eighth channel, over the music.")
	var ids := sounds.keys()
	ids.sort()
	for id in ids:
		var gba_sfx := GbaSfx.from_sfx(sounds[id], str(id))
		lines.append("•  %s: %.2f s, %.1f KB" % [GbaSfx.symbol(str(id)), gba_sfx.seconds(), gba_sfx.samples.size() / 1024.0])
	return lines



static func _channel_has_notes(song: ChipSong, channel: int) -> bool:
	for section in song.data["sections"]:
		var ids: Array = section["patterns"]
		if channel < ids.size() and int(ids[channel]) >= 0:
			return true
	return false


static func _clock(song: ChipSong, step: int) -> String:
	var s := int(step * song.get_step_seconds())
	return "%d:%02d" % [s / 60, s % 60]


static func _pc(music: bool, arranged: Variant, sounds: Dictionary, card: String) -> Array[String]:
	var lines: Array[String] = [""]
	if music and arranged is SpeakerSong:
		var sp: SpeakerSong = arranged
		var rec := SpeakerWriter.record(sp)
		var size := (rec["slots"] as PackedInt32Array).size() * 2
		lines.append("[color=#52d1c0]Fits[/color] after arranging for one square wave: %.1f KB of data for the player." % (size / 1024.0))
		if size > 60000:
			lines.append("[color=%s]Over 60 KB:[/color] in the small memory models one array can't be bigger than 64 KB; build with -ml or load the .bin file." % WARN)
		for line in sp.report:
			lines.append("•  " + line)
		return lines
	if music and arranged is GusSong:
		var gus: GusSong = arranged
		var size := ItWriter.module_bytes(gus, false).size()
		lines.append("[color=#52d1c0]Fits[/color] on the Gravis Ultrasound: a %.0f KB Impulse Tracker module." % (size / 1024.0))
		for line in gus.report:
			lines.append("•  " + line)
		return lines
	if music and arranged is ModuleSong:
		var mod: ModuleSong = arranged
		var limit := 32 if mod.card == "mt32" else 24
		if mod.peak > limit:
			lines.append("[color=%s]Too many notes at once:[/color] %d where the %s plays %d; some will be cut off." % [WARN, mod.peak, PcCards.name_of(mod.card), limit])
		else:
			lines.append("[color=#52d1c0]Fits[/color] on the %s: a %.1f KB MIDI file." % [PcCards.name_of(mod.card), mod.midi_bytes().size() / 1024.0])
		for line in mod.report:
			lines.append("•  " + line)
		return lines
	if music and arranged is SmsSong:
		var sms: SmsSong = arranged
		lines.append("[color=#52d1c0]Fits[/color] after arranging for the SN76496's 3 squares and noise.")
		for line in sms.report:
			lines.append("•  " + line)
		return lines
	if music:
		var opl: OplSong = arranged
		if opl == null:
			return lines
		var recorded := OplWriter.record(opl)
		var dro := OplWriter.dro_bytes(recorded, opl.chip).size()
		var melodic := 0
		for v in opl.layout:
			if str(v["drum"]) == "":
				melodic += 1
		var drums := " and the rhythm mode's drums" if melodic < opl.layout.size() else ""
		lines.append("[color=#52d1c0]Fits[/color] after arranging for %d of the %s's FM voices%s: a %.1f KB DRO file." % [melodic, PcCards.name_of(opl.card), drums, dro / 1024.0])
		for line in opl.report:
			lines.append("•  " + line)
		return lines
	if PcCards.is_module(card):
		lines.append("[color=#52d1c0]Fits.[/color] The %s plays music only, so each sound is a 22 kHz sample for a Sound Blaster beside it, as DOS games did." % PcCards.name_of(card))
	elif card == "gus":
		lines.append("[color=#52d1c0]Fits.[/color] Each sound is a 16-bit sample for a voice the music leaves free.")
	elif card == "speaker":
		lines.append("[color=#52d1c0]Fits.[/color] Each sound takes over the speaker while it plays; the music carries on underneath.")
	elif card == "tandy":
		lines.append("[color=#52d1c0]Fits.[/color] Each sound plays on Square 3 or the noise channel, over the music.")
	elif card == "adlib":
		lines.append("[color=#52d1c0]Fits.[/color] Each sound plays as FM on channel 2, in place of the harmony, which comes back when it ends.")
	else:
		lines.append("[color=#52d1c0]Fits.[/color] Each sound plays as a sample on the %s's DAC, over the FM music." % PcCards.name_of(card))
	var ids := sounds.keys()
	ids.sort()
	var total := 0
	for id in ids:
		var pc_sfx := PcSfx.from_sfx(sounds[id], card, str(id))
		if not pc_sfx.is_sample():
			lines.append("•  %s: %.2f s, %s" % [id, pc_sfx.seconds(), "noise" if pc_sfx.noisy else "tone"])
		else:
			var size := pc_sfx.samples.size() * pc_sfx.bits / 8
			total += size
			lines.append("•  %s: %.2f s, %.1f KB at %d Hz, %d-bit" % [id, pc_sfx.seconds(), size / 1024.0, pc_sfx.rate, pc_sfx.bits])
	if total > 0:
		lines.append("All the samples take %.1f KB of memory." % (total / 1024.0))
	return lines
