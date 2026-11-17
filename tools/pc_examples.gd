extends SceneTree
## Writes DOS PC sound card examples for CI:
##   godot --headless --path . -s tools/pc_examples.gd -- out_dir
## For each card, out_dir gets the song as IMF (.wlf, OPL2 only), DRO and
## VGM files and <card>_preview.wav, the app's own preview, to compare with
## how AdPlug plays the files. Sound effects go in out_dir/sfx: VOC files
## for the Sound Blaster and DRO files for the AdLib.

const SONG := ["happy", "rock", "opl"]


func _initialize() -> void:
	var out := OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out.path_join("sfx"))
	var s := SongSettings.new()
	s.vibes.assign([SONG[0]])
	s.style = SONG[1]
	s.seed_text = SONG[2]
	s.length_seconds = 30
	var song := SongGenerator.generate(s)
	for card in PcCards.CARDS:
		var started := Time.get_ticks_msec()
		var opl := OplArranger.arrange(song, card)
		var rec := OplWriter.record(opl)
		if opl.chip == "opl2":
			_write(out.path_join(card + ".wlf"), OplWriter.imf_bytes(rec, opl.title))
		_write(out.path_join(card + ".dro"), OplWriter.dro_bytes(rec, opl.chip))
		_write(out.path_join(card + ".vgm"), OplWriter.vgm_bytes(rec, opl.chip, opl.title, "IBM PC, " + PcCards.name_of(card), "Chiptune Forge CI"))
		var seq := OplSequencer.new(opl, 44100)
		seq.seek_step(0)
		_write(out.path_join(card + "_preview.wav"), ChipAudio.encode_wav_stereo(seq.render(44100 * 12), 44100))
		print("%s: %d notes, written in %d ms" % [card, opl.note_count(), Time.get_ticks_msec() - started])
	var catalog := Catalog.get_default()
	for id in ["coin", "jump", "explosion", "laser"]:
		if not catalog.sfx_presets.has(id):
			continue
		var sfx := SfxGenerator.make_sfx(catalog.sfx_presets[id], 1)
		_write(out.path_join("sfx/%s.voc" % id), PcSfx.from_sfx(sfx, "sb", id).voc_bytes())
		var fm := PcSfx.from_sfx(sfx, "adlib", id)
		_write(out.path_join("sfx/%s.dro" % id), OplWriter.dro_bytes(fm.recorded(), "opl2"))
		_write(out.path_join("sfx/%s_preview.wav" % id), ChipAudio.encode_wav_mono(fm.render(44100), 44100))
	print("Wrote the DOS PC examples to ", out)
	quit()


func _write(path: String, data: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(data)
	file.close()
