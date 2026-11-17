extends "res://tests/test_case.gd"
## The check for accidental likeness to well-known tunes.


## A song whose lead plays [param tune] (pitch, beats pairs) transposed, at
## four steps a beat, after a bar of other notes.
func _song_with(tune: Array, transpose: int) -> ChipSong:
	var song := SongGenerator.generate(SongSettings.new())
	var data := song.data.duplicate(true)
	var notes: Array = [[0, 2, 70, 100], [4, 2, 66, 100], [8, 4, 61, 100]]
	var step := 16
	for i in range(0, tune.size(), 2):
		var length := int(round(float(tune[i + 1]) * 4))
		notes.append([step, length, int(tune[i]) + transpose, 100])
		step += length
	data["patterns"].append({"notes": notes})
	var section: Dictionary = data["sections"][int(data["order"][0])]
	section["patterns"][0] = data["patterns"].size() - 1
	section["length"] = maxi(int(section["length"]), step)
	return ChipSong.from_dict(data)


func test_finds_a_known_tune_in_any_key() -> void:
	var ode: Array = SimilarityCheck.TUNES[1][1]
	var found := SimilarityCheck.find(_song_with(ode, -5))
	check_eq(found.get("tune", ""), "Ode to Joy")
	check(int(found.get("notes", 0)) >= SimilarityCheck.MATCH_NOTES)
	check_eq(found.get("step", -1), 16, "where the phrase starts")
	check(SimilarityCheck.report_line(_song_with(ode, 3)).contains("Sounds like Ode to Joy"))


func test_rhythm_matters() -> void:
	# Ode to Joy's pitches with every note a different length is not a match.
	var ode: Array = SimilarityCheck.TUNES[1][1].duplicate()
	for i in range(1, ode.size(), 2):
		ode[i] = [1, 3, 0.5, 2][(i / 2) % 4]
	check(SimilarityCheck.find(_song_with(ode, 0)).is_empty())


func test_generated_songs_pass() -> void:
	var catalog := Catalog.get_default()
	var vibes: Array = catalog.vibes.keys()
	for i in 12:
		var settings := SongSettings.new()
		settings.seed_text = str(i)
		settings.vibes = [vibes[i % vibes.size()]]
		var song := SongGenerator.generate(settings)
		check(SimilarityCheck.lead_notes(song).size() > 20, "the lead has notes")
		check(SimilarityCheck.find(song).is_empty(), "seed %d" % i)
	check(SimilarityCheck.report_line(SongGenerator.generate(SongSettings.new())).begins_with("Originality: "))
