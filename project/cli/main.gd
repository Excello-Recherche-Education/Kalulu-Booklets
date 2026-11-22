extends Node
## The main scene: starts the command line (build_command.gd), or says why it
## cannot and quits.
##
## The generator's scripts find each other by their class names, which Godot
## reads from its class list in .godot/, written only by an import. After a pull
## that brings a new class, the list is out of date until the next import, the
## command line fails to compile, and Godot, left with no scene, would wait
## forever. So this script names no class: it loads the command line itself, and
## when that fails it prints what to run and exits.

const COMMAND := "res://cli/build_command.gd"
const REFRESH := "godot --headless --path project --import"


func _ready() -> void:
	var command: Script = load(COMMAND)
	if command == null or not command.can_instantiate():
		printerr("error: the project's class list is out of date (a new script since the last import).")
		printerr("Run tools/setup.sh, or: %s" % REFRESH)
		get_tree().quit(2)
		return
	# Its _ready() runs the build and quits with the build's exit code.
	add_child(command.new())
