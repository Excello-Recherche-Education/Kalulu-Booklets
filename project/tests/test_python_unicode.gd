extends GutTest
## PythonUnicode against Python's str and unicodedata (tools/godot_unicode.py
## writes the fixture), and BookletText's word cutting.


func _fixture() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/unicode.json"))


func test_case_matches_python_one_for_one() -> void:
	var cases: Dictionary = _fixture()["cases"]
	var wrong: Array[String] = []
	for key: String in cases:
		# Godot follows Unicode 16 here, Python 3.13 Unicode 15.1, which gave
		# these two no capital: no pack writes with them.
		if int(key) in [0x019B, 0x0264]:
			continue
		var character := String.chr(int(key))
		var expected_lower: String = cases[key][0]
		var expected_upper: String = cases[key][1]
		# One for one: a longer Python mapping leaves the character as it is.
		var lower := expected_lower if expected_lower.length() == 1 else character
		var upper := expected_upper if expected_upper.length() == 1 else character
		if PythonUnicode.lower(character) != lower or PythonUnicode.upper(character) != upper:
			wrong.append("U+%04X" % int(key))
		if PythonUnicode.upper_full(character) != expected_upper:
			wrong.append("U+%04X full" % int(key))
	assert_eq(wrong, [] as Array[String], "every character of the Latin, Greek and Cyrillic blocks")


func test_case_of_whole_texts() -> void:
	# Character by character, so no final sigma: Python's text.lower() does the same.
	assert_eq(PythonUnicode.lower("ΟΔΟΣ İstanbul Straße"), "οδοσ İstanbul straße")
	assert_eq(PythonUnicode.upper("straße ᾳ"), "STRAßE ᾳ")
	assert_eq(PythonUnicode.upper_full("ß"), "SS")


func test_whitespace_matches_python() -> void:
	var spaces: Array = _fixture()["spaces"]
	var found: Array = []
	for code in 0x3001:
		if PythonUnicode.is_space(String.chr(code)):
			found.append(float(code))
	assert_eq(found, spaces)
	for case: Array in _fixture()["strip"]:
		assert_eq(PythonUnicode.strip(case[0]), case[1], "strip %s" % var_to_str(case[0]))
		assert_eq(PythonUnicode.lstrip(case[0]), case[2])
		assert_eq(PythonUnicode.rstrip(case[0]), case[3])


func test_normalisation_matches_python() -> void:
	for case: Array in _fixture()["normalized"]:
		assert_eq(PythonUnicode.nfc(case[0]), case[1], "NFC of %s" % _codes(case[0]))
		assert_eq(PythonUnicode.nfd(case[0]), case[2], "NFD of %s" % _codes(case[0]))


func test_word_spans_cut_as_the_prof_tool_does() -> void:
	var words := {"tam-tam": [1], "arc-en-ciel": [2]}
	assert_eq(BookletText.words_of("L'ours a-t-il vu le tam-tam ? As-tu l’arc-en-ciel… ¡Sí!", words),
			["l", "ours", "a", "il", "vu", "le", "tam-tam", "as", "tu", "l", "arc-en-ciel", "sí"] as Array[String])
	assert_eq(BookletText.word_spans("a b c"), [[0, 3], [4, 5]], "a no-break space does not cut")
	assert_eq(BookletText.words_of("t-t-t"), ["t", "t"] as Array[String], "only an inner t is euphonic")


func _codes(text: String) -> String:
	var out := PackedStringArray()
	for character in text:
		out.append("%04X" % character.unicode_at(0))
	return " ".join(out)
