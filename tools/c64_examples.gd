extends SceneTree
## Writes Commodore 64 examples for CI:
##   godot --headless --path . -s tools/c64_examples.gd -- out_dir
## out_dir gets each song as a PSID file (song_<name>.sid) and, for the first
## song, song_<name>_preview.wav (the app's own preview, to compare with how
## sidplayfp plays the PSID) and song_<name>_expected.bin (the registers the
## preview sets on every frame, 25 bytes a frame, through the loop, for
## tools/sid_check.py), and sfx.bin (sound effects). out_dir/project and
## out_dir/sfx are example programs for ca65, the second playing the sound
## effects every two seconds over the music.

const SONGS := [
	["happy", "platformer", "42"],
	["boss_fight", "metal", "boss"],
	["cozy", "bossa_nova", "7"],
]


func _initialize() -> void:
	var out := OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out)
	var first: SidSong = null
	var first_name := ""
	for entry in SONGS:
		var s := SongSettings.new()
		s.vibes.assign([entry[0]])
		s.style = entry[1]
		s.seed_text = entry[2]
		var started := Time.get_ticks_msec()
		var sid := SidArranger.arrange(SongGenerator.generate(s))
		var name := "song_" + ExportJob.sanitize("%s %s" % [entry[0], entry[1]])
		var psid := SidWriter.psid_bytes(sid)
		_write(out.path_join(name + ".sid"), psid)
		print("%s: arranged and written in %d ms, %d bytes" % [name, Time.get_ticks_msec() - started, psid.size()])
		if first == null:
			first = sid
			first_name = name
			var seq := SidSequencer.new(sid, 44100)
			seq.seek_step(0)
			_write(out.path_join(name + "_preview.wav"), ChipAudio.encode_wav_stereo(seq.render(44100 * 12), 44100))
			var rec := SidWriter.record_song(sid)
			var frames: Array = rec["frames"]
			var loop_frame := int(rec["loop_frame"])
			var expected := PackedByteArray()
			for f in frames.size() + 300:
				var regs: PackedInt32Array = frames[f] if f < frames.size() else frames[loop_frame + f - frames.size()]
				for r in SidWriter.REGS:
					expected.append(regs[r] & 0xFF)
			_write(out.path_join(name + "_expected.bin"), expected)
	var catalog := Catalog.get_default()
	var sounds: Array = []
	for id in ["coin", "jump", "explosion", "laser", "power_up"]:
		if catalog.sfx_presets.has(id):
			sounds.append(SidSfx.from_sfx(SfxGenerator.make_sfx(catalog.sfx_presets[id], 1), id))
	_write(out.path_join("sfx.bin"), SidWriter.sfx_bytes(sounds))
	for dir in ["project", "sfx"]:
		var path := out.path_join(dir)
		DirAccess.make_dir_recursive_absolute(path)
		var count := sounds.size() if dir == "sfx" else 0
		_write(path.path_join("song.bin"), SidWriter.song_bytes(first))
		if count > 0:
			_write(path.path_join("sfx.bin"), SidWriter.sfx_bytes(sounds))
		_write(path.path_join("sid_player.s"), SidWriter.player_source().to_utf8_buffer())
		_write(path.path_join("sid_player.bin"), SidWriter.player_binary())
		_write(path.path_join("sid_player.cfg"), SidWriter.player_config().to_utf8_buffer())
		_write(path.path_join("main.s"), SidWriter.example_source("Chiptune Forge CI", count).to_utf8_buffer())
		_write(path.path_join("main.cfg"), SidWriter.example_config().to_utf8_buffer())
		_write(path.path_join("Makefile"), SidWriter.makefile(first_name).to_utf8_buffer())
	print("Wrote the Commodore 64 examples to ", out)
	quit()


func _write(path: String, data: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(data)
	file.close()
