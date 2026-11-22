class_name BookletVersion
extends RefCounted
## The versions of a booklet: the same content, printed for different readers.
##
## Every version is derived from the base booklet's chapters; none needs
## content of its own (Kalulu-Main's docs/BOOKLETS-FROM-PACKS.md, "The
## versions"). What they change is how the pages are made:
##
## - **base**: the booklet itself;
## - **teacher**: before each chapter, a page with its title and its picture
##   (the pack's own booklet image the chapter's ``ImageID`` names, else the
##   Look & Learn image of its ``ImageGPID``), carrying the same page number as
##   the chapter page, so a teacher's copy and a pupil's agree;
## - **no-writing**: without its writing pages;
## - **dyslexia**, **dyspraxia**, **adhd**: the "versions différenciées" of
##   the examples, for pupils with those difficulties: bigger and airier text, a
##   chapter over several pages, a fluency test in 3 columns, an "adaptations"
##   page saying what was changed; dyspraxia also prints everything but its
##   writing pages in script, dyspraxia and adhd colour the multi-letter
##   graphemes, and adhd draws no animal.
##
## A language says which versions it prints besides the base booklet, and
## whether in a script series, a cursive series or both (Kalulu-Languages
## SCHEMA.md, ``BookletSettings``; BookletPack.versions() and series()).
##
## The base and no-writing versions are also written for printing: A4
## landscape, two A5 pages a sheet, in the order a folded and stapled booklet
## reads them.

var name: String
## A line under the cover's star, in its colour, by the pack's language (the
## locale's first part); none for the base booklet. French is the examples';
## the others are translations to have checked, and a language missing here
## gets the French.
var labels: Dictionary = {}
var label_color: Variant = null  # Color, or null
## In bold, as the examples print the teacher's; else regular.
var label_bold := false
var writing := true
var teacher := false
## Made up to a multiple of four pages with blank ones, for folded sheets.
var folded := true
## Also written as A4 sheets, imposed for a folded booklet.
var printed := false
## An adapted version's style; "" for the base layout.
var adapted := ""
## The adaptations page's rows ticked, and who the version is advised for, by
## language.
var adaptations: Array = []
var readers: Dictionary = {}

## Every adapted version makes the text bigger and airier.
const _AIRIER: Array[String] = ["font", "word spacing", "letter spacing", "line spacing"]
## The examples' "Version différenciée", each in its colour.
const _ADAPTED := {"fr": "Version différenciée", "es": "Versión diferenciada", "pt": "Versão diferenciada"}

## Name -> BookletVersion, in the order Python lists them.
static var _versions: Dictionary = {}


func _init(version_name: String, options: Dictionary = {}) -> void:
	name = version_name
	for key: String in options:
		set(key, options[key])


func label(locale: String) -> String:
	return labels.get(locale.split("_")[0], labels.get("fr", ""))


## ``series`` ("script", "cursive") is named only for a language that prints
## both: its two series sit side by side in each version's folder.
func file_name(locale: String, number: int, imposed: bool = false, series: String = "") -> String:
	var suffix := "" if name == "base" else "-" + name
	var series_suffix := "-" + series if not series.is_empty() else ""
	return "%s-booklet-%d%s%s%s.pdf" % [locale, number, suffix, series_suffix, "-print" if imposed else ""]


## Every version, by name: base, teacher, no-writing, dyslexia, dyspraxia, adhd.
static func all() -> Dictionary:
	if _versions.is_empty():
		for version in [
			BookletVersion.new("base", {"printed": true}),
			BookletVersion.new("teacher", {
				"labels": {"fr": "Version enseignant", "es": "Versión docente", "pt": "Versão do professor"},
				"label_color": Color.html("#29367e"), "label_bold": true, "teacher": true, "folded": false}),
			BookletVersion.new("no-writing", {"writing": false, "printed": true}),
			BookletVersion.new("dyslexia", {"labels": _ADAPTED, "label_color": Color.html("#f7931d"),
				"adapted": "dyslexia", "adaptations": _AIRIER, "readers": {"fr": "aux élèves dyslexiques"}}),
			BookletVersion.new("dyspraxia", {"labels": _ADAPTED, "label_color": Color.html("#24aae1"),
				"adapted": "dyspraxia",
				"adaptations": _AIRIER + ["fewer items", "graphemes coloured", "silent letters coloured", "script only"],
				"readers": {"fr": "aux élèves dyspraxiques"}}),
			BookletVersion.new("adhd", {"labels": _ADAPTED, "label_color": Color.html("#dc96c2"), "adapted": "adhd",
				"adaptations": _AIRIER + ["fewer items", "graphemes coloured", "silent letters coloured"],
				"readers": {"fr": "aux élèves avec des troubles de l’attention"}}),
		]:
			_versions[version.name] = version
	return _versions


static func named(version_name: String) -> BookletVersion:
	return all().get(version_name)
