extends SceneTree
## Writes Master System example data for CI to check with PSGlib's tools:
##   godot --headless --path . -s tools/sms_examples.gd -- out_dir
## For a few generated songs, out_dir/song_<name>.psg (PSGlib data), .vgm,
## _psg.c and _psg.h, and a sound kit's .psg and .vgm per sound, plus
## kit_psg.c and kit_psg.h. Also writes song_<name>_preview.wav, the app's
## own preview, to check it makes sound. Sound files are named
## sfx_<name>_ch<channel>, the channel the sound plays on.

const SONGS := [
	["happy", "platformer", "42"],
	["boss_fight", "metal", "boss"],
	["cozy", "bossa_nova", "7"],
]


func _initialize() -> void:
	var out := OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out)
	for entry in SONGS:
		var s := SongSettings.new()
		s.vibes.assign([entry[0]])
		s.style = entry[1]
		s.seed_text = entry[2]
		var sms := SmsArranger.arrange(SongGenerator.generate(s))
		var name := "song_" + ExportJob.sanitize("%s %s" % [entry[0], entry[1]])
		var recorded := PsgWriter.record(sms)
		var psg := PsgWriter.encode(recorded)
		_write(out.path_join(name + ".psg"), psg)
		_write(out.path_join(name + ".vgm"), PsgWriter.vgm_bytes(recorded))
		var blobs := {PsgWriter.symbol(name) + "_psg": psg}
		_write(out.path_join(name + "_psg.c"), PsgWriter.c_source(blobs, name + "_psg.h", sms.title).to_utf8_buffer())
		_write(out.path_join(name + "_psg.h"), PsgWriter.c_header(blobs, name.to_upper() + "_PSG_H", sms.title).to_utf8_buffer())
		var seq := SmsSequencer.new(sms, 44100)
		seq.seek_step(0)
		var frames := seq.render(44100 * 8)
		var bytes := ChipAudio.wav_header(frames.size() * 4, 2, 44100, -1, -1)
		var header := bytes.size()
		bytes.resize(header + frames.size() * 4)
		ChipAudio.write_pcm16_stereo(frames, bytes, header)
		_write(out.path_join(name + "_preview.wav"), bytes)
	var catalog := Catalog.get_default()
	var kit := {}
	for id in ["coin", "jump", "explosion", "laser", "power_up"]:
		if catalog.sfx_presets.has(id):
			var sfx := SmsSfx.from_sfx(SfxGenerator.make_sfx(catalog.sfx_presets[id], 1), id)
			var recorded := PsgWriter.record(sfx.to_song(), 1 << sfx.channel)
			var psg := PsgWriter.encode(recorded)
			# The channel goes in the name, for vgm2psg's channel argument.
			var base := "sfx_%s_ch%d" % [id, sfx.channel]
			_write(out.path_join(base + ".psg"), psg)
			_write(out.path_join(base + ".vgm"), PsgWriter.vgm_bytes(recorded))
			kit[PsgWriter.symbol(id) + "_psg"] = psg
	_write(out.path_join("kit_psg.c"), PsgWriter.c_source(kit, "kit_psg.h", "CI kit").to_utf8_buffer())
	_write(out.path_join("kit_psg.h"), PsgWriter.c_header(kit, "KIT_PSG_H", "CI kit").to_utf8_buffer())
	print("Wrote Master System examples to ", out)
	quit()


func _write(path: String, data: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(data)
	file.close()
