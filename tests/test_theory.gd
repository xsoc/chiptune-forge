extends "res://tests/test_case.gd"


func test_fold_keeps_pitch_class() -> void:
	for pitch in range(0, 128):
		var folded := MusicTheory.fold(pitch, 60, 76)
		check(folded >= 60 and folded <= 76, "fold range for %d" % pitch)
		check_eq(folded % 12, pitch % 12, "pitch class of %d" % pitch)


func test_scales_are_sorted_pitch_classes() -> void:
	for mode in MusicTheory.SCALES:
		var scale: Array = MusicTheory.SCALES[mode]
		check(scale[0] == 0, "%s starts on the root" % mode)
		for i in range(1, scale.size()):
			check(scale[i] > scale[i - 1] and scale[i] < 12, "%s is ascending" % mode)


func test_every_mode_has_a_name() -> void:
	for mode in MusicTheory.MODE_NAMES:
		check(MusicTheory.SCALES.has(mode), "%s has a scale" % mode)


func test_every_mode_has_a_feeling() -> void:
	for mode in MusicTheory.MODE_NAMES:
		check(MusicTheory.MODE_FEELINGS.has(mode), "%s has a feeling" % mode)
		var words: int = MusicTheory.MODE_FEELINGS.get(mode, "").replace(",", " ").split(" ", false).size()
		check(words >= 1 and words <= 3, "%s feeling is one to three words" % mode)
	check_eq(MusicTheory.mode_label("phrygian"), "Phrygian (Dark, menacing)")


func test_fit_chord_keeps_chords_that_fit() -> void:
	check_eq(MusicTheory.fit_chord(7, "dom7", 0, "major"), {"root": 7, "quality": "dom7"}, "V7 in C major")
	check_eq(MusicTheory.fit_chord(9, "min", 0, "major"), {"root": 9, "quality": "min"}, "vi in C major")


func test_fit_chord_bends_borrowed_chords_into_the_scale() -> void:
	# V in A natural minor has G#, which is not in the scale: it becomes v.
	check_eq(MusicTheory.fit_chord(4, "maj", 9, "minor"), {"root": 4, "quality": "min"}, "V in A minor")
	# IV in C Lydian has F natural: it keeps F's neighbour notes instead.
	var lydian_iv := MusicTheory.fit_chord(5, "maj", 0, "lydian")
	for pc in MusicTheory.chord_pitch_classes(lydian_iv["root"], lydian_iv["quality"]):
		check(MusicTheory.in_scale(pc, 0, "lydian"), "IV in C Lydian note %d" % pc)
	for mode in MusicTheory.SCALES:
		for key in 12:
			for offset in 12:
				for quality in MusicTheory.CHORD_INTERVALS:
					var fitted := MusicTheory.fit_chord(key + offset, quality, key, mode)
					var pcs := MusicTheory.chord_pitch_classes(fitted["root"], fitted["quality"])
					check(pcs.size() >= 2, "%s chord has notes" % mode)
					for pc in pcs:
						check(MusicTheory.in_scale(pc, key, mode), "%s %d %s %d fits" % [mode, key, quality, offset])


func test_numeral_for_round_trips() -> void:
	for offset in 12:
		for quality in MusicTheory.CHORD_INTERVALS:
			var numeral := MusicTheory.numeral_for(offset, quality)
			var parsed := MusicTheory.parse_numeral(numeral)
			check_eq(parsed["root"], offset, numeral + " root")
			var back := MusicTheory.chord_pitch_classes(parsed["root"], parsed["quality"])
			check_eq(back, MusicTheory.chord_pitch_classes(offset, quality), numeral + " notes")
