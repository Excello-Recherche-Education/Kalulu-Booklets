extends GutTest
## Finding and loading the fonts (FontSet), and what the faces say. Ported from
## the Python generator's tests/test_fonts.py and test_vector.py. Its tests of
## the CFF to TrueType conversion have no port: ReportLab needed it, and the
## port's PDF embeds Mulish as it is (test_surfaces.gd).

const Tiny := preload("res://tests/helpers/tiny_pack.gd")

var pinned := ""


func before_each() -> void:
	pinned = FontSet.pinned_folder() if Tiny.fonts() != null else ""
	if pinned.is_empty():
		pending("kalulu-languages/ has no fonts/ at its pinned commit")


func after_all() -> void:
	Tiny.forget_all()


## A Kalulu-Languages-like folder: ``fonts/`` with the files given, and an
## empty pack folder beside it. Returns the pack folder.
func _checkout(files: Array) -> String:
	var root := ProjectSettings.globalize_path(Tiny.ROOT).path_join("fonts-%d" % Time.get_ticks_usec())
	for file: String in files:
		var target := root.path_join("fonts").path_join(file)
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		DirAccess.copy_absolute(pinned.path_join(file), target)
	DirAccess.make_dir_recursive_absolute(root.path_join("xx_XX"))
	return root.path_join("xx_XX")


func test_the_fonts_beside_the_pack_come_first() -> void:
	if pinned.is_empty():
		return
	var pack := _checkout(FontSet.DEFAULTS.values())
	assert_eq(FontSet.find(pack)["folder"], pack.get_base_dir().path_join("fonts"))


func test_without_them_the_pinned_ones_are_used() -> void:
	if pinned.is_empty():
		return
	var pack := _checkout([])
	assert_eq(FontSet.find(pack)["folder"], pinned)


func test_the_fallback_folder_replaces_the_pinned_one() -> void:
	if pinned.is_empty():
		return
	var other := _checkout(FontSet.DEFAULTS.values()).get_base_dir().path_join("fonts")
	assert_eq(FontSet.find(_checkout([]), {}, other)["folder"], other)
	# A pack with no folder (the Prof Tool's, before it is saved anywhere) uses it too.
	assert_eq(FontSet.find("", {}, other)["folder"], other)
	assert_string_contains(FontSet.find("", {}, "/nowhere")["error"], "/nowhere")


func test_a_missing_font_is_an_error() -> void:
	if pinned.is_empty():
		return
	var found := FontSet.find(_checkout([]), {"script": "nowhere/Nothing-Regular.ttf"})
	assert_eq(found["folder"], "")
	assert_string_contains(found["error"], "Kalulu-Languages keeps them in fonts/")


func test_marelle_joins_its_letters() -> void:
	if pinned.is_empty():
		return
	var faces := FontSet.from_folder(pinned)
	# Mulish prints each letter with its own glyph...
	assert_eq(faces.script_regular.shape("Il lit").size(), 6)
	# ...where Marelle's contextual alternates replace some of them inside a word.
	var joined := faces.cursive.shape("la lune").map(func(glyph: Array) -> int: return glyph[0])
	var alone: Array = []
	for letter in "la lune":
		alone.append(faces.cursive.shape(letter)[0][0])
	assert_ne(joined, alone)


func test_a_replacing_font_must_be_in_the_folder() -> void:
	if pinned.is_empty():
		return
	var pack := _checkout(FontSet.DEFAULTS.values())
	assert_eq(FontSet.find(pack, {"cursive": "marelle/Marelle2-Regular.ttf"})["folder"],
			pack.get_base_dir().path_join("fonts"))
	assert_string_contains(FontSet.find(pack, {"script": "andika/Andika-Regular.ttf"})["error"],
			"andika/Andika-Regular.ttf")


func test_a_replacing_font_prints_its_role() -> void:
	if pinned.is_empty():
		return
	var faces := FontSet.from_folder(pinned, {"cursive": "marelle/MarelleBaton-Regular.ttf"})
	assert_eq(faces.cursive.file, "marelle/MarelleBaton-Regular.ttf")
	assert_eq(faces.script_regular.file, FontSet.SCRIPT)
	assert_ne(faces.cursive.name, FontSet.from_folder(pinned).cursive.name)


func test_a_letter_a_font_lacks_is_noted_but_one_it_composes_is_not() -> void:
	if pinned.is_empty():
		return
	var faces := FontSet.from_folder(pinned, {"script_black": "marelle/Marelle2-Regular.ttf"})
	# Marelle has no precomposed "á": shaping prints it as "a" and an accent.
	faces.script_black.shape("canción")
	assert_true(faces.script_black.missing.is_empty())
	faces.script_black.shape("ŋa")
	assert_eq(faces.script_black.missing.keys(), ["ŋ"])
	assert_eq(Array(faces.missing_notes({"script_black": "Loops"})), [
		"the black script font, Loops (fonts/marelle/Marelle2-Regular.ttf), has no ŋ: printed as an empty box"])


func test_an_empty_text_has_no_glyphs() -> void:
	if pinned.is_empty():
		return
	var faces := FontSet.from_folder(pinned)
	assert_eq(faces.script_regular.shape(""), [])
	assert_eq(faces.script_regular.width("", 12.0), 0.0)


func test_ink_reaches_the_accents() -> void:
	if pinned.is_empty():
		return
	var faces := FontSet.from_folder(pinned)
	# An accented capital reaches higher than the capital alone, in both faces,
	# and Marelle's capitals higher than Mulish's: what title lines are spaced by.
	for face: FontFace in [faces.script_bold, faces.cursive]:
		assert_gt(face.ink("À")[0], face.ink("A")[0])
		assert_gt(face.ink("A")[0], 0.0)
	assert_gt(faces.cursive.ink("A")[0], faces.script_bold.ink("A")[0])
	assert_lt(faces.cursive.ink("g")[1], 0.0)


func test_the_cursive_is_marelle_2() -> void:
	assert_eq(FontSet.CURSIVE, "marelle/Marelle2-Regular.ttf")


func test_the_logo_keeps_its_translucent_cheeks() -> void:
	var opacities := {}
	for shape: Dictionary in BookletArt.vector("kalulu-logo").shapes:
		opacities[snappedf(shape["opacity"], 0.01)] = true
	var found := opacities.keys()
	found.sort()
	assert_eq(found, [0.2, 0.39, 1.0])
