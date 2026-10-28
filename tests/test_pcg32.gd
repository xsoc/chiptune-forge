extends "res://tests/test_case.gd"


func test_reference_sequence() -> void:
	# Output of the reference pcg32-demo for seed 42, sequence 54.
	var rng := Pcg32.new(42, 54)
	var expected := [0xa15c02b7, 0x7b47f409, 0xba1d3330, 0x83d2f293, 0xbfa4784b, 0xcbed606e]
	for value in expected:
		check_eq(rng.next_u32(), value, "pcg32 output")


func test_streams_are_independent_and_repeatable() -> void:
	var a := Pcg32.for_stream(1234, "melody:0")
	var b := Pcg32.for_stream(1234, "melody:0")
	var c := Pcg32.for_stream(1234, "melody:1")
	var same := 0
	for i in 64:
		var x := a.next_u32()
		check_eq(b.next_u32(), x, "same stream")
		if c.next_u32() == x:
			same += 1
	check(same < 2, "different streams should not match")


func test_ranges() -> void:
	var rng := Pcg32.for_stream(7, "ranges")
	var seen := {}
	for i in 2000:
		var n := rng.range_int(3, 9)
		check(n >= 3 and n <= 9, "range_int out of bounds: %d" % n)
		seen[n] = true
		var f := rng.next_float()
		check(f >= 0.0 and f < 1.0, "next_float out of bounds: %f" % f)
	check_eq(seen.size(), 7, "range_int covers every value")


func test_seed_from_text() -> void:
	check_eq(Pcg32.seed_from_text("12345"), Pcg32.seed_from_text("12345"))
	check(Pcg32.seed_from_text("castle") != Pcg32.seed_from_text("castles"), "text seeds differ")
