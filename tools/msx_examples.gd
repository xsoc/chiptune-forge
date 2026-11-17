extends SceneTree
## Writes MSX and ZX Spectrum 128 example projects for CI to build with
## Pasmo:
##   godot --headless --path . -s tools/msx_examples.gd -- out_dir
## out_dir/project plays the first song with our Z80 player (song_msx.bin,
## song_zx.bin, ay_player.asm, msx_main.asm, zx_main.asm, Makefile).
## out_dir/sfx is the same with sound effects played every two seconds over
## the music. out_dir also gets each song's data and VGM, and for the first
## song: song_<name>_preview.wav (the app's own preview, to compare with
## the VGM played by another emulator) and song_<name>_expected_<machine>.bin
## (the registers the preview sets on every frame, 11 bytes a frame, through
## the loop, for tools/ay_check.py to compare with the Z80 player).

const SONGS := [
	["happy", "platformer", "42"],
	["boss_fight", "metal", "boss"],
	["cozy", "bossa_nova", "7"],
]


func _initialize() -> void:
	var out := OS.get_cmdline_user_args()[0]
	var first: AySong = null
	var first_name := ""
	DirAccess.make_dir_recursive_absolute(out)
	for entry in SONGS:
		var s := SongSettings.new()
		s.vibes.assign([entry[0]])
		s.style = entry[1]
		s.seed_text = entry[2]
		var started := Time.get_ticks_msec()
		var ay := AyArranger.arrange(SongGenerator.generate(s))
		var name := "song_" + ExportJob.sanitize("%s %s" % [entry[0], entry[1]])
		var data := AyWriter.song_bytes(ay)
		_write(out.path_join(name + ".bin"), data)
		_write(out.path_join(name + ".vgm"), AyWriter.vgm_bytes(ay))
		print("%s: arranged and written in %d ms, %d bytes" % [name, Time.get_ticks_msec() - started, data.size()])
		if first == null:
			first = ay
			first_name = name
			var seq := AySequencer.new(ay, 44100)
			seq.seek_step(0)
			_write(out.path_join(name + "_preview.wav"), ChipAudio.encode_wav_stereo(seq.render(44100 * 12), 44100))
			for machine in AyWriter.MACHINES:
				var rec := AyWriter.record_song(ay, AyWriter.MACHINES[machine])
				var frames: Array = rec["frames"]
				var loop_frame := int(rec["loop_frame"])
				var expected := PackedByteArray()
				for f in frames.size() + 300:
					var regs: PackedInt32Array = frames[f] if f < frames.size() else frames[loop_frame + f - frames.size()]
					for r in AyWriter.REGS:
						expected.append(regs[r] & 0xFF)
				_write(out.path_join("%s_expected_%s.bin" % [name, machine]), expected)
	var catalog := Catalog.get_default()
	var sounds: Array = []
	for id in ["coin", "jump", "explosion", "laser", "power_up"]:
		if catalog.sfx_presets.has(id):
			sounds.append(AySfx.from_sfx(SfxGenerator.make_sfx(catalog.sfx_presets[id], 1), id))
	for dir in ["project", "sfx"]:
		var path := out.path_join(dir)
		DirAccess.make_dir_recursive_absolute(path)
		var count := sounds.size() if dir == "sfx" else 0
		for machine in AyWriter.MACHINES:
			_write(path.path_join("song_%s.bin" % machine), AyWriter.song_bytes(first, AyWriter.MACHINES[machine]))
			if count > 0:
				_write(path.path_join("sfx_%s.bin" % machine), AyWriter.sfx_bytes(sounds, AyWriter.MACHINES[machine]))
		_write(path.path_join("ay_player.asm"), AyWriter.player_asm().to_utf8_buffer())
		_write(path.path_join("Makefile"), AyWriter.makefile(first_name).to_utf8_buffer())
		_write(path.path_join("msx_main.asm"), AyWriter.msx_main("Chiptune Forge CI", count).to_utf8_buffer())
		_write(path.path_join("zx_main.asm"), AyWriter.zx_main("Chiptune Forge CI", count).to_utf8_buffer())
	print("Wrote the MSX and Spectrum example projects to ", out)
	quit()


func _write(path: String, data: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(data)
	file.close()
