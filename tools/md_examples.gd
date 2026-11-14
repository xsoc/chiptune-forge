extends SceneTree
## Writes a Mega Drive example project for CI to build with SGDK:
##   godot --headless --path . -s tools/md_examples.gd -- out_dir
## out_dir/project is an SGDK project: res/ holds a few generated songs as
## VGM and a sound kit as XGM WAVs, with resources.res; src/main.c plays
## the first song and loads every sound. out_dir also gets each song's VGM
## (song_<name>.vgm) for xgmtool to check, and song_<name>_preview.wav,
## the app's own preview, to compare with how the built ROM sounds.

const SONGS := [
	["happy", "platformer", "42"],
	["boss_fight", "metal", "boss"],
	["cozy", "bossa_nova", "7"],
]


func _initialize() -> void:
	var out := OS.get_cmdline_user_args()[0]
	var res := out.path_join("project/res")
	var src := out.path_join("project/src")
	DirAccess.make_dir_recursive_absolute(res)
	DirAccess.make_dir_recursive_absolute(src)
	var res_lines: PackedStringArray = []
	var first := ""
	for entry in SONGS:
		var s := SongSettings.new()
		s.vibes.assign([entry[0]])
		s.style = entry[1]
		s.seed_text = entry[2]
		var md := MdArranger.arrange(SongGenerator.generate(s))
		var name := "song_" + ExportJob.sanitize("%s %s" % [entry[0], entry[1]])
		var vgm := MdVgmWriter.vgm_bytes(MdVgmWriter.record(md), md.title, "CI example")
		_write(out.path_join(name + ".vgm"), vgm)
		_write(res.path_join(name + ".vgm"), vgm)
		res_lines.append(MdVgmWriter.res_line(name, name + ".vgm"))
		if first == "":
			first = name
			var seq := MdSequencer.new(md, 44100)
			seq.seek_step(0)
			var frames := seq.render(44100 * 12)
			_write(out.path_join(name + "_preview.wav"), ChipAudio.encode_wav_stereo(frames, 44100))
	var catalog := Catalog.get_default()
	var sounds: Array = []
	for id in ["coin", "jump", "explosion", "laser", "power_up"]:
		if catalog.sfx_presets.has(id):
			var sfx := MdSfx.from_sfx(SfxGenerator.make_sfx(catalog.sfx_presets[id], 1), id)
			sounds.append(sfx)
			_write(res.path_join(sfx.name + ".wav"), sfx.wav_bytes())
	_write(res.path_join("resources.res"), ("\n".join(res_lines) + "\n" + MdSfx.res_lines(sounds)).to_utf8_buffer())
	# The README's program, plus the README's sound setup, so CI compiles both.
	var main := MdVgmWriter.main_c(first, "Chiptune Forge CI")
	var setup: PackedStringArray = []
	for i in sounds.size():
		var sym := MdSfx.symbol((sounds[i] as MdSfx).name)
		setup.append("    XGM_setPCM(%d, %s, sizeof(%s));" % [64 + i, sym, sym])
	setup.append("    XGM_startPlayPCM(64, 1, SOUND_PCM_CH2);")
	main = main.replace("    XGM_startPlay(", "\n".join(setup) + "\n    XGM_startPlay(")
	_write(src.path_join("main.c"), main.to_utf8_buffer())
	print("Wrote the Mega Drive example project to ", out)
	quit()


func _write(path: String, data: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(data)
	file.close()
