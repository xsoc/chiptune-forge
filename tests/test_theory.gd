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
