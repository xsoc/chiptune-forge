class_name ExportJob
extends RefCounted
## Builds the files for an export a little at a time, so the UI stays
## responsive while audio renders (web builds have no threads). Call
## [method step] every frame until [member done], then [method build_zip].

const MIX_RATE := 44100
## The WAV sample rates an export can use.
const RATES: Array[int] = [44100, 48000]
const BLOCK := 4096

var files: Dictionary = {}
var progress := 0.0
var done := false
var status := ""
## The sample rate of the WAV files: [constant MIX_RATE] or 48000 (option
## "rate").
var rate := MIX_RATE

var _tasks: Array[Callable] = []
var _task_index := 0
# The render in progress. Each block is written straight into the finished
# WAV bytes, so a long song never holds its float frames in memory.
var _r_path := ""
var _r_seq: ChipSongSequencer
var _r_gb: GbSong
var _r_nes: NesSong
var _r_total := 0
var _r_written := 0
var _r_bytes := PackedByteArray()
var _r_header := 0
var _r_fraction := 0.0


## Target ids, in the order the app lists them.
const TARGETS: PackedStringArray = ["modern", "gameboy", "nes", "sms", "genesis", "snes", "pce", "gba", "msx", "c64", "pc"]


## [param song] arranged for [param target], or null for "modern" (or an
## unknown target). [param gameboy_options] are the Game Boy's sound effect
## channel options (see [GbArranger]); for "pc" they hold the "card".
static func arrange(target: String, song: ChipSong, gameboy_options := {}) -> Variant:
	match target:
		"pc":
			return PcCards.arrange(SynthEngines.chip_song(song), str(gameboy_options.get("card", PcCards.DEFAULT)))
		"gameboy":
			return GbArranger.arrange(SynthEngines.chip_song(song), gameboy_options)
		"nes":
			return NesArranger.arrange(SynthEngines.chip_song(song))
		"sms":
			return SmsArranger.arrange(SynthEngines.chip_song(song))
		"genesis":
			return MdArranger.arrange(SynthEngines.chip_song(song))
		"snes":
			return SnesArranger.arrange(SynthEngines.chip_song(song))
		"pce":
			return PceArranger.arrange(SynthEngines.chip_song(song))
		"msx":
			return AyArranger.arrange(SynthEngines.chip_song(song))
		"c64":
			return SidArranger.arrange(SynthEngines.chip_song(song))
		"gba":
			return GbaArranger.arrange(SynthEngines.chip_song(song))
	return null


## The export of a song for any target, as the Export screen makes it.
## [param arranged] is the song already arranged for the target, or null to
## arrange it here.
## Options as for each target's own export, plus "project": the .cforge
## text to include as <prefix>.cforge.
static func for_target_song(target: String, song: ChipSong, options: Dictionary, arranged: Variant = null) -> ExportJob:
	var job := _song_job(target, song, _with_ogg(options), arranged)
	job._use_rate(options)
	var meta: Dictionary = song.data.get("meta", {})
	job._use_ogg(options, song.get_title(), "Made with Chiptune Forge. Seed %s. %s" % [meta.get("seed", ""), meta.get("license", "")])
	if options.has("project"):
		job.files["%s.%s" % [sanitize(str(options.get("prefix", song.get_title()))), ProjectFile.EXTENSION]] = str(options["project"]).to_utf8_buffer()
	return job


static func _song_job(target: String, song: ChipSong, options: Dictionary, arranged: Variant) -> ExportJob:
	if arranged == null:
		var gameboy: Dictionary = options.get("gameboy", {})
		var arrange_options: Dictionary = {"card": options.get("card", gameboy.get("card", PcCards.DEFAULT))} if target == "pc" else gameboy
		arranged = arrange(target, song, arrange_options)
	match target:
		"pc":
			return for_pc_song(arranged, options)
		"gameboy":
			return for_gameboy_song(arranged, options)
		"nes":
			return for_nes_song(arranged, options)
		"sms":
			return for_sms_song(arranged, options)
		"genesis":
			return for_md_song(arranged, options)
		"snes":
			return for_snes_song(arranged, options)
		"pce":
			return for_pce_song(arranged, options)
		"msx":
			return for_ay_song(arranged, options)
		"c64":
			return for_sid_song(arranged, options)
		"gba":
			return for_gba_song(arranged, options)
	return for_song(song, options)


## The export of a set of sounds (id to [ChipSfx]) for any target.
static func for_target_sfx(target: String, sounds: Dictionary, kit_name: String, options: Dictionary) -> ExportJob:
	var job := _sfx_job(target, sounds, kit_name, _with_ogg(options))
	job._use_rate(options)
	job._use_ogg(options, kit_name, "Made with Chiptune Forge.")
	if options.has("project"):
		job.files["%s.%s" % [sanitize(kit_name), ProjectFile.EXTENSION]] = str(options["project"]).to_utf8_buffer()
	return job


static func _sfx_job(target: String, sounds: Dictionary, kit_name: String, options: Dictionary) -> ExportJob:
	match target:
		"pc":
			return for_pc_sfx(sounds, kit_name, options)
		"gameboy":
			return for_gameboy_sfx(sounds, kit_name, options)
		"nes":
			return for_nes_sfx(sounds, kit_name, options)
		"sms":
			return for_sms_sfx(sounds, kit_name, options)
		"genesis":
			return for_md_sfx(sounds, kit_name, options)
		"snes":
			return for_snes_sfx(sounds, kit_name, options)
		"pce":
			return for_pce_sfx(sounds, kit_name, options)
		"msx":
			return for_ay_sfx(sounds, kit_name, options)
		"c64":
			return for_sid_sfx(sounds, kit_name, options)
		"gba":
			return for_gba_sfx(sounds, kit_name, options)
	return for_sfx(sounds, kit_name, options)


## Runs the job to the end, for the command line and tests.
func run() -> void:
	while not done:
		step(1000000)


## Writes the files into a folder, as the zip would hold them. Returns the
## paths written, or an error message as the only entry starting "error: ".
func write_to(dir: String) -> PackedStringArray:
	var written := PackedStringArray()
	var names := files.keys()
	names.sort()
	for name in names:
		var path := dir.path_join(name)
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			return PackedStringArray(["error: cannot write %s (%s)" % [path, error_string(FileAccess.get_open_error())]])
		file.store_buffer(files[name])
		file.close()
		written.append(path)
	return written


## Export for a song. Options: prefix, godot, plugin, wav, loops, stems, midi.
static func for_song(song: ChipSong, options: Dictionary) -> ExportJob:
	var job := ExportJob.new()
	var prefix := sanitize(str(options.get("prefix", song.get_title())))
	if bool(options.get("godot", true)):
		job._tasks.append(func() -> bool:
			job.files["godot/%s.chipsong" % prefix] = song.to_json().to_utf8_buffer()
			if bool(options.get("plugin", true)):
				job._add_plugin("godot/")
			return true)
	if bool(options.get("midi", false)):
		job._tasks.append(func() -> bool:
			job.files["midi/%s.mid" % prefix] = MidiWriter.encode(song)
			return true)
	if bool(options.get("wav", true)):
		var loops := int(options.get("loops", 1))
		job._queue_render(song, "audio/%s.wav" % prefix, loops, [])
		if bool(options.get("stems", false)):
			for layer in SongSettings.LAYERS:
				var muted: Array = []
				for c in GenContext.CHANNEL_COUNT:
					if not SongGenerator.LAYER_CHANNELS[layer].has(c):
						muted.append(c)
				job._queue_render(song, "audio/stems/%s_%s.wav" % [prefix, layer.to_lower()], loops, muted)
	job._tasks.append(func() -> bool:
		job.files["README.txt"] = job._song_readme(song, prefix, options).to_utf8_buffer()
		return true)
	return job


## Export for a song arranged for the Game Boy: a GBDK-2020 project with the
## song as hUGEDriver C data, plus optional WAV (rendered through the emulated
## sound chip) and MIDI of the arranged parts. Options: prefix, wav, loops,
## midi.
static func for_gameboy_song(gb: GbSong, options: Dictionary) -> ExportJob:
	var job := ExportJob.new()
	var song := gb.source
	var prefix := sanitize(str(options.get("prefix", gb.title)))
	var meta: Dictionary = song.data.get("meta", {})
	var credit := "Made with Chiptune Forge. Seed %s. %s" % [meta.get("seed", ""), meta.get("license", "")]
	if bool(options.get("console", true)):
		job._tasks.append(func() -> bool:
			var symbol := GbCWriter.song_symbol(prefix)
			var project := GbCWriter.song_project(gb, symbol, gb.title, credit)
			for path in project:
				job.files["gameboy/" + path] = project[path]
			return true)
	if bool(options.get("midi", false)):
		job._tasks.append(func() -> bool:
			job.files["midi/%s.mid" % prefix] = MidiWriter.encode(song)
			return true)
	if bool(options.get("wav", true)):
		job._r_gb = gb
		job._queue_render(song, "audio/%s.wav" % prefix, int(options.get("loops", 1)), [])
	job._tasks.append(func() -> bool:
		job.files["README.txt"] = job._gameboy_readme(gb, prefix, options).to_utf8_buffer()
		return true)
	return job


## Export for a song arranged for the NES: the song as music data for
## FamiStudio's sound engine (ca65) in a project that builds a ROM, and the
## FamiStudio text project it comes from, plus
## optional WAV (rendered through the emulated 2A03) and MIDI of the arranged
## parts. Options: prefix, wav, loops, midi.
static func for_nes_song(nes: NesSong, options: Dictionary) -> ExportJob:
	var job := ExportJob.new()
	var song := nes.source
	var prefix := sanitize(str(options.get("prefix", nes.title)))
	var meta: Dictionary = song.data.get("meta", {})
	var credit := "Made with Chiptune Forge. Seed %s. %s" % [meta.get("seed", ""), meta.get("license", "")]
	if bool(options.get("console", true)):
		job._tasks.append(func() -> bool:
			var project := FamiStudioAsmWriter.song_project(nes, prefix, credit)
			for path in project:
				job.files["nes/" + path] = project[path]
			job.files["nes/famistudio/%s.txt" % prefix] = FamiStudioWriter.song_project(nes, nes.title, credit).to_utf8_buffer()
			job.files["nes/famistudio/README.txt"] = FamiStudioWriter.readme("song", "%s.txt" % prefix).to_utf8_buffer()
			return true)
	if bool(options.get("midi", false)):
		job._tasks.append(func() -> bool:
			job.files["midi/%s.mid" % prefix] = MidiWriter.encode(song)
			return true)
	if bool(options.get("wav", true)):
		job._r_nes = nes
		job._queue_render(song, "audio/%s.wav" % prefix, int(options.get("loops", 1)), [])
	job._tasks.append(func() -> bool:
		job.files["README.txt"] = job._nes_readme(nes, prefix, options).to_utf8_buffer()
		return true)
	return job


## Export for sound effects on the NES: the sounds for FamiStudio's sound
## engine in a project that builds a ROM, a FamiStudio text project with one
## song per sound, and WAVs of how each one sounds on the console.
static func for_nes_sfx(sounds: Dictionary, kit_name: String, options: Dictionary) -> ExportJob:
	var job := ExportJob.new()
	var prefix := sanitize(kit_name)
	var converted: Array = []
	var ids := sounds.keys()
	ids.sort()
	for id in ids:
		converted.append(NesSfx.from_sfx(sounds[id], sanitize(str(id))))
	if bool(options.get("console", true)):
		job._tasks.append(func() -> bool:
			var project := FamiStudioAsmWriter.sfx_project(converted, prefix)
			for path in project:
				job.files["nes/" + path] = project[path]
			job.files["nes/famistudio/%s.txt" % prefix] = FamiStudioWriter.sfx_project(converted, kit_name).to_utf8_buffer()
			job.files["nes/famistudio/README.txt"] = FamiStudioWriter.readme("sfx", "%s.txt" % prefix).to_utf8_buffer()
			return true)
	if bool(options.get("wav", true)):
		for nes_sfx in converted:
			job._tasks.append(func() -> bool:
				job.files["audio/%s.wav" % nes_sfx.name] = ChipAudio.encode_wav_mono(nes_sfx.render(job.rate), job.rate)
				return true)
	job._tasks.append(func() -> bool:
		var lines: Array[String] = [
			"Sound kit for the NES: %s" % prefix,
			"Made with Chiptune Forge. You own these sounds and may use them for any purpose, including commercially.",
			"",
			"nes/    The sounds for FamiStudio's sound engine (ca65) and an example ROM project.\n        See nes/README.txt. nes/famistudio/ has them as a FamiStudio project to edit." if bool(options.get("console", true)) else "",
			"audio/  One WAV per sound, as the NES plays it.",
			"",
			"Sounds:",
		]
		for nes_sfx in converted:
			var text := "  %s  (%s, %d frames)" % [nes_sfx.name, "Pulse 2" if nes_sfx.channel == NesSong.PULSE2 else "Noise", nes_sfx.frame_count()]
			if not nes_sfx.notes.is_empty():
				text += ": " + ", ".join(nes_sfx.notes)
			lines.append(text)
		job.files["README.txt"] = "\n".join(lines).to_utf8_buffer()
		return true)
	return job


## Export for a song arranged for the Master System and Game Gear: PSGlib
## data (as a .psg file and as a C array for devkitSMS) and a VGM file, plus
## optional WAV (rendered through the emulated SN76489) and MIDI of the
## arranged parts. Options: prefix, wav, loops, midi.
static func for_sms_song(sms: SmsSong, options: Dictionary) -> ExportJob:
	var job := ExportJob.new()
	var song := sms.source
	var prefix := sanitize(str(options.get("prefix", sms.title)))
	var meta: Dictionary = song.data.get("meta", {})
	var credit := "%s. Made with Chiptune Forge. Seed %s. %s" % [sms.title, meta.get("seed", ""), meta.get("license", "")]
	if bool(options.get("console", true)):
		job._tasks.append(func() -> bool:
			var recorded := PsgWriter.record(sms)
			var psg := PsgWriter.encode(recorded)
			var blobs := {PsgWriter.symbol(prefix) + "_psg": psg}
			job.files["sms/%s.psg" % prefix] = psg
			job.files["sms/%s.vgm" % prefix] = PsgWriter.vgm_bytes(recorded)
			job.files["sms/%s_psg.c" % prefix] = PsgWriter.c_source(blobs, "%s_psg.h" % prefix, credit).to_utf8_buffer()
			job.files["sms/%s_psg.h" % prefix] = PsgWriter.c_header(blobs, PsgWriter.symbol(prefix).to_upper() + "_PSG_H", credit).to_utf8_buffer()
			job.files["sms/README.txt"] = PsgWriter.readme("song", prefix).to_utf8_buffer()
			return true)
	if bool(options.get("midi", false)):
		job._tasks.append(func() -> bool:
			job.files["midi/%s.mid" % prefix] = MidiWriter.encode(song)
			return true)
	if bool(options.get("wav", true)):
		job._r_nes = sms
		job._queue_render(song, "audio/%s.wav" % prefix, int(options.get("loops", 1)), [])
	job._tasks.append(func() -> bool:
		job.files["README.txt"] = job._sms_readme(sms, prefix, options).to_utf8_buffer()
		return true)
	return job


## Export for sound effects on the Master System and Game Gear: one PSGlib
## file and one VGM per sound, the sounds as C arrays, and WAVs of how each
## one sounds on the console.
static func for_sms_sfx(sounds: Dictionary, kit_name: String, options: Dictionary) -> ExportJob:
	var job := ExportJob.new()
	var prefix := sanitize(kit_name)
	var converted: Array = []
	var ids := sounds.keys()
	ids.sort()
	for id in ids:
		converted.append(SmsSfx.from_sfx(sounds[id], sanitize(str(id))))
	if bool(options.get("console", true)):
		job._tasks.append(func() -> bool:
			var blobs := {}
			for sms_sfx: SmsSfx in converted:
				var recorded := PsgWriter.record(sms_sfx.to_song(), 1 << sms_sfx.channel)
				var psg := PsgWriter.encode(recorded)
				job.files["sms/%s.psg" % sms_sfx.name] = psg
				job.files["sms/%s.vgm" % sms_sfx.name] = PsgWriter.vgm_bytes(recorded)
				blobs[PsgWriter.symbol(sms_sfx.name) + "_psg"] = psg
			var comment := "%s: sound effects made with Chiptune Forge" % kit_name
			job.files["sms/%s.c" % prefix] = PsgWriter.c_source(blobs, "%s.h" % prefix, comment).to_utf8_buffer()
			job.files["sms/%s.h" % prefix] = PsgWriter.c_header(blobs, PsgWriter.symbol(prefix).to_upper() + "_H", comment).to_utf8_buffer()
			job.files["sms/README.txt"] = PsgWriter.readme("sfx", prefix, converted).to_utf8_buffer()
			return true)
	if bool(options.get("wav", true)):
		for sms_sfx in converted:
			job._tasks.append(func() -> bool:
				job.files["audio/%s.wav" % sms_sfx.name] = ChipAudio.encode_wav_mono(sms_sfx.render(job.rate), job.rate)
				return true)
	job._tasks.append(func() -> bool:
		var lines: Array[String] = [
			"Sound kit for the Master System and Game Gear: %s" % prefix,
			"Made with Chiptune Forge. You own these sounds and may use them for any purpose, including commercially.",
			"",
			"sms/    PSGlib data for each sound (.psg and as C arrays) and a VGM of each.\n        See sms/README.txt to play them over your music." if bool(options.get("console", true)) else "",
			"audio/  One WAV per sound, as the Master System plays it.",
			"",
			"Sounds:",
		]
		for sms_sfx: SmsSfx in converted:
			var text := "  %s  (%s, %d frames)" % [sms_sfx.name, "Square 3" if sms_sfx.channel == SmsSong.SQUARE3 else "Noise", sms_sfx.frame_count()]
			if not sms_sfx.notes.is_empty():
				text += ": " + ", ".join(sms_sfx.notes)
			lines.append(text)
		job.files["README.txt"] = "\n".join(lines).to_utf8_buffer()
		return true)
	return job


## Export for a song arranged for the Mega Drive / Genesis: a VGM for SGDK
## (which converts it to XGM music), the resource line and a minimal SGDK
## program, plus optional WAV (rendered through the emulated YM2612 and
## SN76489) and MIDI of the arranged parts. Options: prefix, wav, loops, midi.
static func for_md_song(md: MdSong, options: Dictionary) -> ExportJob:
	var job := ExportJob.new()
	var song := md.source
	var prefix := sanitize(str(options.get("prefix", md.title)))
	var meta: Dictionary = song.data.get("meta", {})
	var credit := "Made with Chiptune Forge. Seed %s. %s" % [meta.get("seed", ""), meta.get("license", "")]
	if bool(options.get("console", true)):
		job._tasks.append(func() -> bool:
			var sym := PsgWriter.symbol(prefix)
			job.files["genesis/%s.vgm" % prefix] = MdVgmWriter.vgm_bytes(MdVgmWriter.record(md), md.title, credit)
			job.files["genesis/resources.res"] = (MdVgmWriter.res_line(sym, prefix + ".vgm") + "\n").to_utf8_buffer()
			job.files["genesis/main.c"] = MdVgmWriter.main_c(sym, md.title).to_utf8_buffer()
			job.files["genesis/README.txt"] = MdVgmWriter.readme(prefix).to_utf8_buffer()
			return true)
	if bool(options.get("midi", false)):
		job._tasks.append(func() -> bool:
			job.files["midi/%s.mid" % prefix] = MidiWriter.encode(song)
			return true)
	if bool(options.get("wav", true)):
		job._r_nes = md
		job._queue_render(song, "audio/%s.wav" % prefix, int(options.get("loops", 1)), [])
	job._tasks.append(func() -> bool:
		job.files["README.txt"] = job._md_readme(md, prefix, options).to_utf8_buffer()
		return true)
	return job


## Export for sound effects on the Mega Drive: one 8-bit, 14 kHz WAV per
## sound for SGDK's XGM driver, the resource lines, and WAVs of how each
## one sounds on the console.
static func for_md_sfx(sounds: Dictionary, kit_name: String, options: Dictionary) -> ExportJob:
	var job := ExportJob.new()
	var prefix := sanitize(kit_name)
	var converted: Array = []
	var ids := sounds.keys()
	ids.sort()
	for id in ids:
		converted.append(MdSfx.from_sfx(sounds[id], sanitize(str(id))))
	if bool(options.get("console", true)):
		job._tasks.append(func() -> bool:
			for md_sfx: MdSfx in converted:
				job.files["genesis/%s.wav" % md_sfx.name] = md_sfx.wav_bytes()
			job.files["genesis/resources.res"] = MdSfx.res_lines(converted).to_utf8_buffer()
			job.files["genesis/README.txt"] = MdSfx.readme(prefix, converted).to_utf8_buffer()
			return true)
	if bool(options.get("wav", true)):
		for md_sfx in converted:
			job._tasks.append(func() -> bool:
				job.files["audio/%s.wav" % md_sfx.name] = ChipAudio.encode_wav_mono(md_sfx.render(job.rate), job.rate)
				return true)
	job._tasks.append(func() -> bool:
		var lines: Array[String] = [
			"Sound kit for the Mega Drive / Genesis: %s" % prefix,
			"Made with Chiptune Forge. You own these sounds and may use them for any purpose, including commercially.",
			"",
			"genesis/  One 8-bit, 14 kHz WAV per sound for SGDK's XGM driver, and resources.res.\n          See genesis/README.txt to play them over your music." if bool(options.get("console", true)) else "",
			"audio/    One WAV per sound, 44.1 kHz, as the Mega Drive plays it.",
			"",
			"Sounds:",
		]
		for md_sfx: MdSfx in converted:
			lines.append("  %s  (%.2f s)" % [MdSfx.symbol(md_sfx.name), md_sfx.seconds()])
		job.files["README.txt"] = "\n".join(lines).to_utf8_buffer()
		return true)
	return job


## Export for a song arranged for the Game Boy Advance: an Impulse Tracker
## module with 8-bit samples for Maxmod, with a devkitARM project that plays
## it, plus optional WAV (rendered through the emulated mixer) and MIDI of
## the arranged parts. Options: prefix, wav, loops, midi, console.
static func for_gba_song(gba: GbaSong, options: Dictionary) -> ExportJob:
	var job := ExportJob.new()
	var song := gba.source
	var prefix := sanitize(str(options.get("prefix", gba.title)))
	if bool(options.get("console", true)):
		job._tasks.append(func() -> bool:
			job.files["gba/audio/%s.it" % prefix] = GbaWriter.module_bytes(gba)
			job.files["gba/Makefile"] = GbaWriter.makefile(prefix).to_utf8_buffer()
			job.files["gba/main.c"] = GbaWriter.main_c(gba.title, ItWriter.module_id(prefix + ".it")).to_utf8_buffer()
			job.files["gba/README.txt"] = GbaWriter.readme(prefix, gba).to_utf8_buffer()
			return true)
	if bool(options.get("midi", false)):
		job._tasks.append(func() -> bool:
			job.files["midi/%s.mid" % prefix] = MidiWriter.encode(song)
			return true)
	if bool(options.get("wav", true)):
		job._r_nes = gba
		job._queue_render(song, "audio/%s.wav" % prefix, int(options.get("loops", 1)), [])
	job._tasks.append(func() -> bool:
		var meta: Dictionary = song.data.get("meta", {})
		job.files["README.txt"] = "\n".join([
			"%s, arranged for the Game Boy Advance" % gba.title,
			"Made with Chiptune Forge. Seed %s, %s, %d BPM on the console." % [meta.get("seed", ""), meta.get("key", ""), int(gba.get_bpm())],
			"",
			str(meta.get("license", "")),
			"",
			"gba/      An Impulse Tracker module for Maxmod (devkitPro), with a Makefile and\n          main.c that build a ROM playing it. See gba/README.txt." if bool(options.get("console", true)) else "",
			"audio/    WAV, 44.1 kHz, 16-bit, rendered through an emulation of Maxmod's mixer." if bool(options.get("wav", true)) else "",
			"midi/     The arranged parts, one track each." if bool(options.get("midi", false)) else "",
			"",
			"Arrangement:",
			"\n".join(Array(gba.report).map(func(line: String) -> String: return "  " + line)),
		]).to_utf8_buffer()
		return true)
	return job


## Export for sound effects on the Game Boy Advance: one 8-bit, 16 kHz WAV
## per sound for Maxmod's soundbank, and WAVs of how each sounds.
static func for_gba_sfx(sounds: Dictionary, kit_name: String, options: Dictionary) -> ExportJob:
	var job := ExportJob.new()
	var prefix := sanitize(kit_name)
	var converted: Array = []
	var ids := sounds.keys()
	ids.sort()
	for id in ids:
		converted.append(GbaSfx.from_sfx(sounds[id], sanitize(str(id))))
	if bool(options.get("console", true)):
		job._tasks.append(func() -> bool:
			for gba_sfx: GbaSfx in converted:
				job.files["gba/audio/%s.wav" % gba_sfx.name] = gba_sfx.wav_bytes()
			job.files["gba/README.txt"] = GbaSfx.readme(prefix, converted).to_utf8_buffer()
			return true)
	if bool(options.get("wav", true)):
		for gba_sfx in converted:
			job._tasks.append(func() -> bool:
				job.files["audio/%s.wav" % gba_sfx.name] = ChipAudio.encode_wav_mono(gba_sfx.render(job.rate), job.rate)
				return true)
	job._tasks.append(func() -> bool:
		var lines: Array[String] = [
			"Sound kit for the Game Boy Advance: %s" % prefix,
			"Made with Chiptune Forge. You own these sounds and may use them for any purpose, including commercially.",
			"",
			"gba/      One 8-bit, 16 kHz WAV per sound for Maxmod's soundbank.\n          See gba/README.txt to play them over your music." if bool(options.get("console", true)) else "",
			"audio/    One WAV per sound, 44.1 kHz, as the GBA plays it.",
			"",
			"Sounds:",
		]
		for gba_sfx: GbaSfx in converted:
			lines.append("  %s  (%.2f s)" % [GbaSfx.symbol(gba_sfx.name), gba_sfx.seconds()])
		job.files["README.txt"] = "\n".join(lines).to_utf8_buffer()
		return true)
	return job


## Export for a song arranged for the SNES: an Impulse Tracker module for
## SNESMod with a PVSnesLib project that plays it, plus optional WAV
## (rendered through the emulated S-DSP) and MIDI of the arranged parts.
## Options: prefix, wav, loops, midi, console.
static func for_snes_song(snes: SnesSong, options: Dictionary) -> ExportJob:
	var job := ExportJob.new()
	var song := snes.source
	var prefix := sanitize(str(options.get("prefix", snes.title)))
	if bool(options.get("console", true)):
		job._tasks.append(func() -> bool:
			job.files["snes/res/%s.it" % prefix] = ItWriter.module_bytes(snes)
			job.files["snes/Makefile"] = ItWriter.makefile(prefix).to_utf8_buffer()
			job.files["snes/main.c"] = ItWriter.main_c(prefix, snes.title).to_utf8_buffer()
			job.files["snes/README.txt"] = ItWriter.readme(prefix, snes).to_utf8_buffer()
			return true)
	if bool(options.get("midi", false)):
		job._tasks.append(func() -> bool:
			job.files["midi/%s.mid" % prefix] = MidiWriter.encode(song)
			return true)
	if bool(options.get("wav", true)):
		job._r_nes = snes
		job._queue_render(song, "audio/%s.wav" % prefix, int(options.get("loops", 1)), [])
	job._tasks.append(func() -> bool:
		job.files["README.txt"] = job._snes_readme(snes, prefix, options).to_utf8_buffer()
		return true)
	return job


## Export for sound effects on the SNES: one 16 kHz BRR sample per sound,
## the assembly that puts them in the ROM, and WAVs of how each sounds.
static func for_snes_sfx(sounds: Dictionary, kit_name: String, options: Dictionary) -> ExportJob:
	var job := ExportJob.new()
	var prefix := sanitize(kit_name)
	var converted: Array = []
	var ids := sounds.keys()
	ids.sort()
	for id in ids:
		converted.append(SnesSfx.from_sfx(sounds[id], sanitize(str(id))))
	if bool(options.get("console", true)):
		for snes_sfx in converted:
			job._tasks.append(func() -> bool:
				job.files["snes/%s.brr" % snes_sfx.name] = snes_sfx.brr_bytes()
				return true)
		job._tasks.append(func() -> bool:
			job.files["snes/data.asm"] = SnesSfx.data_asm(converted).to_utf8_buffer()
			job.files["snes/README.txt"] = SnesSfx.readme(prefix, converted).to_utf8_buffer()
			return true)
	if bool(options.get("wav", true)):
		for snes_sfx in converted:
			job._tasks.append(func() -> bool:
				job.files["audio/%s.wav" % snes_sfx.name] = ChipAudio.encode_wav_mono(snes_sfx.render(job.rate), job.rate)
				return true)
	job._tasks.append(func() -> bool:
		var lines: Array[String] = [
			"Sound kit for the SNES: %s" % prefix,
			"Made with Chiptune Forge. You own these sounds and may use them for any purpose, including commercially.",
			"",
			"snes/   One 16 kHz BRR sample per sound for PVSnesLib, and data.asm.\n        See snes/README.txt to play them over your music." if bool(options.get("console", true)) else "",
			"audio/  One WAV per sound, 44.1 kHz, as the SNES plays it.",
			"",
			"Sounds:",
		]
		for snes_sfx: SnesSfx in converted:
			lines.append("  %s  (%.2f s)" % [SnesSfx.symbol(snes_sfx.name), snes_sfx.seconds()])
		job.files["README.txt"] = "\n".join(lines).to_utf8_buffer()
		return true)
	return job


## Export for a song arranged for the PC Engine: data for our C player
## with a HuCC project that plays it, plus optional WAV (rendered through
## the emulated PSG) and MIDI of the arranged parts.
## Options: prefix, wav, loops, midi, console.
static func for_pce_song(pce: PceSong, options: Dictionary) -> ExportJob:
	var job := ExportJob.new()
	var song := pce.source
	var prefix := sanitize(str(options.get("prefix", pce.title)))
	if bool(options.get("console", true)):
		job._tasks.append(func() -> bool:
			job.files["pce/song.bin"] = PceWriter.song_bytes(pce)
			job.files["pce/pce_player.c"] = PceWriter.player_c().to_utf8_buffer()
			job.files["pce/main.c"] = PceWriter.main_c(pce.title).to_utf8_buffer()
			job.files["pce/Makefile"] = PceWriter.makefile(prefix).to_utf8_buffer()
			job.files["pce/README.txt"] = PceWriter.song_readme(prefix, pce).to_utf8_buffer()
			return true)
	if bool(options.get("midi", false)):
		job._tasks.append(func() -> bool:
			job.files["midi/%s.mid" % prefix] = MidiWriter.encode(song)
			return true)
	if bool(options.get("wav", true)):
		job._r_nes = pce
		job._queue_render(song, "audio/%s.wav" % prefix, int(options.get("loops", 1)), [])
	job._tasks.append(func() -> bool:
		var meta: Dictionary = song.data.get("meta", {})
		job.files["README.txt"] = "\n".join([
			"%s, arranged for the PC Engine / TurboGrafx-16" % pce.title,
			"Made with Chiptune Forge. Seed %s, %s, %d BPM on the console." % [meta.get("seed", ""), meta.get("key", ""), int(pce.get_bpm())],
			"",
			str(meta.get("license", "")),
			"",
			"pce/      song.bin and Chiptune Forge's C player (MIT) for HuCC, with a Makefile\n          and main.c that build a ROM playing it. See pce/README.txt." if bool(options.get("console", true)) else "",
			"audio/    WAV, 44.1 kHz, 16-bit, rendered through an emulated PC Engine PSG." if bool(options.get("wav", true)) else "",
			"midi/     The arranged parts, one track each." if bool(options.get("midi", false)) else "",
			"",
			"Arrangement:",
			"\n".join(Array(pce.report).map(func(line: String) -> String: return "  " + line)),
		]).to_utf8_buffer()
		return true)
	return job


## Export for sound effects on the PC Engine: the sounds as data for our C
## player, and WAVs of how each sounds.
static func for_pce_sfx(sounds: Dictionary, kit_name: String, options: Dictionary) -> ExportJob:
	var job := ExportJob.new()
	var prefix := sanitize(kit_name)
	var converted: Array = []
	var ids := sounds.keys()
	ids.sort()
	for id in ids:
		converted.append(PceSfx.from_sfx(sounds[id], sanitize(str(id))))
	if bool(options.get("console", true)):
		job._tasks.append(func() -> bool:
			job.files["pce/sfx.bin"] = PceWriter.sfx_bytes(converted)
			job.files["pce/pce_player.c"] = PceWriter.player_c().to_utf8_buffer()
			job.files["pce/README.txt"] = PceWriter.sfx_readme(prefix, converted).to_utf8_buffer()
			return true)
	if bool(options.get("wav", true)):
		for pce_sfx in converted:
			job._tasks.append(func() -> bool:
				job.files["audio/%s.wav" % pce_sfx.name] = ChipAudio.encode_wav_mono(pce_sfx.render(job.rate), job.rate)
				return true)
	job._tasks.append(func() -> bool:
		var lines: Array[String] = [
			"Sound kit for the PC Engine / TurboGrafx-16: %s" % prefix,
			"Made with Chiptune Forge. You own these sounds and may use them for any purpose, including commercially.",
			"",
			"pce/    sfx.bin and Chiptune Forge's C player (MIT) for HuCC.\n        See pce/README.txt to play them over your music." if bool(options.get("console", true)) else "",
			"audio/  One WAV per sound, 44.1 kHz, as the PC Engine plays it.",
			"",
			"Sounds:",
		]
		for i in converted.size():
			lines.append("  %d  %s" % [i, (converted[i] as PceSfx).name])
		job.files["README.txt"] = "\n".join(lines).to_utf8_buffer()
		return true)
	return job


## Export for a song arranged for the MSX and ZX Spectrum 128: data for our
## Z80 player with example programs for both machines, a VGM file, plus
## optional WAV (rendered through the emulated AY-3-8910) and MIDI of the
## arranged parts. Options: prefix, wav, loops, midi, console.
static func for_ay_song(ay: AySong, options: Dictionary) -> ExportJob:
	var job := ExportJob.new()
	var song := ay.source
	var prefix := sanitize(str(options.get("prefix", ay.title)))
	if bool(options.get("console", true)):
		job._tasks.append(func() -> bool:
			for machine in AyWriter.MACHINES:
				job.files["msx/song_%s.bin" % machine] = AyWriter.song_bytes(ay, AyWriter.MACHINES[machine])
			job.files["msx/song.vgm"] = AyWriter.vgm_bytes(ay)
			job.files["msx/ay_player.asm"] = AyWriter.player_asm().to_utf8_buffer()
			job.files["msx/msx_main.asm"] = AyWriter.msx_main(ay.title).to_utf8_buffer()
			job.files["msx/zx_main.asm"] = AyWriter.zx_main(ay.title).to_utf8_buffer()
			job.files["msx/Makefile"] = AyWriter.makefile(prefix).to_utf8_buffer()
			job.files["msx/README.txt"] = AyWriter.song_readme(prefix, ay).to_utf8_buffer()
			return true)
	if bool(options.get("midi", false)):
		job._tasks.append(func() -> bool:
			job.files["midi/%s.mid" % prefix] = MidiWriter.encode(song)
			return true)
	if bool(options.get("wav", true)):
		job._r_nes = ay
		job._queue_render(song, "audio/%s.wav" % prefix, int(options.get("loops", 1)), [])
	job._tasks.append(func() -> bool:
		var meta: Dictionary = song.data.get("meta", {})
		job.files["README.txt"] = "\n".join([
			"%s, arranged for the MSX and ZX Spectrum 128 (AY-3-8910)" % ay.title,
			"Made with Chiptune Forge. Seed %s, %s, %d BPM on the machine." % [meta.get("seed", ""), meta.get("key", ""), int(ay.get_bpm())],
			"",
			str(meta.get("license", "")),
			"",
			"msx/      The song for Chiptune Forge's Z80 player (MIT), with programs that build\n          an MSX cartridge and a Spectrum tape, and a VGM file. See msx/README.txt." if bool(options.get("console", true)) else "",
			"audio/    WAV, 44.1 kHz, 16-bit, rendered through an emulated AY-3-8910." if bool(options.get("wav", true)) else "",
			"midi/     The arranged parts, one track each." if bool(options.get("midi", false)) else "",
			"",
			"Arrangement:",
			"\n".join(Array(ay.report).map(func(line: String) -> String: return "  " + line)),
		]).to_utf8_buffer()
		return true)
	return job


## Export for sound effects on the MSX and ZX Spectrum 128: the sounds as
## data for our Z80 player, and WAVs of how each sounds.
static func for_ay_sfx(sounds: Dictionary, kit_name: String, options: Dictionary) -> ExportJob:
	var job := ExportJob.new()
	var prefix := sanitize(kit_name)
	var converted: Array = []
	var ids := sounds.keys()
	ids.sort()
	for id in ids:
		converted.append(AySfx.from_sfx(sounds[id], sanitize(str(id))))
	if bool(options.get("console", true)):
		job._tasks.append(func() -> bool:
			for machine in AyWriter.MACHINES:
				job.files["msx/sfx_%s.bin" % machine] = AyWriter.sfx_bytes(converted, AyWriter.MACHINES[machine])
			job.files["msx/ay_player.asm"] = AyWriter.player_asm().to_utf8_buffer()
			job.files["msx/README.txt"] = AyWriter.sfx_readme(prefix, converted).to_utf8_buffer()
			return true)
	if bool(options.get("wav", true)):
		for ay_sfx in converted:
			job._tasks.append(func() -> bool:
				job.files["audio/%s.wav" % ay_sfx.name] = ChipAudio.encode_wav_mono(ay_sfx.render(job.rate), job.rate)
				return true)
	job._tasks.append(func() -> bool:
		var lines: Array[String] = [
			"Sound kit for the MSX and ZX Spectrum 128 (AY-3-8910): %s" % prefix,
			"Made with Chiptune Forge. You own these sounds and may use them for any purpose, including commercially.",
			"",
			"msx/    The sounds for Chiptune Forge's Z80 player (MIT).\n        See msx/README.txt to play them over your music." if bool(options.get("console", true)) else "",
			"audio/  One WAV per sound, 44.1 kHz, as the AY-3-8910 plays it.",
			"",
			"Sounds:",
		]
		for i in converted.size():
			lines.append("  %d  %s" % [i, (converted[i] as AySfx).name])
		job.files["README.txt"] = "\n".join(lines).to_utf8_buffer()
		return true)
	return job


## Export for a song arranged for the Commodore 64: a PSID file, data for
## our 6502 player with an example program, plus optional WAV (rendered
## through the emulated SID) and MIDI of the arranged parts.
## Options: prefix, wav, loops, midi, console.
static func for_sid_song(sid: SidSong, options: Dictionary) -> ExportJob:
	var job := ExportJob.new()
	var song := sid.source
	var prefix := sanitize(str(options.get("prefix", sid.title)))
	if bool(options.get("console", true)):
		job._tasks.append(func() -> bool:
			var data := SidWriter.song_bytes(sid)
			job.files["c64/%s.sid" % prefix] = SidWriter.psid_bytes(sid, data)
			job.files["c64/song.bin"] = data
			job.files["c64/sid_player.s"] = SidWriter.player_source().to_utf8_buffer()
			job.files["c64/sid_player.bin"] = SidWriter.player_binary()
			job.files["c64/sid_player.cfg"] = SidWriter.player_config().to_utf8_buffer()
			job.files["c64/main.s"] = SidWriter.example_source(sid.title).to_utf8_buffer()
			job.files["c64/main.cfg"] = SidWriter.example_config().to_utf8_buffer()
			job.files["c64/Makefile"] = SidWriter.makefile(prefix).to_utf8_buffer()
			job.files["c64/README.txt"] = SidWriter.song_readme(prefix, sid).to_utf8_buffer()
			return true)
	if bool(options.get("midi", false)):
		job._tasks.append(func() -> bool:
			job.files["midi/%s.mid" % prefix] = MidiWriter.encode(song)
			return true)
	if bool(options.get("wav", true)):
		job._r_nes = sid
		job._queue_render(song, "audio/%s.wav" % prefix, int(options.get("loops", 1)), [])
	job._tasks.append(func() -> bool:
		var meta: Dictionary = song.data.get("meta", {})
		job.files["README.txt"] = "\n".join([
			"%s, arranged for the Commodore 64 (SID)" % sid.title,
			"Made with Chiptune Forge. Seed %s, %s, %d BPM on the machine." % [meta.get("seed", ""), meta.get("key", ""), int(sid.get_bpm())],
			"",
			str(meta.get("license", "")),
			"",
			"c64/      The song as a PSID file (.sid), and for Chiptune Forge's 6502 player (MIT)\n          with an example program for ca65. See c64/README.txt." if bool(options.get("console", true)) else "",
			"audio/    WAV, 44.1 kHz, 16-bit, rendered through an emulated SID." if bool(options.get("wav", true)) else "",
			"midi/     The arranged parts, one track each." if bool(options.get("midi", false)) else "",
			"",
			"Arrangement:",
			"\n".join(Array(sid.report).map(func(line: String) -> String: return "  " + line)),
		]).to_utf8_buffer()
		return true)
	return job


## Export for sound effects on the Commodore 64: the sounds as data for our
## 6502 player, and WAVs of how each sounds.
static func for_sid_sfx(sounds: Dictionary, kit_name: String, options: Dictionary) -> ExportJob:
	var job := ExportJob.new()
	var prefix := sanitize(kit_name)
	var converted: Array = []
	var ids := sounds.keys()
	ids.sort()
	for id in ids:
		converted.append(SidSfx.from_sfx(sounds[id], sanitize(str(id))))
	if bool(options.get("console", true)):
		job._tasks.append(func() -> bool:
			job.files["c64/sfx.bin"] = SidWriter.sfx_bytes(converted)
			job.files["c64/sid_player.s"] = SidWriter.player_source().to_utf8_buffer()
			job.files["c64/sid_player.bin"] = SidWriter.player_binary()
			job.files["c64/sid_player.cfg"] = SidWriter.player_config().to_utf8_buffer()
			job.files["c64/README.txt"] = SidWriter.sfx_readme(prefix, converted).to_utf8_buffer()
			return true)
	if bool(options.get("wav", true)):
		for sid_sfx in converted:
			job._tasks.append(func() -> bool:
				job.files["audio/%s.wav" % sid_sfx.name] = ChipAudio.encode_wav_mono(sid_sfx.render(job.rate), job.rate)
				return true)
	job._tasks.append(func() -> bool:
		var lines: Array[String] = [
			"Sound kit for the Commodore 64 (SID): %s" % prefix,
			"Made with Chiptune Forge. You own these sounds and may use them for any purpose, including commercially.",
			"",
			"c64/    The sounds for Chiptune Forge's 6502 player (MIT).\n        See c64/README.txt to play them over your music." if bool(options.get("console", true)) else "",
			"audio/  One WAV per sound, 44.1 kHz, as the SID plays it.",
			"",
			"Sounds:",
		]
		for i in converted.size():
			lines.append("  %d  %s" % [i, (converted[i] as SidSfx).name])
		job.files["README.txt"] = "\n".join(lines).to_utf8_buffer()
		return true)
	return job


## Export for a song arranged for a PC sound card's FM chip: IMF (OPL2
## only), DRO and VGM files, plus optional WAV (rendered through the
## emulated chip) and MIDI of the arranged parts.
## Options: prefix, wav, loops, midi, console.
static func for_pc_song(arranged: Variant, options: Dictionary) -> ExportJob:
	if arranged is ModuleSong:
		return _for_module_song(arranged, options)
	if arranged is GusSong:
		return _for_gus_song(arranged, options)
	if arranged is SpeakerSong:
		return _for_speaker_song(arranged, options)
	if arranged is SmsSong:
		return _for_tandy_song(arranged, options)
	var opl: OplSong = arranged
	var job := ExportJob.new()
	var song := opl.source
	var prefix := sanitize(str(options.get("prefix", opl.title)))
	var card := PcCards.name_of(opl.card)
	if bool(options.get("console", true)):
		job._tasks.append(func() -> bool:
			var recorded := OplWriter.record(opl)
			if opl.chip == "opl2":
				job.files["pc/%s.wlf" % prefix] = OplWriter.imf_bytes(recorded, opl.title)
			job.files["pc/%s.dro" % prefix] = OplWriter.dro_bytes(recorded, opl.chip)
			job.files["pc/%s.vgm" % prefix] = OplWriter.vgm_bytes(recorded, opl.chip, opl.title, "IBM PC, " + card, "Made with Chiptune Forge")
			job.files["pc/README.txt"] = OplWriter.song_readme(prefix, opl).to_utf8_buffer()
			return true)
	if bool(options.get("midi", false)):
		job._tasks.append(func() -> bool:
			job.files["midi/%s.mid" % prefix] = MidiWriter.encode(song)
			return true)
	if bool(options.get("wav", true)):
		job._r_nes = opl
		job._queue_render(song, "audio/%s.wav" % prefix, int(options.get("loops", 1)), [])
	job._tasks.append(func() -> bool:
		var meta: Dictionary = song.data.get("meta", {})
		job.files["README.txt"] = "\n".join([
			"%s, arranged for the %s (%s)" % [opl.title, card, {"opl2": "OPL2", "dual_opl2": "two OPL2s", "opl3": "OPL3"}[opl.chip]],
			"Made with Chiptune Forge. Seed %s, %s, %d BPM on the card." % [meta.get("seed", ""), meta.get("key", ""), int(opl.get_bpm())],
			"",
			str(meta.get("license", "")),
			"",
			"pc/       The song as %s. See pc/README.txt." % ("IMF (.wlf), DRO and VGM files" if opl.chip == "opl2" else "DRO and VGM files") if bool(options.get("console", true)) else "",
			"audio/    WAV, 44.1 kHz, 16-bit, rendered through an emulated %s." % ("OPL3" if opl.chip == "opl3" else "OPL2") if bool(options.get("wav", true)) else "",
			"midi/     The arranged parts, one track each." if bool(options.get("midi", false)) else "",
			"",
			"Arrangement:",
			"\n".join(Array(opl.report).map(func(line: String) -> String: return "  " + line)),
		]).to_utf8_buffer()
		return true)
	return job


## The PC speaker: the song as C data and binary, the player
## (speaker.c) and an example program for Open Watcom or Turbo C.
static func _for_speaker_song(sp: SpeakerSong, options: Dictionary) -> ExportJob:
	var job := ExportJob.new()
	var song := sp.source
	var prefix := sanitize(str(options.get("prefix", sp.title)))
	var symbol := "song_" + PsgWriter.symbol(prefix)
	if bool(options.get("console", true)):
		job._tasks.append(func() -> bool:
			var rec := SpeakerWriter.record(sp)
			var slots: PackedInt32Array = rec["slots"]
			job.files["pc/%s.h" % symbol] = SpeakerWriter.c_header(symbol, slots, int(rec["loop_slot"]), "%s, for the PC speaker" % sp.title).to_utf8_buffer()
			job.files["pc/%s.bin" % symbol] = SpeakerWriter.bin_bytes(slots)
			job.files["pc/speaker.c"] = SpeakerWriter.player_source().to_utf8_buffer()
			job.files["pc/speaker.h"] = SpeakerWriter.player_header().to_utf8_buffer()
			job.files["pc/main.c"] = SpeakerWriter.example_source("%s.h" % symbol, symbol, []).to_utf8_buffer()
			job.files["pc/makefile"] = SpeakerWriter.makefile("play").to_utf8_buffer()
			job.files["pc/README.txt"] = SpeakerWriter.readme(prefix, symbol, slots.size(), false).to_utf8_buffer()
			return true)
	_pc_common(job, sp, song, prefix, options, "pc/       The song as C data (%s.h) and binary, the player (speaker.c) and an example. See pc/README.txt." % symbol, "the PC speaker")
	return job


## The Tandy 1000: the song as a VGM for the SN76496.
static func _for_tandy_song(sms: SmsSong, options: Dictionary) -> ExportJob:
	var job := ExportJob.new()
	var song := sms.source
	var prefix := sanitize(str(options.get("prefix", sms.title)))
	if bool(options.get("console", true)):
		job._tasks.append(func() -> bool:
			var rec := PsgWriter.record(sms)
			job.files["pc/%s.vgm" % prefix] = PsgWriter.vgm_bytes(rec, sms.noise_taps, sms.noise_width, OplWriter.gd3(sms.title, "IBM PC, Tandy 1000", "Made with Chiptune Forge"))
			job.files["pc/README.txt"] = "\n".join([
				"%s: music for the Tandy 1000's SN76496" % prefix,
				"",
				"%s.vgm  The song as a VGM file (SN76496 at 3.58 MHz, 60 frames a second)." % prefix,
				"         VGM players, Furnace and DefleMask open it. To play it in a DOS",
				"         program, write each byte after a 0x50 command to port 0xC0 and wait",
				"         1/60 s at each 0x62.",
			]).to_utf8_buffer()
			return true)
	_pc_common(job, sms, song, prefix, options, "pc/       The song as a VGM file. See pc/README.txt.", "the Tandy 1000's SN76496")
	return job


## The Gravis Ultrasound: the song as an Impulse Tracker module with 16-bit
## samples.
static func _for_gus_song(gus: GusSong, options: Dictionary) -> ExportJob:
	var job := ExportJob.new()
	var prefix := sanitize(str(options.get("prefix", gus.title)))
	if bool(options.get("console", true)):
		job._tasks.append(func() -> bool:
			job.files["pc/%s.it" % prefix] = ItWriter.module_bytes(gus, false)
			job.files["pc/README.txt"] = "\n".join([
				"%s: music for the Gravis Ultrasound" % prefix,
				"",
				"%s.it  An Impulse Tracker module with 16-bit samples. Impulse Tracker plays" % prefix,
				"        it on a GUS directly, as do the DOS sound systems games used (MIDAS,",
				"        the Galaxy player, USMP), and OpenMPT and Schism Tracker open it.",
				"",
				"Channels 1 to 7 play the music; sound effects can use any voice it leaves free.",
			]).to_utf8_buffer()
			return true)
	_pc_common(job, gus, gus.source, prefix, options, "pc/       The song as an Impulse Tracker module. See pc/README.txt.", "the Gravis Ultrasound")
	return job


## A MIDI sound module: the song as a MIDI file set up for it.
static func _for_module_song(mod: ModuleSong, options: Dictionary) -> ExportJob:
	var job := ExportJob.new()
	var prefix := sanitize(str(options.get("prefix", mod.title)))
	var name := PcCards.name_of(mod.card)
	if bool(options.get("console", true)):
		job._tasks.append(func() -> bool:
			job.files["pc/%s.mid" % prefix] = mod.midi_bytes()
			var lines: PackedStringArray = [
				"%s: music for the %s" % [prefix, name],
				"",
				"%s.mid  A type 1 MIDI file set up for the %s. Play it on the module (or" % [prefix, name],
				"         %s), or with any DOS MIDI driver." % ("Munt, the MT-32 emulator" if mod.card == "mt32" else "a GM synth with a Sound Canvas sound set"),
				"",
				"Parts:",
			]
			for c in mod.parts:
				var part: Dictionary = mod.parts[c]
				if part.has("program_name"):
					lines.append("  Channel %d: %s, program %d" % [int(part["midi"]) + 1, part["program_name"], int(part["program"]) + 1])
			lines.append("  Channel 10: drums")
			lines.append("")
			lines.append("The file starts with SysEx (%s), then a beat of silence while the module takes it." % ("display, reverb, partial reserve and MIDI channels" if mod.card == "mt32" else "GM System On and GS reset"))
			job.files["pc/README.txt"] = "\n".join(lines).to_utf8_buffer()
			return true)
	_pc_common(job, mod, mod.source, prefix, options, "pc/       The song as a MIDI file set up for the %s. See pc/README.txt." % name, "the " + name)
	return job


## WAV, MIDI and the top README for the speaker, Tandy and module exports.
static func _pc_common(job: ExportJob, arranged: Variant, song: ChipSong, prefix: String, options: Dictionary, pc_line: String, sound: String) -> void:
	if bool(options.get("midi", false)):
		job._tasks.append(func() -> bool:
			job.files["midi/%s.mid" % prefix] = MidiWriter.encode(song)
			return true)
	if bool(options.get("wav", true)):
		if arranged is ModuleSong:
			job._queue_render(arranged.preview, "audio/%s.wav" % prefix, int(options.get("loops", 1)), [])
		else:
			job._r_nes = arranged
			job._queue_render(song, "audio/%s.wav" % prefix, int(options.get("loops", 1)), [])
	job._tasks.append(func() -> bool:
		var meta: Dictionary = song.data.get("meta", {})
		job.files["README.txt"] = "\n".join([
			"%s, arranged for %s" % [arranged.title, sound],
			"Made with Chiptune Forge. Seed %s, %s, %d BPM on the card." % [meta.get("seed", ""), meta.get("key", ""), int(arranged.get_bpm())],
			"",
			str(meta.get("license", "")),
			"",
			pc_line if bool(options.get("console", true)) else "",
			("audio/    WAV, 44.1 kHz, 16-bit: an approximation of %s on the app's own synth." % sound if arranged is ModuleSong else "audio/    WAV, 44.1 kHz, 16-bit, rendered through an emulation of %s." % sound) if bool(options.get("wav", true)) else "",
			"midi/     The arranged parts, one track each." if bool(options.get("midi", false)) else "",
			"",
			"Arrangement:",
			"\n".join(Array(arranged.report).map(func(line: String) -> String: return "  " + line)),
		]).to_utf8_buffer()
		return true)


## Export for sound effects on a PC sound card: Creative Voice files (or
## 16-bit WAVs on the Sound Blaster 16) for the Sound Blasters' DAC, or FM
## sounds as DRO and IMF files for the AdLib, and WAVs of how each sounds.
static func for_pc_sfx(sounds: Dictionary, kit_name: String, options: Dictionary) -> ExportJob:
	var job := ExportJob.new()
	var prefix := sanitize(kit_name)
	var card := str(options.get("card", PcCards.DEFAULT))
	var converted: Array = []
	var ids := sounds.keys()
	ids.sort()
	for id in ids:
		converted.append(PcSfx.from_sfx(sounds[id], card, sanitize(str(id))))
	if bool(options.get("console", true)) and card == "speaker":
		job._tasks.append(func() -> bool:
			var symbols: Array = []
			for pc_sfx: PcSfx in converted:
				var symbol := "sfx_" + PsgWriter.symbol(pc_sfx.name)
				job.files["pc/%s.h" % symbol] = SpeakerWriter.c_header(symbol, pc_sfx.slots, -1, "%s, for the PC speaker" % pc_sfx.name).to_utf8_buffer()
				job.files["pc/%s.bin" % symbol] = SpeakerWriter.bin_bytes(pc_sfx.slots)
				symbols.append(symbol)
			job.files["pc/speaker.c"] = SpeakerWriter.player_source().to_utf8_buffer()
			job.files["pc/speaker.h"] = SpeakerWriter.player_header().to_utf8_buffer()
			job.files["pc/main.c"] = SpeakerWriter.example_source("", "", symbols).to_utf8_buffer()
			job.files["pc/makefile"] = SpeakerWriter.makefile("sounds").to_utf8_buffer()
			job.files["pc/README.txt"] = SpeakerWriter.readme(prefix, "", 0, true, symbols).to_utf8_buffer()
			return true)
	elif bool(options.get("console", true)):
		for pc_sfx: PcSfx in converted:
			job._tasks.append(func() -> bool:
				if card == "tandy":
					var rec := PsgWriter.record(pc_sfx.psg.to_song(), 1 << pc_sfx.psg.channel)
					job.files["pc/%s.vgm" % pc_sfx.name] = PsgWriter.vgm_bytes(rec, 0x0006, 16)
				elif pc_sfx.is_fm():
					var recorded := pc_sfx.recorded()
					job.files["pc/%s.dro" % pc_sfx.name] = OplWriter.dro_bytes(recorded, "opl2")
					job.files["pc/%s.wlf" % pc_sfx.name] = OplWriter.imf_bytes(recorded, pc_sfx.name)
				elif pc_sfx.bits == 16:
					job.files["pc/%s.wav" % pc_sfx.name] = pc_sfx.wav_bytes()
				else:
					job.files["pc/%s.voc" % pc_sfx.name] = pc_sfx.voc_bytes()
				return true)
		job._tasks.append(func() -> bool:
			if card == "tandy":
				job.files["pc/README.txt"] = "Sound effects for the Tandy 1000's SN76496, one VGM file each. Each plays on\nSquare 3 or the noise channel, which the music gives up while it sounds.\n".to_utf8_buffer()
			else:
				job.files["pc/README.txt"] = OplWriter.sfx_readme(prefix, card, converted).to_utf8_buffer()
			return true)
	if bool(options.get("wav", true)):
		for pc_sfx: PcSfx in converted:
			job._tasks.append(func() -> bool:
				job.files["audio/%s.wav" % pc_sfx.name] = ChipAudio.encode_wav_mono(pc_sfx.render(job.rate), job.rate)
				return true)
	job._tasks.append(func() -> bool:
		var lines: Array[String] = [
			"Sound kit for the %s: %s" % [PcCards.name_of(card), prefix],
			"Made with Chiptune Forge. You own these sounds and may use them for any purpose, including commercially.",
			"",
			"pc/     The sounds for the card. See pc/README.txt." if bool(options.get("console", true)) else "",
			"audio/  One WAV per sound, 44.1 kHz, as the card plays it.",
			"",
			"Sounds:",
		]
		for i in converted.size():
			lines.append("  %d  %s" % [i, (converted[i] as PcSfx).name])
		job.files["README.txt"] = "\n".join(lines).to_utf8_buffer()
		return true)
	return job


## Export for sound effects on the Game Boy: a GBDK-2020 project with the
## sounds as cf_sfx data, plus WAVs of how each one sounds on the console.
static func for_gameboy_sfx(sounds: Dictionary, kit_name: String, options: Dictionary) -> ExportJob:
	var job := ExportJob.new()
	var prefix := sanitize(kit_name)
	var converted: Array = []
	var ids := sounds.keys()
	ids.sort()
	for id in ids:
		converted.append(GbSfx.from_sfx(sounds[id], sanitize(str(id))))
	if bool(options.get("console", true)):
		job._tasks.append(func() -> bool:
			var project := GbCWriter.sfx_project(converted, prefix, kit_name)
			for path in project:
				job.files["gameboy/" + path] = project[path]
			return true)
	if bool(options.get("wav", true)):
		for gb_sfx in converted:
			job._tasks.append(func() -> bool:
				job.files["audio/%s.wav" % gb_sfx.name] = ChipAudio.encode_wav_mono(gb_sfx.render(job.rate), job.rate)
				return true)
	job._tasks.append(func() -> bool:
		var lines: Array[String] = [
			"Sound kit for the Game Boy: %s" % prefix,
			"Made with Chiptune Forge. You own these sounds and may use them for any purpose, including commercially.",
			"",
			"gameboy/  A GBDK-2020 project: the sounds, the cf_sfx player and an example ROM.\n          See gameboy/README.txt to build it and use the sounds in your game." if bool(options.get("console", true)) else "",
			"audio/    One WAV per sound, as the Game Boy plays it.",
			"",
			"Sounds:",
		]
		for gb_sfx in converted:
			var text := "  %s  (%s, %s, %d frames)" % [gb_sfx.name, GbCWriter.sfx_symbol(gb_sfx.name), "Pulse 2" if gb_sfx.channel == GbSfx.PULSE else "Noise", gb_sfx.frame_count()]
			if not gb_sfx.notes.is_empty():
				text += ": " + ", ".join(gb_sfx.notes)
			lines.append(text)
		job.files["README.txt"] = "\n".join(lines).to_utf8_buffer()
		return true)
	return job


## Export for sound effects. [param sounds] maps ids to [ChipSfx].
static func for_sfx(sounds: Dictionary, kit_name: String, options: Dictionary) -> ExportJob:
	var job := ExportJob.new()
	var prefix := sanitize(kit_name)
	if bool(options.get("godot", true)):
		job._tasks.append(func() -> bool:
			var kit := ChipSfxKit.new()
			kit.kit_name = kit_name
			kit.sounds = sounds
			job.files["godot/%s.chipkit" % prefix] = kit.to_json().to_utf8_buffer()
			for id in sounds:
				job.files["godot/sounds/%s.chipsfx" % sanitize(id)] = sounds[id].to_json().to_utf8_buffer()
			if bool(options.get("plugin", true)):
				job._add_plugin("godot/")
			return true)
	if bool(options.get("wav", true)):
		for id in sounds:
			var sfx: ChipSfx = sounds[id]
			job._tasks.append(func() -> bool:
				job.files["audio/%s.wav" % sanitize(id)] = ChipAudio.encode_wav_mono(sfx.render(job.rate), job.rate)
				return true)
	job._tasks.append(func() -> bool:
		job.files["README.txt"] = job._sfx_readme(sounds, prefix).to_utf8_buffer()
		return true)
	return job


## Lower-case, underscores, letters and digits only: safe for files and C.
static func sanitize(text: String) -> String:
	var out := ""
	for c in text.to_lower():
		out += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") else "_"
	while out.contains("__"):
		out = out.replace("__", "_")
	out = out.trim_prefix("_").trim_suffix("_")
	return out if out != "" else "export"


## Does work for up to [param budget_usec] microseconds.
func step(budget_usec := 12000) -> void:
	var start := Time.get_ticks_usec()
	while not done and Time.get_ticks_usec() - start < budget_usec:
		if _task_index >= _tasks.size():
			done = true
			progress = 1.0
			status = "Done"
			break
		if _tasks[_task_index].call():
			_task_index += 1
		progress = (_task_index + _r_fraction) / float(maxi(_tasks.size(), 1))


func build_zip() -> PackedByteArray:
	var path := "user://export_tmp.zip"
	var zip := ZIPPacker.new()
	if zip.open(path) != OK:
		return PackedByteArray()
	var names := files.keys()
	names.sort()
	for name in names:
		zip.start_file(name)
		zip.write_file(files[name])
		zip.close_file()
	zip.close()
	var bytes := FileAccess.get_file_as_bytes(path)
	DirAccess.remove_absolute(path)
	return bytes


## Takes the "rate" option. The READMEs say 44.1 kHz, so a 48 kHz export
## corrects them once they are written.
func _use_rate(options: Dictionary) -> void:
	var wanted := int(options.get("rate", MIX_RATE))
	rate = wanted if RATES.has(wanted) else MIX_RATE
	if rate == MIX_RATE:
		return
	_tasks.append(func() -> bool:
		for path in files:
			if path.get_file() == "README.txt":
				files[path] = files[path].get_string_from_utf8().replace("44.1 kHz", ("%.1f kHz" % (rate / 1000.0)).replace(".0 ", " ")).to_utf8_buffer()
		return true)


## OGG files are made from the rendered WAVs, so an OGG export renders
## them even when WAV is not asked for.
static func _with_ogg(options: Dictionary) -> Dictionary:
	if bool(options.get("ogg", false)) and not bool(options.get("wav", true)):
		return options.merged({"wav": true}, true)
	return options


## Takes the "ogg" option: once everything else is built, each WAV under
## audio/ gets an OGG Vorbis copy with its loop as LOOPSTART and LOOPLENGTH
## tags. Without "wav", the OGG replaces the WAV.
func _use_ogg(options: Dictionary, title: String, credit: String) -> void:
	if not bool(options.get("ogg", false)):
		return
	var keep_wav := bool(options.get("wav", true))
	var encoder: Array = [null, ""]
	_tasks.append(func() -> bool:
		if encoder[0] == null:
			var next := ""
			for path: String in files:
				if path.begins_with("audio/") and path.ends_with(".wav") and not files.has(path.get_basename() + ".ogg"):
					next = path
					break
			if next == "":
				_ogg_readmes(keep_wav)
				_r_fraction = 0.0
				return true
			var name := next.get_file().get_basename()
			encoder[0] = ChipVorbis.from_wav(files[next], PackedStringArray(["TITLE=%s" % (title if name == sanitize(title) else name), "COMMENT=%s" % credit, "ENCODER=Chiptune Forge"]))
			encoder[1] = next
			status = "Encoding %s.ogg" % name
			if encoder[0] == null:
				files[next.get_basename() + ".ogg"] = PackedByteArray()
				return false
		var vorbis: ChipVorbis = encoder[0]
		_r_fraction = vorbis.get_progress()
		if not vorbis.step(2):
			return false
		var wav_path: String = encoder[1]
		files[wav_path.get_basename() + ".ogg"] = vorbis.bytes
		if not keep_wav:
			files.erase(wav_path)
		encoder[0] = null
		return false)


func _ogg_readmes(keep_wav: bool) -> void:
	for path in files:
		if path.get_file() != "README.txt":
			continue
		var lines: PackedStringArray = files[path].get_string_from_utf8().split("\n")
		for i in lines.size():
			if lines[i].strip_edges().begins_with("audio/") and lines[i].contains("WAV"):
				if keep_wav:
					lines.insert(i + 1, "        OGG Vorbis copies sit beside the WAVs, with the loop as LOOPSTART and LOOPLENGTH tags.")
				else:
					lines[i] = lines[i].replace(", 16-bit", "").replace("WAV", "OGG Vorbis").replace("in the smpl chunk", "as LOOPSTART and LOOPLENGTH tags")
				break
		files[path] = "\n".join(lines).to_utf8_buffer()


func _queue_render(song: ChipSong, path: String, loops: int, muted: Array) -> void:
	_tasks.append(func() -> bool:
		if _r_path != path:
			_start_render(song, path, loops, muted)
		var chunk := _r_seq.render(mini(BLOCK, _r_total - _r_written))
		ChipAudio.write_pcm16_stereo(chunk, _r_bytes, _r_header + _r_written * 4)
		_r_written += chunk.size()
		_r_fraction = _r_written / float(maxi(_r_total, 1))
		if _r_written < _r_total and not chunk.is_empty():
			return false
		files[path] = _finish_render()
		return true)


func _start_render(song: ChipSong, path: String, loops: int, muted: Array) -> void:
	if _r_gb:
		_r_seq = GbSequencer.new(_r_gb, rate)
	elif _r_nes is OplSong:
		_r_seq = OplSequencer.new(_r_nes, rate)
	elif _r_nes is GusSong:
		_r_seq = GusSequencer.new(_r_nes, rate)
	elif _r_nes is GbaSong:
		_r_seq = GbaSequencer.new(_r_nes, rate)
	elif _r_nes is SnesSong:
		_r_seq = SnesSequencer.new(_r_nes, rate)
	elif _r_nes is PceSong:
		_r_seq = PceSequencer.new(_r_nes, rate)
	elif _r_nes is AySong:
		_r_seq = AySequencer.new(_r_nes, rate)
	elif _r_nes is SidSong:
		_r_seq = SidSequencer.new(_r_nes, rate)
	elif _r_nes is MdSong:
		_r_seq = MdSequencer.new(_r_nes, rate)
	elif _r_nes is SmsSong:
		_r_seq = SmsSequencer.new(_r_nes, rate)
	elif _r_nes is SpeakerSong:
		_r_seq = SpeakerSequencer.new(_r_nes, rate)
	elif _r_nes:
		_r_seq = NesSequencer.new(_r_nes, rate)
	else:
		_r_seq = ChipSongSequencer.new(song, rate)
	for c in muted:
		_r_seq.set_channel_muted(c, true)
	_r_total = _r_seq.get_loop_start_frame() + (_r_seq.get_loop_end_frame() - _r_seq.get_loop_start_frame()) * maxi(loops, 1)
	if not _r_seq.looping:
		_r_total = _r_seq.get_length_frames() + int(1.5 * rate)
	_r_seq.seek_step(0)
	_r_path = path
	_r_written = 0
	_r_fraction = 0.0
	_r_bytes = _wav_header(_r_total)
	_r_header = _r_bytes.size()
	_r_bytes.resize(_r_header + _r_total * 4)
	status = "Rendering %s" % path.get_file()


func _finish_render() -> PackedByteArray:
	var bytes := _r_bytes
	if _r_written < _r_total:
		# The sequencer ran out early: trim the data and fix the sizes.
		bytes.resize(_r_header + _r_written * 4)
		var header := _wav_header(_r_written)
		for i in header.size():
			bytes[i] = header[i]
	bytes.append_array(ChipAudio.wav_loop_chunk(rate, _loop_begin(), _loop_end()))
	_r_path = ""
	_r_seq = null
	_r_bytes = PackedByteArray()
	_r_fraction = 0.0
	return bytes


func _wav_header(frames: int) -> PackedByteArray:
	return ChipAudio.wav_header(frames * 4, 2, rate, _loop_begin(), _loop_end())


func _loop_begin() -> int:
	return _r_seq.get_loop_start_frame() if _r_seq.looping else -1


func _loop_end() -> int:
	return _r_seq.get_loop_end_frame() if _r_seq.looping else -1


func _add_plugin(base: String) -> void:
	_copy_dir("res://addons/chipforge", base + "addons/chipforge")


func _copy_dir(from: String, to: String) -> void:
	var dir := DirAccess.open(from)
	if dir == null:
		return
	for file in dir.get_files():
		if file.ends_with(".import") or file.ends_with(".uid"):
			continue
		var bytes := FileAccess.get_file_as_bytes(from.path_join(file))
		if not bytes.is_empty():
			files[to.path_join(file)] = bytes
	for sub in dir.get_directories():
		_copy_dir(from.path_join(sub), to.path_join(sub))


func _song_readme(song: ChipSong, prefix: String, options: Dictionary) -> String:
	var meta: Dictionary = song.data["meta"]
	return "\n".join([
		"%s" % song.get_title(),
		"Made with Chiptune Forge. Seed %s, %s, %d BPM." % [meta.get("seed", ""), meta.get("key", ""), int(song.get_bpm())],
		"",
		str(meta.get("license", "")),
		"",
		"godot/  The song for the Chiptune Forge Godot plugin (Godot 4.3 or later).",
		"        1. Copy godot/addons/chipforge into your project's addons folder.",
		"        2. Enable it in Project Settings > Plugins.",
		"        3. Copy godot/%s.chipsong into your project. It imports as a ChipSong." % prefix,
		"        4. Add a ChipMusicPlayer node, assign the song, and call play().",
		"        Adaptive music: $Music.set_state(\"combat\") or $Music.intensity = 0.72.",
		"audio/  WAV, 44.1 kHz, 16-bit. Looping songs carry loop points in the smpl chunk.",
		"midi/   One track per chip channel, drums on channel 10." if bool(options.get("midi", false)) else "",
	])


func _gameboy_readme(gb: GbSong, prefix: String, options: Dictionary) -> String:
	var meta: Dictionary = gb.source.data.get("meta", {})
	return "\n".join([
		"%s, arranged for the Game Boy" % gb.title,
		"Made with Chiptune Forge. Seed %s, %s, %d BPM on the console." % [meta.get("seed", ""), meta.get("key", ""), int(gb.get_bpm())],
		"",
		str(meta.get("license", "")),
		"",
		"gameboy/  A GBDK-2020 project: the song as hUGEDriver data, an example main.c and a Makefile\n          that builds a ROM. See gameboy/README.txt." if bool(options.get("console", true)) else "",
		"audio/    WAV, 44.1 kHz, 16-bit, rendered through an emulated Game Boy sound chip." if bool(options.get("wav", true)) else "",
		"midi/     The four arranged parts, one track each." if bool(options.get("midi", false)) else "",
		"",
		"Arrangement:",
		"\n".join(Array(gb.report).map(func(line: String) -> String: return "  " + line)),
	])


func _nes_readme(nes: NesSong, prefix: String, options: Dictionary) -> String:
	var meta: Dictionary = nes.source.data.get("meta", {})
	return "\n".join([
		"%s, arranged for the NES" % nes.title,
		"Made with Chiptune Forge. Seed %s, %s, %d BPM on the console." % [meta.get("seed", ""), meta.get("key", ""), int(nes.get_bpm())],
		"",
		str(meta.get("license", "")),
		"",
		("nes/     %s.s, the song for FamiStudio's sound engine (ca65), with the engine and an\n         example that builds a ROM with cc65. See nes/README.txt.\n         nes/famistudio/%s.txt is the FamiStudio project, to edit it or export NSF." % [prefix, prefix]) if bool(options.get("console", true)) else "",
		"audio/   WAV, 44.1 kHz, 16-bit, rendered through an emulated NES sound chip." if bool(options.get("wav", true)) else "",
		"midi/    The four arranged parts, one track each." if bool(options.get("midi", false)) else "",
		"",
		"Arrangement:",
		"\n".join(Array(nes.report).map(func(line: String) -> String: return "  " + line)),
	])


func _sms_readme(sms: SmsSong, prefix: String, options: Dictionary) -> String:
	var meta: Dictionary = sms.source.data.get("meta", {})
	return "\n".join([
		"%s, arranged for the Master System and Game Gear" % sms.title,
		"Made with Chiptune Forge. Seed %s, %s, %d BPM on the console." % [meta.get("seed", ""), meta.get("key", ""), int(sms.get_bpm())],
		"",
		str(meta.get("license", "")),
		"",
		("sms/     %s.psg, PSGlib data, also as a C array for devkitSMS, and %s.vgm.\n         See sms/README.txt to play it in your game." % [prefix, prefix]) if bool(options.get("console", true)) else "",
		"audio/   WAV, 44.1 kHz, 16-bit, rendered through an emulated SN76489." if bool(options.get("wav", true)) else "",
		"midi/    The four arranged parts, one track each." if bool(options.get("midi", false)) else "",
		"",
		"Arrangement:",
		"\n".join(Array(sms.report).map(func(line: String) -> String: return "  " + line)),
	])


func _md_readme(md: MdSong, prefix: String, options: Dictionary) -> String:
	var meta: Dictionary = md.source.data.get("meta", {})
	return "\n".join([
		"%s, arranged for the Mega Drive / Genesis" % md.title,
		"Made with Chiptune Forge. Seed %s, %s, %d BPM on the console." % [meta.get("seed", ""), meta.get("key", ""), int(md.get_bpm())],
		"",
		str(meta.get("license", "")),
		"",
		("genesis/  %s.vgm (YM2612 and SN76489), with resources.res and main.c for SGDK.\n          See genesis/README.txt to play it in your game." % prefix) if bool(options.get("console", true)) else "",
		"audio/    WAV, 44.1 kHz, 16-bit, rendered through an emulated YM2612 and SN76489." if bool(options.get("wav", true)) else "",
		"midi/     The ten arranged parts, one track each." if bool(options.get("midi", false)) else "",
		"",
		"Arrangement:",
		"\n".join(Array(md.report).map(func(line: String) -> String: return "  " + line)),
	])


func _snes_readme(snes: SnesSong, prefix: String, options: Dictionary) -> String:
	var meta: Dictionary = snes.source.data.get("meta", {})
	return "\n".join([
		"%s, arranged for the SNES" % snes.title,
		"Made with Chiptune Forge. Seed %s, %s, %d BPM on the console." % [meta.get("seed", ""), meta.get("key", ""), int(snes.get_bpm())],
		"",
		str(meta.get("license", "")),
		"",
		("snes/     res/%s.it, an Impulse Tracker module for PVSnesLib's SNESMod driver,\n          with a Makefile and main.c that build a ROM playing it. See snes/README.txt." % prefix) if bool(options.get("console", true)) else "",
		"audio/    WAV, 44.1 kHz, 16-bit, rendered through an emulated S-DSP." if bool(options.get("wav", true)) else "",
		"midi/     The arranged parts, one track each." if bool(options.get("midi", false)) else "",
		"",
		"Arrangement:",
		"\n".join(Array(snes.report).map(func(line: String) -> String: return "  " + line)),
	])


func _sfx_readme(sounds: Dictionary, prefix: String) -> String:
	var ids: Array = []
	for id in sounds:
		ids.append("  %s  (%s)" % [id, SfxGenerator.c_id(id)])
	return "\n".join([
		"Sound kit: %s" % prefix,
		"Made with Chiptune Forge. You own these sounds and may use them for any purpose, including commercially.",
		"",
		"godot/  The kit for the Chiptune Forge Godot plugin. Copy addons/chipforge into your project,",
		"        enable the plugin, add a ChipSfxPlayer node, assign %s.chipkit and call $Sfx.play(\"id\")." % prefix,
		"audio/  One WAV per sound, 44.1 kHz, 16-bit mono.",
		"",
		"Sounds:",
		"\n".join(ids),
	])
