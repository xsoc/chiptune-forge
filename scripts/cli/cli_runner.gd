class_name CliRunner
extends RefCounted
## The headless command line: generate songs and sound effects, export
## projects again, run batch manifests, validate files and list what the
## app knows, with the same engine and seeds as the app. See docs/cli.md.
##
##   godot --headless --path . -- generate --vibe happy --style platformer --seed 1 --out build
##
## [method run] returns the exit code: 0 success, 1 bad arguments, 2 chip
## limits exceeded or changes made (only with --strict), 3 export or file
## error, 4 schema validation failed.

const OK_CODE := 0
const BAD_ARGS := 1
const LIMITS := 2
const FILE_ERROR := 3
const SCHEMA := 4

const COMMANDS: PackedStringArray = ["generate", "sfx", "export", "batch", "validate", "list", "version", "help"]
## Output formats. "console" is the target's source and data (for a console
## target), "project" the .cforge file.
const FORMATS := {
	"json": "Chiptune Forge files for Godot (.chipsong, .chipsfx, .chipkit)",
	"plugin": "the Godot plugin, beside the json files",
	"wav": "WAV audio, with loop points for songs",
	"stems": "one WAV per layer (songs, modern target)",
	"midi": "a MIDI file of the song",
	"console": "the console target's source, data and example project",
	"project": "a .cforge project, to export again later",
}
const DEFAULT_FORMATS: PackedStringArray = ["json", "plugin", "wav", "console", "project"]
## Flags that take no value.
const SWITCHES: PackedStringArray = ["json", "strict", "stems", "layers", "loop", "no-loop", "intro", "no-intro", "outro", "no-outro", "help", "quiet"]
const LIST_KINDS: PackedStringArray = ["vibes", "styles", "targets", "presets", "formats", "packs", "modes", "keys", "structures", "engines"]
const KEYS: PackedStringArray = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

## Everything printed, for tests.
var output := PackedStringArray()
var catalog: Catalog
## Folder that relative paths start from (a batch manifest's folder).
var base_dir := ""
## Print nothing, only collect (batch jobs).
var silent := false

var _json := false
var _report := {}
var _error := ""


func _init(use_catalog: Catalog = null) -> void:
	catalog = use_catalog if use_catalog else Catalog.get_default()
	base_dir = start_dir()


## The folder the command was started in. Godot's --path moves into the
## project, so relative paths start from the shell's folder ($PWD), or
## CHIPTUNE_FORGE_CWD, which the Docker image's entry point sets.
static func start_dir() -> String:
	for name in ["CHIPTUNE_FORGE_CWD", "PWD"]:
		var dir := OS.get_environment(name)
		if dir != "" and DirAccess.dir_exists_absolute(dir):
			return dir
	return ""


## True when the arguments ask for the command line rather than the app.
static func wants_cli(args: PackedStringArray) -> bool:
	return not args.is_empty() and (COMMANDS.has(args[0]) or args[0] in ["--help", "-h", "--version"])


func run(args: PackedStringArray) -> int:
	output.clear()
	_report = {}
	if args.is_empty() or args[0] in ["help", "--help", "-h"]:
		_say(_usage())
		return OK_CODE
	if args[0] == "--version":
		args = PackedStringArray(["version"])
	var command := args[0]
	var parsed := _parse(args.slice(1))
	if parsed.has("error"):
		return _fail(BAD_ARGS, parsed["error"], command)
	var flags: Dictionary = parsed["flags"]
	var positional: PackedStringArray = parsed["positional"]
	_json = flags.has("json")
	var code := _dispatch(command, flags, positional)
	_report["command"] = command
	_report["ok"] = code == OK_CODE
	_report["exit_code"] = code
	if _json:
		_say(JSON.stringify(_report, "  ", false))
	if flags.has("report"):
		# Godot prints its own banner on stdout first, so a file is the
		# cleanest way for scripts to get the report.
		var path := _path(str(flags["report"]))
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			_fail(FILE_ERROR, "cannot write %s" % path, command)
			return FILE_ERROR
		file.store_string(JSON.stringify(_report, "  ", false) + "\n")
	return code


func _dispatch(command: String, flags: Dictionary, positional: PackedStringArray) -> int:
	for pack_path in flags.get("pack", []):
		var error := _load_pack(_path(pack_path))
		if error != "":
			return _fail(FILE_ERROR if error.begins_with("cannot read") else SCHEMA, error, command)
	var code := OK_CODE
	match command:
		"generate":
			code = _generate(flags)
		"sfx":
			code = _sfx(flags)
		"export":
			code = _export(flags, positional)
		"batch":
			code = _batch(flags, positional)
		"validate":
			code = _validate(flags, positional)
		"list":
			code = _list(flags, positional)
		"version":
			code = _version()
		_:
			return _fail(BAD_ARGS, "unknown command \"%s\". Commands: %s" % [command, ", ".join(COMMANDS)], command)
	return code


# Arguments -------------------------------------------------------------------

## Flags into a dictionary: values as strings, repeated flags (vibe, preset,
## pack) as lists, switches as true.
func _parse(args: PackedStringArray) -> Dictionary:
	var flags := {}
	var positional := PackedStringArray()
	var i := 0
	while i < args.size():
		var arg := args[i]
		i += 1
		if not arg.begins_with("--"):
			positional.append(arg)
			continue
		var name := arg.substr(2)
		var value := ""
		var has_value := false
		if name.contains("="):
			value = name.get_slice("=", 1)
			name = name.get_slice("=", 0)
			has_value = true
		if SWITCHES.has(name):
			if has_value:
				return {"error": "--%s takes no value" % name}
			flags[name] = true
			continue
		if not has_value:
			if i >= args.size():
				return {"error": "--%s needs a value" % name}
			value = args[i]
			i += 1
		if name in ["vibe", "preset", "pack", "layer-engine"]:
			if not flags.has(name):
				flags[name] = []
			flags[name].append(value)
		else:
			flags[name] = value
	return {"flags": flags, "positional": positional}


func _path(path: String) -> String:
	if path.is_absolute_path() or path.begins_with("res://") or path.begins_with("user://") or base_dir == "":
		return path
	return base_dir.path_join(path)


func _formats(flags: Dictionary) -> Variant:
	if flags.has("rate") and not ExportJob.RATES.has(int(flags["rate"])):
		return "unknown sample rate \"%s\". Rates: 44100, 48000" % flags["rate"]
	var list := DEFAULT_FORMATS
	if flags.has("format"):
		list = PackedStringArray()
		for f in str(flags["format"]).split(",", false):
			f = f.strip_edges().to_lower()
			if f in ["c", "asm", "source"]:
				f = "console"
			if f == "all":
				list = PackedStringArray(FORMATS.keys())
				break
			if not FORMATS.has(f):
				return "unknown format \"%s\". Formats: %s" % [f, ", ".join(FORMATS.keys())]
			list.append(f)
	if flags.has("stems") and not list.has("stems"):
		list.append("stems")
	return list


func _options(formats: PackedStringArray, prefix: String, flags: Dictionary) -> Dictionary:
	return {
		"card": str(flags.get("card", PcCards.DEFAULT)).to_lower(),
		"prefix": prefix,
		"godot": formats.has("json") or formats.has("plugin"),
		"plugin": formats.has("plugin"),
		"wav": formats.has("wav") or formats.has("stems"),
		"loops": int(flags.get("loops", 1)),
		"rate": int(flags.get("rate", ExportJob.MIX_RATE)),
		"stems": formats.has("stems"),
		"midi": formats.has("midi"),
		"console": formats.has("console"),
	}


## The target id from --target (or [param fallback]), or "" with the
## reason in [member _error].
func _target(flags: Dictionary, fallback := "modern") -> String:
	var target := str(flags.get("target", fallback)).to_lower()
	match target:
		"gb":
			target = "gameboy"
		"genesis", "md", "megadrive", "mega_drive":
			target = "genesis"
		"zx", "spectrum":
			target = "msx"
		"gamegear", "gg", "mastersystem":
			target = "sms"
		"pcengine", "turbografx":
			target = "pce"
	if not ExportJob.TARGETS.has(target):
		_error = "unknown target \"%s\". Targets: %s" % [target, ", ".join(ExportJob.TARGETS)]
		return ""
	if flags.has("card") and not PcCards.is_card(str(flags["card"]).to_lower()):
		_error = "unknown sound card \"%s\". Cards: %s" % [flags["card"], ", ".join(PcCards.CARDS)]
		return ""
	var chip: ChipProfile = catalog.chips.get(target)
	if chip and not chip.available:
		_error = "the %s target is not available yet" % chip.display_name
		return ""
	return target


func _seed(flags: Dictionary) -> String:
	if flags.has("seed"):
		return str(flags["seed"])
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return str(rng.randi_range(1, 999999))


# Commands --------------------------------------------------------------------

func _generate(flags: Dictionary) -> int:
	var settings := SongSettings.new()
	if flags.has("settings"):
		var text := FileAccess.get_file_as_string(_path(flags["settings"]))
		if text == "":
			return _fail(FILE_ERROR, "cannot read %s" % flags["settings"], "generate")
		var parsed: Variant = JSON.parse_string(text)
		if not parsed is Dictionary:
			return _fail(SCHEMA, "%s is not a JSON object" % flags["settings"], "generate")
		var dict: Dictionary = parsed
		if dict.get("format") == ProjectFile.FORMAT:
			dict = dict.get("settings", {})
		settings = SongSettings.from_dict(dict)
	var error := _apply_song_flags(settings, flags)
	if error != "":
		return _fail(BAD_ARGS, error, "generate")
	var target := _target(flags, settings.target)
	if target == "":
		return _fail(BAD_ARGS, _error, "generate")
	settings.target = target
	var formats: Variant = _formats(flags)
	if formats is String:
		return _fail(BAD_ARGS, formats, "generate")
	var song := SongGenerator.generate(settings, catalog)
	return _export_song(song, settings, target, formats, flags, {})


func _apply_song_flags(s: SongSettings, flags: Dictionary) -> String:
	if flags.has("vibe"):
		var list: Array = flags["vibe"]
		if list.size() > 3:
			return "at most three vibes"
		s.vibes.clear()
		s.vibe_strengths.clear()
		for entry in list:
			var id := str(entry).get_slice(":", 0)
			if catalog.get_vibe(id) == null:
				return "unknown vibe \"%s\" (see: list vibes)" % id
			s.vibes.append(id)
			var strength := 100.0
			if str(entry).contains(":"):
				var text := str(entry).get_slice(":", 1)
				if not text.is_valid_float():
					return "vibe strength should be a number: %s" % entry
				strength = clampf(text.to_float(), 1.0, 100.0)
			s.vibe_strengths.append(strength)
	elif not flags.has("settings"):
		pass
	for id in s.vibes:
		if catalog.get_vibe(id) == null:
			return "unknown vibe \"%s\" (see: list vibes)" % id
	if flags.has("style"):
		if catalog.get_style(flags["style"]) == null:
			return "unknown style \"%s\" (see: list styles)" % flags["style"]
		s.style = flags["style"]
	elif catalog.get_style(s.style) == null:
		return "unknown style \"%s\" (see: list styles)" % s.style
	for pair in [["intensity", "intensity"], ["complexity", "complexity"]]:
		if flags.has(pair[0]):
			if not str(flags[pair[0]]).is_valid_float():
				return "--%s should be a number from 0 to 100" % pair[0]
			s.set(pair[1], clampf(float(flags[pair[0]]), 0.0, 100.0))
	if flags.has("tempo"):
		var tempo := str(flags["tempo"])
		if tempo == "auto":
			s.tempo = 0
		elif tempo.is_valid_int() and int(tempo) >= 40 and int(tempo) <= 240:
			s.tempo = int(tempo)
		else:
			return "--tempo should be auto or 40 to 240 BPM"
	if flags.has("key"):
		var key := str(flags["key"])
		if key == "auto":
			s.key = -1
		else:
			var index := KEYS.find(key.to_upper().replace("B#", "C").replace("DB", "C#").replace("EB", "D#").replace("GB", "F#").replace("AB", "G#").replace("BB", "A#"))
			if index < 0:
				return "--key should be auto or a note name such as C, F# or Bb"
			s.key = index
	if flags.has("mode"):
		var mode := str(flags["mode"]).to_lower()
		if mode == "auto":
			s.mode = ""
		elif MusicTheory.SCALES.has(mode):
			s.mode = mode
		else:
			return "unknown mode \"%s\" (see: list modes)" % mode
	if flags.has("length"):
		var length := str(flags["length"])
		var seconds := -1.0
		if length.contains(":"):
			seconds = length.get_slice(":", 0).to_float() * 60.0 + length.get_slice(":", 1).to_float()
		elif length.is_valid_float():
			seconds = length.to_float()
		if seconds < 5.0 or seconds > 600.0:
			return "--length should be 5 to 600 seconds, or m:ss"
		s.length_seconds = seconds
	if flags.has("structure"):
		var form := str(flags["structure"]).to_lower()
		if not SongSettings.FORMS.has(form):
			return "unknown structure \"%s\" (see: list structures)" % form
		s.form = form
	if flags.has("energy"):
		if not SongSettings.ENERGY_CURVES.has(flags["energy"]):
			return "--energy should be one of %s" % ", ".join(SongSettings.ENERGY_CURVES)
		s.energy_curve = flags["energy"]
	if flags.has("engine"):
		var engine := str(flags["engine"]).to_lower()
		if not SynthEngines.CHOICES.has(engine):
			return "--engine should be one of %s" % ", ".join(SynthEngines.CHOICES)
		s.engine = engine
	if flags.has("layer-engine"):
		for entry in flags["layer-engine"]:
			var layer := str(entry).get_slice(":", 0).capitalize()
			var engine := str(entry).get_slice(":", 1).to_lower()
			if not SongSettings.LAYERS.has(layer):
				return "--layer-engine layer should be one of %s" % ", ".join(SongSettings.LAYERS)
			if not SynthEngines.CHOICES.has(engine):
				return "--layer-engine engine should be one of %s" % ", ".join(SynthEngines.CHOICES)
			s.layer_engines[layer] = engine
	for name in ["loop", "intro", "outro"]:
		if flags.has(name):
			s.set(name, true)
		if flags.has("no-" + name):
			s.set(name, false)
	s.seed_text = _seed(flags) if (flags.has("seed") or not flags.has("settings")) else s.seed_text
	return ""


func _export_song(song: ChipSong, settings: SongSettings, target: String, formats: PackedStringArray, flags: Dictionary, gameboy: Dictionary) -> int:
	var prefix := str(flags.get("name", song.get_title()))
	var options := _options(formats, prefix, flags)
	if target == "pc":
		var card := str(flags.get("card", gameboy.get("card", PcCards.DEFAULT))).to_lower()
		gameboy = {"card": card}
		options["card"] = card
	if formats.has("project"):
		options["project"] = ProjectFile.for_song(song, settings, target, gameboy)
	options["gameboy"] = gameboy
	var arranged: Variant = ExportJob.arrange(target, song, gameboy)
	var report := TargetReport.lines(target, true, song, arranged, {}, str(options["card"]))
	var job := ExportJob.for_target_song(target, song, options, arranged)
	job.run()
	var out := _path(str(flags.get("out", ".")))
	var written := job.write_to(out)
	_report["title"] = song.get_title()
	_report["seed"] = settings.seed_text
	_report["settings"] = settings.to_dict()
	_report["target"] = target
	_report["length_seconds"] = snappedf(song.get_length_seconds(), 0.01)
	_report["chip_report"] = _report_dict(report)
	if not written.is_empty() and written[0].begins_with("error: "):
		return _fail(FILE_ERROR, written[0].substr(7), "generate")
	_report["files"] = Array(written)
	_say_human("%s, seed %s, %d:%02d, for %s." % [song.get_title(), settings.seed_text, int(song.get_length_seconds()) / 60, int(song.get_length_seconds()) % 60, target])
	_say_report(report)
	_say_human("Wrote %d files to %s." % [written.size(), out])
	return _strict_code(flags, report)


func _sfx(flags: Dictionary) -> int:
	var presets: Array = flags.get("preset", [])
	if presets.is_empty():
		return _fail(BAD_ARGS, "pick at least one --preset (see: list presets)", "sfx")
	var target := _target(flags)
	if target == "":
		return _fail(BAD_ARGS, _error, "sfx")
	var formats: Variant = _formats(flags)
	if formats is String:
		return _fail(BAD_ARGS, formats, "sfx")
	var variants := int(flags.get("variants", 1))
	if variants < 1 or variants > 50:
		return _fail(BAD_ARGS, "--variants should be 1 to 50", "sfx")
	var seed_text := _seed(flags)
	var base_seed := int(seed_text) if seed_text.is_valid_int() else Pcg32.seed_from_text(seed_text)
	var sounds := {}
	var seeds := {}
	for id in presets:
		var preset := catalog.get_sfx_preset(id)
		if preset == null:
			return _fail(BAD_ARGS, "unknown preset \"%s\" (see: list presets)" % id, "sfx")
		for v in variants:
			var sound_id := ExportJob.sanitize(id if variants == 1 else "%s_%d" % [id, v + 1])
			var sfx := SfxGenerator.make_sfx(preset, base_seed + v)
			sfx.data["meta"]["name"] = sound_id
			sounds[sound_id] = sfx
			seeds[sound_id] = base_seed + v
	var kit_name := str(flags.get("name", "sounds"))
	_report["seed"] = seed_text
	_report["sounds"] = seeds
	return _export_kit(kit_name, sounds, target, formats, flags)


func _export_kit(kit_name: String, sounds: Dictionary, target: String, formats: PackedStringArray, flags: Dictionary) -> int:
	var options := _options(formats, kit_name, flags)
	if formats.has("project"):
		options["project"] = ProjectFile.for_kit(kit_name, sounds, target, options["card"] if target == "pc" else "")
	var report := TargetReport.lines(target, false, null, null, sounds, str(options["card"]))
	var job := ExportJob.for_target_sfx(target, sounds, kit_name, options)
	job.run()
	var out := _path(str(flags.get("out", ".")))
	var written := job.write_to(out)
	_report["target"] = target
	_report["chip_report"] = _report_dict(report)
	if not written.is_empty() and written[0].begins_with("error: "):
		return _fail(FILE_ERROR, written[0].substr(7), "sfx")
	_report["files"] = Array(written)
	_say_human("%s: %d sounds for %s." % [kit_name, sounds.size(), target])
	_say_report(report)
	_say_human("Wrote %d files to %s." % [written.size(), out])
	return _strict_code(flags, report)


func _export(flags: Dictionary, positional: PackedStringArray) -> int:
	if positional.size() != 1:
		return _fail(BAD_ARGS, "export takes one file: a .cforge project, .chipsong, .chipsfx or .chipkit", "export")
	var path := _path(positional[0])
	if not FileAccess.file_exists(path):
		return _fail(FILE_ERROR, "cannot read %s" % positional[0], "export")
	var project := ProjectFile.parse(FileAccess.get_file_as_string(path))
	if project.has("error"):
		return _fail(SCHEMA, "%s: %s" % [positional[0], project["error"]], "export")
	var target := _target(flags, project["target"])
	if target == "":
		return _fail(BAD_ARGS, _error, "export")
	var formats: Variant = _formats(flags)
	if formats is String:
		return _fail(BAD_ARGS, formats, "export")
	if not flags.has("name"):
		flags["name"] = path.get_file().get_slice(".", 0)
	if project["kind"] == "song":
		var song: ChipSong = project["song"]
		return _export_song(song, project["settings"], target, formats, flags, project.get("gameboy", {}))
	if project.get("card", "") != "" and not flags.has("card"):
		flags["card"] = project["card"]
	return _export_kit(str(flags["name"]), project["sounds"], target, formats, flags)


## A manifest is {"jobs": [...]} or a list of jobs. Each job has a
## "command" (generate, sfx or export; generate when left out) and the
## command's flags as keys without the dashes ("vibe": ["happy:70"],
## "seed": 3, "out": "music"). Paths are relative to the manifest.
func _batch(flags: Dictionary, positional: PackedStringArray) -> int:
	if positional.size() != 1:
		return _fail(BAD_ARGS, "batch takes one manifest file", "batch")
	var path := _path(positional[0])
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		return _fail(FILE_ERROR, "cannot read %s" % positional[0], "batch")
	var parsed: Variant = JSON.parse_string(text)
	var jobs: Variant = parsed.get("jobs") if parsed is Dictionary else parsed
	if not jobs is Array:
		return _fail(SCHEMA, "the manifest should be a list of jobs, or {\"jobs\": [...]}", "batch")
	var results: Array = []
	var worst := OK_CODE
	for i in (jobs as Array).size():
		var job: Variant = jobs[i]
		if not job is Dictionary:
			return _fail(SCHEMA, "job %d is not a table" % (i + 1), "batch")
		var args := PackedStringArray([str(job.get("command", "generate"))])
		if not args[0] in ["generate", "sfx", "export"]:
			return _fail(SCHEMA, "job %d: the command should be generate, sfx or export" % (i + 1), "batch")
		for key in job:
			if key == "command":
				continue
			if key == "file":
				args.append(str(job[key]))
				continue
			var value: Variant = job[key]
			if value is bool:
				if value:
					args.append("--" + key)
			elif value is Array:
				for v in value:
					args.append("--" + key)
					args.append(str(v))
			else:
				args.append("--" + key)
				args.append(str(int(value)) if value is float and value == floorf(value) else str(value))
		if flags.has("strict"):
			args.append("--strict")
		var child := CliRunner.new(catalog)
		child.base_dir = path.get_base_dir()
		child.silent = true
		var code := child.run(args)
		worst = maxi(worst, code)
		var entry := child._report.duplicate()
		entry["job"] = i + 1
		entry["exit_code"] = code
		entry["command"] = args[0]
		if child.output.size() > 0 and not child._json:
			entry["log"] = Array(child.output)
		results.append(entry)
		_say_human("Job %d (%s): %s" % [i + 1, args[0], "done" if code == OK_CODE else "exit code %d: %s" % [code, entry.get("error", "")]])
	_report["jobs"] = results
	_say_human("%d jobs, %d failed." % [results.size(), results.filter(func(r: Dictionary) -> bool: return int(r["exit_code"]) != OK_CODE).size()])
	return worst


func _validate(flags: Dictionary, positional: PackedStringArray) -> int:
	if positional.size() != 1:
		return _fail(BAD_ARGS, "validate takes one file", "validate")
	var path := _path(positional[0])
	if not FileAccess.file_exists(path):
		return _fail(FILE_ERROR, "cannot read %s" % positional[0], "validate")
	var text := FileAccess.get_file_as_string(path)
	if path.ends_with("." + ChipPack.EXTENSION):
		var parsed := ChipPack.parse(text, catalog)
		if parsed.has("error"):
			return _fail(SCHEMA, parsed["error"], "validate")
		var pack: ChipPack = parsed["pack"]
		_report["pack"] = {"name": pack.name, "summary": pack.summary()}
		_say_human("%s is a valid pack: %s." % [positional[0], pack.summary()])
		return OK_CODE
	var project := ProjectFile.parse(text)
	if project.has("error"):
		return _fail(SCHEMA, "%s: %s" % [positional[0], project["error"]], "validate")
	var target := _target(flags, project["target"])
	if target == "":
		return _fail(BAD_ARGS, _error, "validate")
	var report: Array[String]
	if project["kind"] == "song":
		var song: ChipSong = project["song"]
		var gameboy: Dictionary = project.get("gameboy", {})
		if flags.has("card"):
			gameboy = gameboy.merged({"card": str(flags["card"]).to_lower()}, true)
		report = TargetReport.lines(target, true, song, ExportJob.arrange(target, song, gameboy), {}, str(gameboy.get("card", PcCards.DEFAULT)))
		_report["title"] = song.get_title()
	else:
		var kit_card := str(flags.get("card", project.get("card", ""))).to_lower()
		report = TargetReport.lines(target, false, null, null, project["sounds"], kit_card if kit_card != "" else PcCards.DEFAULT)
	_report["target"] = target
	_report["chip_report"] = _report_dict(report)
	_say_human("%s is valid. For %s:" % [positional[0], target])
	_say_report(report)
	return _strict_code(flags, report)


func _list(_flags: Dictionary, positional: PackedStringArray) -> int:
	if positional.size() != 1 or not LIST_KINDS.has(positional[0]):
		return _fail(BAD_ARGS, "list what? One of: %s" % ", ".join(LIST_KINDS), "list")
	var items: Array = []
	match positional[0]:
		"vibes", "styles", "presets":
			var dict: Dictionary = catalog.sfx_presets if positional[0] == "presets" else catalog.get(positional[0])
			var groups: PackedStringArray = {"vibes": Catalog.VIBE_GROUPS, "styles": Catalog.STYLE_GROUPS, "presets": Catalog.SFX_GROUPS}[positional[0]]
			for group in groups:
				for res in catalog.in_group(dict, group):
					var item := {"id": res.id, "name": res.display_name, "group": group, "description": res.description}
					if res.has_meta("pack"):
						item["pack"] = res.get_meta("pack")
					items.append(item)
		"targets":
			for id in ExportJob.TARGETS:
				var chip: ChipProfile = catalog.chips.get(id)
				if chip:
					items.append({"id": id, "name": chip.display_name, "chip": chip.chip_name, "available": chip.available, "description": chip.description})
		"formats":
			for id in FORMATS:
				items.append({"id": id, "description": FORMATS[id], "default": DEFAULT_FORMATS.has(id)})
		"packs":
			for pack in catalog.packs:
				items.append({"id": pack.name, "author": pack.author, "license": pack.license, "description": pack.summary()})
		"modes":
			var names := MusicTheory.SCALES.keys()
			names.sort()
			for m in names:
				items.append({"id": m})
		"keys":
			for k in KEYS:
				items.append({"id": k})
		"structures":
			for f in SongSettings.FORMS:
				items.append({"id": f})
		"engines":
			for e in SynthEngines.CHOICES:
				items.append({"id": e, "name": SynthEngines.NAMES[e], "description": SynthEngines.DESCRIPTIONS[e]})
	_report["items"] = items
	for item in items:
		var line := str(item["id"])
		if item.has("group"):
			line = "%-24s %-26s %s" % [item["id"], item["name"], item["group"]]
		elif item.has("chip"):
			line = "%-10s %s (%s)%s" % [item["id"], item["name"], item["chip"], "" if item["available"] else ", not available yet"]
		elif item.has("description"):
			line = "%-10s %s" % [item["id"], item["description"]]
		_say_human(line)
	return OK_CODE


func _version() -> int:
	_report["app"] = BuildInfo.version()
	_report["build"] = BuildInfo.build_number()
	_report["engine"] = SongGenerator.ENGINE_VERSION
	_report["formats"] = {"song": ChipSong.VERSION, "sfx": ChipSfx.VERSION, "kit": ChipSfxKit.VERSION, "project": ProjectFile.VERSION, "pack": ChipPack.VERSION}
	_say_human("Chiptune Forge %s (%s), engine %s, song format %d, project format %d" % [BuildInfo.version(), BuildInfo.label(true), SongGenerator.ENGINE_VERSION, ChipSong.VERSION, ProjectFile.VERSION])
	return OK_CODE


# Output ----------------------------------------------------------------------

func _load_pack(path: String) -> String:
	if not FileAccess.file_exists(path):
		return "cannot read %s" % path
	var parsed := ChipPack.parse(FileAccess.get_file_as_string(path), catalog)
	if parsed.has("error"):
		return "%s: %s" % [path.get_file(), parsed["error"]]
	return catalog.add_pack(parsed["pack"])


func _report_dict(report: Array[String]) -> Dictionary:
	return {"fits": TargetReport.fits(report), "changed": TargetReport.changed(report), "lines": Array(TargetReport.plain(report))}


func _strict_code(flags: Dictionary, report: Array[String]) -> int:
	if flags.has("strict") and (not TargetReport.fits(report) or TargetReport.changed(report)):
		_say_human("Strict: %s." % ("over the chip's limits" if not TargetReport.fits(report) else "the arranger changed the music to fit"))
		return LIMITS
	return OK_CODE


func _fail(code: int, message: String, _command: String) -> int:
	_report["error"] = message
	if not _json:
		output.append("error: " + message)
		if not silent:
			printerr("error: " + message)
	return code


func _say(text: String) -> void:
	output.append(text)
	if not silent:
		print(text)


func _say_human(text: String) -> void:
	if not _json:
		_say(text)


func _say_report(report: Array[String]) -> void:
	for line in TargetReport.plain(report):
		_say_human("  " + line)


func _usage() -> String:
	return "\n".join(PackedStringArray([
		"Chiptune Forge %s: royalty-free chiptune music and sound effects." % BuildInfo.version(),
		"",
		"Usage: chiptune-forge --headless -- <command> [flags]",
		"   or: godot --headless --path . -- <command> [flags]",
		"",
		"Commands:",
		"  generate   make a song:   generate --vibe happy:70 --vibe cozy:30 --style platformer --target gameboy --seed 1234 --out build/music",
		"  sfx        make sounds:   sfx --preset jump --preset coin --variants 5 --target nes --out build/sfx",
		"  export     export again:  export level1.cforge --target nes --format console",
		"  batch      run a manifest of jobs: batch music.manifest.json",
		"  validate   check a file against the format and a target's limits: validate theme.chipsong --target snes --strict",
		"  list       list vibes, styles, targets, presets, formats, packs, modes, keys, structures or engines",
		"  version    print the app, engine and format versions",
		"",
		"Flags for generate: --vibe id[:strength] (up to three), --style, --target, --intensity 0-100,",
		"  --complexity 0-100, --tempo BPM|auto, --key C..B|auto, --mode name|auto, --length seconds|m:ss,",
		"  --structure, --energy, --loop/--no-loop, --intro/--no-intro, --outro/--no-outro, --seed,",
		"  --engine chip|auto|analog|fm|wavetable|sampled, --layer-engine Layer:engine (repeatable),",
		"  --settings file.json (flags override it).",
		"For --target pc: --card speaker|tandy|adlib|sb|sbpro|sb16|mt32|gm|gus picks the sound card (default adlib).",
		"Output: --format json,plugin,wav,stems,midi,console,project (default: json,plugin,wav,console,project),",
		"  --out folder, --name prefix, --loops n, --rate 44100|48000 (WAV sample rate).",
		"Everywhere: --json for a machine-readable report (--report file.json writes it to a file), --strict to fail when the music does not fit a",
		"  chip or had to change, --pack file.chippack to use a community pack.",
		"",
		"Exit codes: 0 success, 1 bad arguments, 2 chip limits (--strict), 3 file error, 4 invalid file.",
	]))
