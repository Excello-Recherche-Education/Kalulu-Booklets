class_name PythonUnicode
extends RefCounted
## Text treated as Python treats it, where Godot differs.
##
## - Case: Godot's ``to_lower()`` / ``to_upper()`` map one character to one,
##   and so do the generator's ``lower()`` / ``upper()``, which keep a
##   character whose Python mapping is longer ("İ", "ß", "ᾳ"). Godot follows
##   a newer Unicode than Python 3.13 on a few characters added in Unicode 16;
##   no pack writes with them.
## - Whitespace: ``strip_edges()`` strips only control characters and spaces,
##   ``str.strip()`` every character ``str.isspace()`` is true of, the no-break
##   spaces included.
## - Normalisation: Godot 4.7 has none. NFC and NFD are done here for the Latin
##   letters, which is all a pack's file names hold (``BookletPack.picture()``).
##
## The tables are PythonUnicodeTables, written from Python by
## tools/godot_unicode.py.


## ``character`` lowercased as Python would, one character for one.
static func lower_char(character: String) -> String:
	if PythonUnicodeTables.MULTI_LOWER.has(character.unicode_at(0)):
		return character
	return character.to_lower()


## ``character`` uppercased as Python would, one character for one.
static func upper_char(character: String) -> String:
	if PythonUnicodeTables.MULTI_UPPER.has(character.unicode_at(0)):
		return character
	return character.to_upper()


## ``text`` lowercased one character for one, so positions still match.
static func lower(text: String) -> String:
	var lowered := text.to_lower()
	if not _has_special(text, PythonUnicodeTables.MULTI_LOWER):
		return lowered
	var out := PackedStringArray()
	for index in text.length():
		out.append(lower_char(text[index]))
	return "".join(out)


## ``text`` uppercased one character for one: "ß" stays "ß".
static func upper(text: String) -> String:
	var raised := text.to_upper()
	if not _has_special(text, PythonUnicodeTables.MULTI_UPPER):
		return raised
	var out := PackedStringArray()
	for index in text.length():
		out.append(upper_char(text[index]))
	return "".join(out)


## Python's own ``str.upper()``, which may lengthen the text: "SS" for "ß".
static func upper_full(text: String) -> String:
	var out := PackedStringArray()
	for index in text.length():
		var code := text.unicode_at(index)
		out.append(PythonUnicodeTables.MULTI_UPPER[code] if PythonUnicodeTables.MULTI_UPPER.has(code)
				else text[index].to_upper())
	return "".join(out)


static func is_space(character: String) -> bool:
	return PythonUnicodeTables.SPACES.has(character.unicode_at(0))


## ``str.strip()``.
static func strip(text: String) -> String:
	return rstrip(lstrip(text))


## ``str.lstrip()``.
static func lstrip(text: String) -> String:
	var start := 0
	while start < text.length() and PythonUnicodeTables.SPACES.has(text.unicode_at(start)):
		start += 1
	return text.substr(start)


## ``str.rstrip()``.
static func rstrip(text: String) -> String:
	var end := text.length()
	while end > 0 and PythonUnicodeTables.SPACES.has(text.unicode_at(end - 1)):
		end -= 1
	return text.substr(0, end)


## ``unicodedata.normalize("NFD", text)`` for Latin letters.
static func nfd(text: String) -> String:
	var codes: Array[int] = []
	for index in text.length():
		var code := text.unicode_at(index)
		if PythonUnicodeTables.DECOMPOSITIONS.has(code):
			var parts: String = PythonUnicodeTables.DECOMPOSITIONS[code]
			for part in parts.length():
				codes.append(parts.unicode_at(part))
		else:
			codes.append(code)
	# Canonical order: within a run of marks, by combining class, ties kept.
	var start := 0
	while start < codes.size():
		if _class_of(codes[start]) == 0:
			start += 1
			continue
		var end := start
		while end < codes.size() and _class_of(codes[end]) != 0:
			end += 1
		var run := StableSort.sorted(codes.slice(start, end), _class_of)
		for offset in run.size():
			codes[start + offset] = run[offset]
		start = end
	return _string_of(codes)


## ``unicodedata.normalize("NFC", text)`` for Latin letters.
static func nfc(text: String) -> String:
	var codes: Array[int] = []
	for character in nfd(text):
		codes.append(character.unicode_at(0))
	var out: Array[int] = []
	var starter := -1  # index in out of the last starter
	var last_class := -1  # class of the last character since it, -1 for none
	for code in codes:
		var klass := _class_of(code)
		if starter >= 0 and (last_class == -1 or (last_class != 0 and last_class < klass)):
			var pair := String.chr(out[starter]) + String.chr(code)
			if PythonUnicodeTables.COMPOSITIONS.has(pair):
				out[starter] = PythonUnicodeTables.COMPOSITIONS[pair]
				continue
		if klass == 0:
			starter = out.size()
			last_class = -1
		else:
			last_class = klass
		out.append(code)
	return _string_of(out)


static func _class_of(code: int) -> int:
	return PythonUnicodeTables.COMBINING_CLASSES.get(code, 0)


static func _has_special(text: String, table: Dictionary) -> bool:
	for index in text.length():
		if text.unicode_at(index) >= 0x80 and table.has(text.unicode_at(index)):
			return true
	return false


static func _string_of(codes: Array[int]) -> String:
	var out := PackedStringArray()
	for code in codes:
		out.append(String.chr(code))
	return "".join(out)
