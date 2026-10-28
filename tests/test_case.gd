extends RefCounted
## Base class for tests run by run_tests.gd. Methods named test_* are run in
## order; a failed check records a message and the test carries on.

var failures: PackedStringArray = []
var update_golden := false


func check(condition: bool, message := "check failed") -> void:
	if not condition:
		failures.append(message)


func check_eq(actual: Variant, expected: Variant, message := "") -> void:
	if typeof(actual) != typeof(expected) or actual != expected:
		failures.append("%sexpected %s, got %s" % [message + ": " if message else "", str(expected), str(actual)])


func check_near(actual: float, expected: float, tolerance: float, message := "") -> void:
	if absf(actual - expected) > tolerance:
		failures.append("%sexpected %s ± %s, got %s" % [message + ": " if message else "", expected, tolerance, actual])


## Compares [param text] with the golden file [param golden_name] in
## tests/golden/. With --update-golden the file is rewritten instead.
func check_golden(golden_name: String, text: String) -> void:
	var path := "res://tests/golden/" + golden_name
	if update_golden or not FileAccess.file_exists(path):
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(text)
		file.close()
		if not update_golden:
			failures.append("golden file %s was missing and has been written; check it in" % golden_name)
		return
	var expected := FileAccess.get_file_as_string(path)
	if expected != text:
		var a := expected.split("\n")
		var b := text.split("\n")
		var line := 0
		while line < mini(a.size(), b.size()) and a[line] == b[line]:
			line += 1
		failures.append("output differs from golden file %s at line %d. Run with --update-golden if the change is intended." % [golden_name, line + 1])
