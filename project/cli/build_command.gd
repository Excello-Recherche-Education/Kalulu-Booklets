extends Node
## The command line: the project's main scene, so that
##
##     godot --headless --no-header --path project -- build fr_FR
##     godot --headless --no-header --path project -- build ../Kalulu-Languages/fr_FR
##     godot --headless --no-header --path project -- build fr_FR --booklet 1 --out /tmp/booklets
##     godot --headless --no-header --path project -- build fr_FR --version teacher
##
## writes the booklets of one pack as PDF files (BookletBuild), and quits with
## its exit code: 0 done, 1 nothing to build, 2 refused.
##
## ``pack`` is a locale of kalulu-languages/ (fr_FR), a pack folder, or its
## language.db. ``--booklet`` and ``--version`` may be repeated; by default
## every booklet, in every version the language prints. ``--out`` defaults to
## build/ at the repository's root. Godot runs from the project folder, so a
## relative path is taken from the folder the command was typed in ($PWD).

const USAGE := "usage: godot --headless --no-header --path project -- build <pack> [--booklet N]... [--version V]... [--out DIR]"


func _ready() -> void:
	var code := run(OS.get_cmdline_user_args())
	# The faces and pictures kept for the next build, let go of before Godot
	# counts what is still held at exit.
	FontSet.forget()
	BookletArt.forget()
	get_tree().quit(code)


func run(arguments: PackedStringArray) -> int:
	if arguments.is_empty() or arguments[0] in ["-h", "--help"]:
		print(USAGE)
		return 0 if not arguments.is_empty() else 2
	if arguments[0] != "build":
		printerr(USAGE)
		printerr("error: unknown command %s; the only one is build" % arguments[0])
		return 2
	var pack := ""
	var numbers: Array[int] = []
	var versions: Array[String] = []
	var out := ""
	var index := 1
	while index < arguments.size():
		var argument := arguments[index]
		if argument in ["--booklet", "--version", "--out"]:
			if index + 1 >= arguments.size():
				printerr(USAGE)
				printerr("error: argument %s: expected one argument" % argument)
				return 2
			var value := arguments[index + 1]
			index += 2
			match argument:
				"--booklet":
					if not value.is_valid_int():
						printerr(USAGE)
						printerr("error: argument --booklet: invalid int value: '%s'" % value)
						return 2
					numbers.append(int(value))
				"--version":
					if BookletVersion.named(value) == null:
						printerr(USAGE)
						printerr("error: argument --version: invalid choice: '%s' (choose from %s)"
								% [value, ", ".join(BookletVersion.all().keys())])
						return 2
					versions.append(value)
				"--out":
					out = value
			continue
		if argument.begins_with("-") or not pack.is_empty():
			printerr(USAGE)
			printerr("error: unrecognized argument: %s" % argument)
			return 2
		pack = argument
		index += 1
	if pack.is_empty():
		printerr(USAGE)
		printerr("error: the following arguments are required: pack")
		return 2
	var repository := ProjectSettings.globalize_path("res://").path_join("..").simplify_path()
	var shown_out := out.simplify_path() if not out.is_empty() else repository.path_join("build")
	return BookletBuild.new().build(pack_path(pack), numbers, versions, absolute(shown_out), shown_out)


## A bare locale means the pack pinned in kalulu-languages/.
static func pack_path(argument: String) -> String:
	var path := absolute(argument)
	var pinned := ProjectSettings.globalize_path("res://").path_join("../kalulu-languages").simplify_path()
	if not FileAccess.file_exists(path) and not DirAccess.dir_exists_absolute(path) and not argument.contains("/") \
			and DirAccess.dir_exists_absolute(pinned.path_join(argument)):
		return pinned.path_join(argument)
	return path


## ``path`` from the folder the command was typed in.
static func absolute(path: String) -> String:
	if path.begins_with("~"):
		path = OS.get_environment("HOME") + path.substr(1)
	if path.is_absolute_path():
		return path.simplify_path()
	var here := OS.get_environment("PWD")
	if here.is_empty():
		here = ProjectSettings.globalize_path("res://").path_join("..")
	return here.path_join(path).simplify_path()
