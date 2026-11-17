extends SceneTree
## Writes DOS PC sound card examples for CI:
##   godot --headless --path . -s tools/pc_examples.gd -- out_dir
## For each FM card, out_dir gets the song as IMF (.wlf, OPL2 only), DRO
## and VGM files and <card>_preview.wav, the app's own preview, to compare
## with how AdPlug plays the files; for the Tandy, tandy.vgm and its preview
## to compare with libvgm. out_dir/speaker is the PC speaker export (C data,
## player and example), for Open Watcom to build. Sound effects go in
## out_dir/sfx: VOC files for the Sound Blaster and DRO files for the AdLib,
## and out_dir/speaker_sfx is the PC speaker's sound kit export.

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
		if PcCards.is_module(card):
			var mod: ModuleSong = PcCards.arrange(song, card)
			_write(out.path_join(card + ".mid"), mod.midi_bytes())
			var preview := ChipSongSequencer.new(mod.preview, 44100)
			preview.seek_step(0)
			_write(out.path_join(card + "_preview.wav"), ChipAudio.encode_wav_stereo(preview.render(44100 * 12), 44100))
			print("%s: written in %d ms" % [card, Time.get_ticks_msec() - started])
			continue
		if card == "gus":
			var gus: GusSong = PcCards.arrange(song, card)
			_write(out.path_join("gus.it"), ItWriter.module_bytes(gus, false))
			var gus_seq := GusSequencer.new(gus, 44100)
			gus_seq.seek_step(0)
			_write(out.path_join("gus_preview.wav"), ChipAudio.encode_wav_stereo(gus_seq.render(44100 * 12), 44100))
			print("gus: written in %d ms" % (Time.get_ticks_msec() - started))
			continue
		if not PcCards.is_fm(card):
			var arranged: NesSong = PcCards.arrange(song, card)
			var job := ExportJob.for_target_song("pc", song, {"prefix": "tune", "wav": false, "card": card}, arranged)
			job.run()
			for path: String in job.files:
				if path.begins_with("pc/"):
					var dest := out.path_join(card).path_join(path.get_file()) if card == "speaker" else out.path_join("tandy.vgm")
					DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
					if card == "speaker" or path.ends_with(".vgm"):
						_write(dest, job.files[path])
			var player: Variant = SpeakerSequencer.new(arranged, 44100) if arranged is SpeakerSong else SmsSequencer.new(arranged, 44100)
			player.seek_step(0)
			_write(out.path_join(card + "_preview.wav"), ChipAudio.encode_wav_stereo(player.render(44100 * 12), 44100))
			print("%s: written in %d ms" % [card, Time.get_ticks_msec() - started])
			continue
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
	var kit := {}
	for id in ["coin", "jump", "explosion", "laser"]:
		if catalog.sfx_presets.has(id):
			kit[id] = SfxGenerator.make_sfx(catalog.sfx_presets[id], 1)
	var sfx_job := ExportJob.for_target_sfx("pc", kit, "kit", {"card": "speaker", "wav": false})
	sfx_job.run()
	DirAccess.make_dir_recursive_absolute(out.path_join("speaker_sfx"))
	for path: String in sfx_job.files:
		if path.begins_with("pc/"):
			_write(out.path_join("speaker_sfx").path_join(path.get_file()), sfx_job.files[path])
	print("Wrote the DOS PC examples to ", out)
	quit()


func _write(path: String, data: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(data)
	file.close()
