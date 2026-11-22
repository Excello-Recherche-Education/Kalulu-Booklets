extends GutTest
## FontFace against the Python generator's Face, HarfBuzz and fontTools, on
## the four fonts the booklets print with (tests/fixtures/fonts.json, written
## by tools/godot_fixtures.py at 338cae2, the last commit with the Python generator, from kalulu-languages/fonts). A font changed in Kalulu-Fonts
## since leaves its tests pending: to check it again, run that script at that
## commit with the new font in place.

var _fixture: Dictionary


func before_all() -> void:
	_fixture = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/fonts.json"))


## The fixture's fonts that are on disk and unchanged since it was written.
func _faces() -> Dictionary:
	var faces := {}
	var folder := FontSet.pinned_folder()
	for file: String in _fixture["fonts"]:
		var bytes := FileAccess.get_file_as_bytes(folder.path_join(file))
		if bytes.is_empty():
			pending("%s is not checked out: kalulu-languages/ with its fonts submodule is needed" % file)
			continue
		var hashing := HashingContext.new()
		hashing.start(HashingContext.HASH_SHA256)
		hashing.update(bytes)
		if hashing.finish().hex_encode() != _fixture["fonts"][file]["sha256"]:
			pending("%s changed since tests/fixtures/fonts.json was written: rewrite it with tools/godot_fixtures.py at 338cae2" % file)
			continue
		faces[file] = FontFace.new(bytes, file)
	return faces


func test_metrics() -> void:
	var faces := _faces()
	for file: String in faces:
		var face: FontFace = faces[file]
		var expected: Dictionary = _fixture["fonts"][file]
		assert_eq(face.units, int(expected["units"]), "%s: units per em" % file)
		assert_almost_eq(face.x_height, float(expected["x_height"]), 1e-9, "%s: x-height" % file)
		assert_almost_eq(face.cap_height, float(expected["cap_height"]), 1e-9, "%s: cap height" % file)


func test_shaping_matches_harfbuzz() -> void:
	var faces := _faces()
	for file: String in faces:
		var face: FontFace = faces[file]
		var expected: Dictionary = _fixture["fonts"][file]["shaped"]
		for text: String in expected:
			var got: Array = []
			for glyph: Array in face.shape(text):
				got.append([glyph[0], glyph[1], snappedf(glyph[2] * face.units, 0.01),
						snappedf(glyph[3] * face.units, 0.01), snappedf(glyph[5], 0.01)])
			var want: Array = expected[text].map(func(glyph: Array) -> Array:
				return [int(glyph[0]), int(glyph[1]), snappedf(glyph[2], 0.01), snappedf(glyph[3], 0.01),
						snappedf(glyph[4], 0.01)])
			assert_eq(str(got), str(want), "%s: \"%s\" shaped as HarfBuzz shapes it" % [file, text])


func test_missing_letters_are_recorded() -> void:
	var faces := _faces()
	for file: String in faces:
		var face: FontFace = faces[file]
		for text: String in _fixture["texts"]:
			face.shape(text)
		assert_eq(StableSort.sorted(face.missing.keys()), _fixture["fonts"][file]["missing"],
				"%s: the letters it cannot print" % file)


func test_widths_with_spacing() -> void:
	var faces := _faces()
	var spacings: Array = _fixture["spacings"]
	for file: String in faces:
		var face: FontFace = faces[file]
		var expected: Dictionary = _fixture["fonts"][file]["widths"]
		for text: String in expected:
			for index in spacings.size():
				var spacing := TextSpacing.new(spacings[index][0], spacings[index][1])
				assert_almost_eq(face.width(text, 16.0, spacing), float(expected[text][index]), 1e-6,
						"%s: width of \"%s\" with spacing %s" % [file, text, spacings[index]])


func test_ink_matches_python() -> void:
	var faces := _faces()
	for file: String in faces:
		var face: FontFace = faces[file]
		var expected: Dictionary = _fixture["fonts"][file]["ink"]
		for text: String in expected:
			var ink := face.ink(text)
			# 1e-5 em: Godot's outline points are 32-bit floats.
			assert_almost_eq(ink[0], float(expected[text][0]), 1e-5, "%s: top of \"%s\"" % [file, text])
			assert_almost_eq(ink[1], float(expected[text][1]), 1e-5, "%s: bottom of \"%s\"" % [file, text])


## Every glyph of every font: the bounds Face.ink() is built on, against
## fontTools' BoundsPen.
func test_every_glyph_bounds_match_fonttools() -> void:
	var faces := _faces()
	for file: String in faces:
		var face: FontFace = faces[file]
		var expected: Array = _fixture["fonts"][file]["bounds"]
		var wrong: Array = []
		for index in expected.size():
			var want: Variant = expected[index]
			var got: Variant = face.glyph_bounds(index)
			if want == null or got == null:
				if want != got:
					wrong.append("glyph %d: %s instead of %s" % [index, got, want])
				continue
			for side in 4:
				if absf(float(got[side]) - float(want[side])) > 0.01:
					wrong.append("glyph %d: %s instead of %s" % [index, got, want])
					break
		assert_eq(wrong.size(), 0, "%s: %d of %d glyphs bounded differently, first: %s"
				% [file, wrong.size(), expected.size(), wrong.slice(0, 5)])


func test_draw_colours_by_cluster_and_spaces_letters() -> void:
	var faces := _faces()
	if faces.is_empty():
		return
	var face: FontFace = faces.values()[0]
	var surface := RecordingSurface.new(Vector2(420, 595))
	var red := Color(1, 0, 0)
	var grey := Color(0.5, 0.5, 0.5)
	var spacing := TextSpacing.new(0.1, 0.5)
	var width := face.draw(surface, 10.0, 20.0, "la lune", 16.0, Color.BLACK, [1], grey, {3: red}, spacing)
	assert_almost_eq(width, face.width("la lune", 16.0, spacing), 1e-9, "draw returns the width it drew")
	var operation: Dictionary = surface.pages[0][0]
	assert_eq(operation["op"], "glyphs")
	var glyphs: Array = operation["glyphs"]
	assert_eq(glyphs[0][3], [0.0, 0.0, 0.0], "l in black")
	assert_eq(glyphs[1][3], [grey.r, grey.g, grey.b], "a in grey")
	assert_eq(glyphs[3][3], [1.0, 0.0, 0.0], "the first l of lune in red")
	assert_eq(glyphs[0][4], "l", "each glyph says which letter it stands for")
	assert_almost_eq(glyphs[0][1], 10.0, 1e-9, "the first glyph at x")
	var shaped := face.shape("la lune")
	assert_almost_eq(glyphs[1][1], 10.0 + (shaped[0][4] + 0.1) * 16.0, 1e-9, "letter spacing after l")
	assert_almost_eq(glyphs[3][1], glyphs[2][1] + 0.5 * 16.0, 1e-9, "the space as wide as asked")
