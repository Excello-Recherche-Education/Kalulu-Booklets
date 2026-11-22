class_name FontSet
extends RefCounted
## The four faces a booklet prints with, by role: script (Mulish regular, bold
## and black, Kalulu's modified version) and cursive (Marelle 2). A language can
## replace any of them with a font of the same fonts folder (``BookletFonts``
## in the pack): ``load`` takes the replacements by role.
##
## The fonts are not kept here: they are Kalulu-Fonts, mounted at fonts/ in
## Kalulu-Languages and at res://fonts/ in the Prof Tool.

const SCRIPT := "mulish/kalulu_mulish_regular.otf"
const SCRIPT_BOLD := "mulish/kalulu_mulish_bold.otf"
const SCRIPT_BLACK := "mulish/kalulu_mulish_black.otf"
# Marelle 2: shorter loops, which do not run into the lines above and below in
# a paragraph (the PO's choice, 2026-11-09).
const CURSIVE := "marelle/Marelle2-Regular.ttf"

const ROLES: Array[String] = ["script", "script_bold", "script_black", "cursive"]
## What each role prints with unless the pack replaces it.
const DEFAULTS := {"script": SCRIPT, "script_bold": SCRIPT_BOLD, "script_black": SCRIPT_BLACK, "cursive": CURSIVE}
const DEFAULT_NAMES := {"script": "Mulish", "script_bold": "Mulish bold", "script_black": "Mulish black",
		"cursive": "Marelle 2"}
const ROLE_NAMES := {"script": "script", "script_bold": "bold script", "script_black": "black script",
		"cursive": "cursive"}

static var _loaded: Dictionary = {}  # folder and replacements -> FontSet

## The script face, regular (the "script" role; ``script`` is Object's own).
var script_regular: FontFace
var script_bold: FontFace
var script_black: FontFace
var cursive: FontFace


func _init(faces: Dictionary) -> void:
	script_regular = faces["script"]
	script_bold = faces["script_bold"]
	script_black = faces["script_black"]
	cursive = faces["cursive"]


func roles() -> Dictionary:
	return {"script": script_regular, "script_bold": script_bold, "script_black": script_black, "cursive": cursive}


## Kalulu-Booklets' own fonts: those of its pinned packs, kalulu-languages/fonts.
## Only there when running from a checkout of this repository.
static func pinned_folder() -> String:
	return ProjectSettings.globalize_path("res://").path_join("../kalulu-languages/fonts").simplify_path()


## The fonts of the Kalulu-Languages checkout ``pack_folder`` is in; failing
## that, those of ``fallback``: the pinned packs' when it is "" (this
## repository), res://fonts/ in the Prof Tool. The folder must hold every file
## the booklets print with: the defaults, and the files of ``replaced`` (role ->
## path inside fonts/) instead of those they replace. Returns {folder, error}.
static func find(pack_folder: String, replaced: Dictionary = {}, fallback: String = "") -> Dictionary:
	var files := DEFAULTS.duplicate()
	files.merge(replaced, true)
	var candidates: Array[String] = []
	if not pack_folder.is_empty():
		candidates.append(pack_folder.path_join("../fonts").simplify_path())
	candidates.append(fallback if not fallback.is_empty() else pinned_folder())
	for folder: String in candidates:
		if files.values().all(func(file: String) -> bool: return has_font(folder.path_join(file))):
			return {"folder": folder, "error": ""}
	var looked_for := "Mulish and Marelle"
	if not replaced.is_empty():
		var names: Array = []
		for file: String in files.values():
			if not names.has(file):
				names.append(file)
		looked_for = ", ".join(StableSort.sorted(names))
	return {"folder": "", "error": "no fonts folder with %s in %s -- Kalulu-Languages keeps them in fonts/"
			% [looked_for, " or ".join(candidates)]}


## The four faces, from ``folder``; ``replaced`` gives the path inside fonts/
## for each role the pack replaces. Loaded once per folder and replacements.
static func from_folder(folder: String, replaced: Dictionary = {}) -> FontSet:
	var key := "%s|%s" % [folder, JSON.stringify(replaced, "", true)]
	if not _loaded.has(key):
		var files := DEFAULTS.duplicate()
		files.merge(replaced, true)
		var faces := {}
		for role in ROLES:
			faces[role] = FontFace.new(font_bytes(folder.path_join(files[role])), files[role])
		_loaded[key] = FontSet.new(faces)
	return _loaded[key]


## Whether ``path`` is a font the booklets can print with (see font_bytes()).
static func has_font(path: String) -> bool:
	return FileAccess.file_exists(path) or (path.begins_with("res://") and ResourceLoader.exists(path))


## A font file's bytes: the file itself, or, in an exported project, where a
## font under res:// is there only as Godot imported it (the Prof Tool's
## res://fonts/), the imported font's copy of them, which is the same bytes.
static func font_bytes(path: String) -> PackedByteArray:
	if FileAccess.file_exists(path):
		return FileAccess.get_file_as_bytes(path)
	if path.begins_with("res://") and ResourceLoader.exists(path):
		var font := load(path) as FontFile
		if font != null:
			return font.data
	return PackedByteArray()


## Lets go of the faces loaded so far; the next from_folder() reads them again.
static func forget() -> void:
	_loaded.clear()


## What the build says about the characters a face met and cannot print.
## ``names`` gives the pack's name for a replaced role's font.
func missing_notes(names: Dictionary = {}) -> Array[String]:
	var notes: Array[String] = []
	var faces := roles()
	for role in ROLES:
		var face: FontFace = faces[role]
		if not face.missing.is_empty():
			var listed := " ".join(StableSort.sorted(face.missing.keys()))
			notes.append("the %s font, %s (fonts/%s), has no %s: printed as an empty box"
					% [ROLE_NAMES[role], names.get(role, DEFAULT_NAMES[role]), face.file, listed])
	return notes
