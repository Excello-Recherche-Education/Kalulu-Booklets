extends GutTest
## Phase 4 of the port's check: every booklet of every pack, series and
## version drawn by BookletLayout / AdaptedLayout and BookletWriter as the
## Python generator's layout draws it, operation for operation, its notes and
## its printing copy's imposition included.
##
## The expected operations are recorded from ReportLab's canvas by
## tools/godot_layout.py into tests/generated/layout/, which is not committed
## (they follow the pinned packs): the Godot Tests workflow writes them before
## running GUT, and so must anyone running the tests by hand. Text is recorded
## as the layout asked for it; each is drawn here again with the port's
## FontFace, whose glyphs phase 2 checked against HarfBuzz, and the glyphs
## compared.

const GENERATED := "res://tests/generated/layout"
## How far two numbers may differ: positions in points, colours in [0, 1].
const TOLERANCE := 0.001


func _locales() -> Array[String]:
	var out: Array[String] = []
	if DirAccess.dir_exists_absolute(GENERATED):
		for file in DirAccess.get_files_at(GENERATED):
			if file.ends_with(".json"):
				out.append(file.get_basename())
	out.sort()
	return out


func _packs_folder() -> String:
	return ProjectSettings.globalize_path("res://").path_join("../kalulu-languages").simplify_path()


func test_every_pack_is_checked() -> void:
	if _locales().is_empty():
		pending("no expected layout: run tools/godot_layout.py first")
		return
	var packs: Array[String] = []
	for folder in DirAccess.get_directories_at(_packs_folder()):
		if FileAccess.file_exists(_packs_folder().path_join(folder).path_join("language.db")):
			packs.append(folder)
	packs.sort()
	assert_eq(_locales(), packs, "tools/godot_layout.py recorded every pack of kalulu-languages/")


func test_booklets_draw_what_python_draws() -> void:
	if _locales().is_empty():
		pending("no expected layout: run tools/godot_layout.py first")
		return
	for locale in _locales():
		var pack := BookletPackReader.new().read(_packs_folder().path_join(locale))
		if pack == null:
			fail_test("%s cannot be read" % locale)
			continue
		var replaced := {}
		for role: String in pack.fonts:
			replaced[role] = pack.fonts[role].file
		var found := FontSet.find(pack.folder, replaced)
		var fonts := FontSet.from_folder(found["folder"], replaced)
		var faces := {}
		for face: FontFace in fonts.roles().values():
			faces[face.file] = face
		var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
				GENERATED.path_join(locale + ".json")))
		var made: Array[String] = []
		for series in pack.series():
			for number in pack.booklets():
				for version in pack.versions():
					made.append("%s/%d/%s" % [series, number, version])
		assert_eq(made, Array(expected["runs"].keys(), TYPE_STRING, "", null), "%s draws the same booklets" % locale)
		for key: String in expected["runs"]:
			var parts := key.split("/")
			var run: Dictionary = expected["runs"][key]
			var booklet := BookletContent.booklet(pack, int(parts[1]), parts[0])
			var before := booklet.notes.size()
			var surface := RecordingSurface.new(BookletWriter.A5)
			var laid_out := BookletWriter.draw(surface, booklet, fonts, BookletVersion.named(parts[2]))
			var where := "%s %s" % [locale, key]
			assert_eq(_difference(run["notes"], booklet.notes.slice(before), where + " notes"), "")
			if run["imposition"] != null:
				assert_eq(_difference(run["imposition"], BookletWriter.sheet_sides(laid_out.pages.size()),
						where + " imposition"), "")
			assert_eq(_pages_difference(run["pages"], surface.finished_pages(), faces, pack, where), "")


## Draws an imposed copy of one booklet and checks every A4 side holds its two
## pages, each moved to its place, as the Python generator draws them.
func test_imposed_sheets_hold_the_pages() -> void:
	var pack := BookletPackReader.new().read(_packs_folder().path_join("fr_FR"))
	if pack == null:
		pending("fr_FR is not checked out")
		return
	var fonts := FontSet.from_folder(FontSet.pinned_folder())
	var booklet := BookletContent.booklet(pack, 1)
	var pages := RecordingSurface.new(BookletWriter.A5)
	var laid_out := BookletWriter.draw(pages, booklet, fonts)
	var sheets := RecordingSurface.new(BookletWriter.A4_LANDSCAPE)
	BookletWriter.draw_imposed(sheets, laid_out)
	var drawn := pages.finished_pages()
	var sides := sheets.finished_pages()
	assert_eq(sides.size(), drawn.size() / 2, "two pages an A4 side")
	assert_eq(drawn.size() % 4, 0, "a booklet of folded sheets")
	for side in sides.size():
		var expected: Array = []
		for placed: Array in BookletWriter.sheet_sides(drawn.size())[side]:
			expected.append({"op": "save"})
			expected.append({"op": "transform", "matrix": [1.0, 0.0, 0.0, 1.0, placed[1], 0.0]})
			expected.append_array(drawn[placed[0]])
			expected.append({"op": "restore"})
		assert_eq(_difference(expected, sides[side], "side %d" % side), "")
	assert_eq(BookletWriter.imposition(8), [[7, 0], [1, 6], [5, 2], [3, 4]], "saddle-stitch order")


## The pictures are kept twice until the Python generator goes (phase 5 of
## the port): src/kalulu_booklets/art/ for it, booklets/art/ for the port.
func test_art_matches_the_python_generators() -> void:
	var python := ProjectSettings.globalize_path("res://").path_join("../src/kalulu_booklets/art").simplify_path()
	var files: Array[String] = []
	for file in DirAccess.get_files_at(python):
		files.append(file)
		assert_eq(FileAccess.get_file_as_bytes(BookletArt.FOLDER.path_join(file)),
				FileAccess.get_file_as_bytes(python.path_join(file)), "%s is the same in both" % file)
	assert_true(files.has("parakeet.png") and files.has("kalulu-logo.svg"), "the Python art folder is read")


func test_booklet_writes_a_pdf() -> void:
	var pack := BookletPackReader.new().read(_packs_folder().path_join("fr_FR"))
	if pack == null:
		pending("fr_FR is not checked out")
		return
	var fonts := FontSet.from_folder(FontSet.pinned_folder())
	var written := BookletWriter.pdf(BookletContent.booklet(pack, 1), fonts, BookletVersion.named("base"), true)
	for bytes in written:
		assert_eq(bytes.slice(0, 8).get_string_from_ascii(), "%PDF-1.7")
		assert_gt(bytes.size(), 100000)
	var file := FileAccess.open("user://fr_FR-booklet-1.pdf", FileAccess.WRITE)
	file.store_buffer(written[0])
	file.close()


## The first difference between Python's pages and the port's, "" for none.
func _pages_difference(expected: Array, actual: Array, faces: Dictionary, pack: BookletPack, where: String) -> String:
	if expected.size() != actual.size():
		return "%s: %d pages, expected %d" % [where, actual.size(), expected.size()]
	for number in expected.size():
		var wanted := _expand(expected[number], faces)
		var drawn: Array = actual[number].map(func(operation: Dictionary) -> Dictionary:
			return _relative(operation, pack))
		var found := _difference(wanted, drawn, "%s page %d" % [where, number + 1])
		if not found.is_empty():
			return found
	return ""


## Python's operations as the port records them: text drawn again, glyph by
## glyph, with the port's FontFace.
func _expand(operations: Array, faces: Dictionary) -> Array:
	var out: Array = []
	for operation: Array in operations:
		match operation[0]:
			"save", "restore":
				out.append({"op": operation[0]})
			"transform":
				out.append({"op": "transform", "matrix": operation[1]})
			"fill_color", "stroke_color":
				out.append({"op": operation[0], "rgb": operation[1]})
			"line_width":
				out.append({"op": "line_width", "width": operation[1]})
			"fill_alpha":
				out.append({"op": "fill_alpha", "alpha": operation[1]})
			"path":
				out.append({"op": "path", "code": operation[1], "stroke": operation[2], "fill": operation[3],
						"even_odd": operation[4]})
			"image":
				out.append({"op": "image", "key": operation[1], "x": operation[2], "y": operation[3],
						"width": operation[4], "height": operation[5]})
			"text":
				var scratch := RecordingSurface.new(BookletWriter.A5)
				var grey := {}
				for position: float in operation[7]:
					grey[int(position)] = true
				var colors := {}
				for position: String in operation[9]:
					colors[int(position)] = _color(operation[9][position])
				var spacing: TextSpacing = null if operation[10] == null else TextSpacing.new(operation[10][0],
						operation[10][1])
				var outline: Variant = null if operation[11] == null else [_color(operation[11][0]), operation[11][1]]
				var face: FontFace = faces[operation[1]]
				face.draw(scratch, operation[2], operation[3], operation[4], operation[5], _color(operation[6]), grey,
						null if operation[8] == null else _color(operation[8]), colors, spacing, outline)
				out.append_array(scratch.pages[0])
	return out


## An image of the pack named by its path inside the pack, as Python names it.
static func _relative(operation: Dictionary, pack: BookletPack) -> Dictionary:
	if operation["op"] != "image" or not operation["key"].begins_with(pack.folder + "/"):
		return operation
	var named := operation.duplicate()
	named["key"] = operation["key"].trim_prefix(pack.folder + "/")
	return named


static func _color(rgb: Array) -> Color:
	return Color(rgb[0], rgb[1], rgb[2])


## Where ``actual`` first differs from ``expected``, numbers within TOLERANCE;
## "" when they agree.
static func _difference(expected: Variant, actual: Variant, path: String) -> String:
	if expected is Dictionary and actual is Dictionary:
		for key: Variant in expected:
			if not actual.has(key):
				return "%s: %s is missing" % [path, key]
			var found := _difference(expected[key], actual[key], "%s/%s" % [path, key])
			if not found.is_empty():
				return found
		for key: Variant in actual:
			if not expected.has(key):
				return "%s: %s is not expected" % [path, key]
		return ""
	if expected is Array and actual is Array:
		for index in mini(expected.size(), actual.size()):
			var found := _difference(expected[index], actual[index], "%s[%d]" % [path, index])
			if not found.is_empty():
				if expected[index] is Dictionary and not found.contains("\n"):
					return "%s\n    expected %s\n    drawn    %s" % [found, JSON.stringify(expected[index]).left(600),
							JSON.stringify(actual[index]).left(600)]
				return found
		if expected.size() != actual.size():
			return "%s: %d items, expected %d" % [path, actual.size(), expected.size()]
		return ""
	if (expected is float or expected is int) and (actual is float or actual is int):
		return "" if absf(float(expected) - float(actual)) <= TOLERANCE else "%s: %s, expected %s" % [path, actual,
				expected]
	if typeof(expected) == typeof(actual) and expected == actual:
		return ""
	return "%s: %s, expected %s" % [path, var_to_str(actual), var_to_str(expected)]
