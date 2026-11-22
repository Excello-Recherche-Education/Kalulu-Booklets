extends GutTest
## BookletWriter on fr_FR's first booklet: its A4 printing copy holds the
## pages in saddle-stitch order, and it writes PDF files.

## How far two numbers may differ: positions in points, colours in [0, 1].
const TOLERANCE := 0.001


func _packs_folder() -> String:
	return ProjectSettings.globalize_path("res://").path_join("../kalulu-languages").simplify_path()


## Draws an imposed copy of one booklet and checks every A4 side holds its two
## pages, each moved to its place.
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
