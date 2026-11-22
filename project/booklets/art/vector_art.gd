class_name VectorArt
extends RefCounted
## The vector artwork of the booklets (the cover's logo and star), read from
## SVG and drawn as paths.
##
## These files use very little of SVG: filled <path> elements in absolute M, L,
## C and Z commands, each with a fill colour, a fill-rule and at times a
## fill-opacity, which is what this reads. A file using more is refused rather
## than drawn wrong.

const _SVG_NAMESPACE := "http://www.w3.org/2000/svg"
const _OPERANDS := {"M": 2, "L": 2, "C": 6, "Z": 0}

## Names the drawing, so a surface can keep a raster of it.
var key: String
## The SVG file's bytes, for surfaces that rasterise it.
var source: PackedByteArray
var width: float
var height: float
## {"color": Color, "opacity": float, "even_odd": bool, "commands": [[command, numbers...]...]}
## each, in the file's units, y pointing down.
var shapes: Array = []
## Why the file was refused, or "" when it was read.
var error := ""

static var _token: RegEx
static var _separators: RegEx


static func read(path: String) -> VectorArt:
	var art := VectorArt.new()
	art.key = path
	art.source = FileAccess.get_file_as_bytes(path)
	if art.source.is_empty():
		art.error = "%s: cannot be read" % path.get_file()
	else:
		art._parse(path.get_file())
	return art


## Draws it ``width`` wide, its top left corner at (left, top), as paths.
func draw(surface: DrawingSurface, left: float, top: float, drawn_width: float) -> void:
	surface.vector(self, left, top, drawn_width)


## What DrawingSurface.vector() does unless a surface draws it otherwise.
func draw_paths(surface: DrawingSurface, left: float, top: float, drawn_width: float) -> void:
	var scale := drawn_width / width
	surface.save()
	surface.transform([1.0, 0.0, 0.0, 1.0, left, top])
	surface.transform([scale, 0.0, 0.0, -scale, 0.0, 0.0])
	for shape: Dictionary in shapes:
		var code: Array = []
		for command: Array in shape["commands"]:
			match command[0]:
				"M":
					code.append(["m", command[1], command[2]])
				"L":
					code.append(["l", command[1], command[2]])
				"C":
					code.append(["c", command[1], command[2], command[3], command[4], command[5], command[6]])
				"Z":
					code.append(["h"])
		surface.fill_color(shape["color"])
		surface.fill_alpha(shape["opacity"])
		surface.path(code, false, true, shape["even_odd"])
	surface.restore()


func _parse(file_name: String) -> void:
	if _token == null:
		_token = RegEx.create_from_string("[MLCZ]|-?(?:\\d+\\.?\\d*|\\.\\d+)(?:[eE][-+]?\\d+)?")
		_separators = RegEx.create_from_string("[\\s,]")
	var parser := XMLParser.new()
	parser.open_buffer(source)
	var seen_root := false
	while parser.read() == OK:
		if parser.get_node_type() != XMLParser.NODE_ELEMENT:
			continue
		var tag := parser.get_node_name()
		if not seen_root:
			seen_root = true
			if tag != "svg" or parser.get_named_attribute_value_safe("xmlns") != _SVG_NAMESPACE:
				error = "%s: not an SVG drawing" % file_name
				return
			var box := parser.get_named_attribute_value_safe("viewBox").split(" ", false)
			if box.size() != 4:
				error = "%s: no viewBox" % file_name
				return
			if float(box[0]) != 0.0 or float(box[1]) != 0.0:
				error = "%s: a viewBox not starting at 0 0" % file_name
				return
			width = float(box[2])
			height = float(box[3])
			continue
		if tag != "path":
			error = "%s: <%s> is not read" % [file_name, tag]
			return
		var commands := _commands(file_name, parser.get_named_attribute_value_safe("d"))
		if commands.is_empty() and not error.is_empty():
			return
		var fill := parser.get_named_attribute_value_safe("fill")
		var opacity := parser.get_named_attribute_value_safe("fill-opacity")
		shapes.append({
			"color": Color.html(fill if not fill.is_empty() else "#000000"),
			"opacity": float(opacity) if not opacity.is_empty() else 1.0,
			"even_odd": parser.get_named_attribute_value_safe("fill-rule") == "evenodd",
			"commands": commands,
		})


func _commands(file_name: String, d: String) -> Array:
	var tokens: Array[String] = []
	for found in _token.search_all(d):
		tokens.append(found.get_string())
	if "".join(tokens) != _separators.sub(d, "", true):
		error = "%s: a path command this does not read in \"%s\"" % [file_name, d.left(40)]
		return []
	var commands: Array = []
	var index := 0
	while index < tokens.size():
		var command := tokens[index]
		if not _OPERANDS.has(command):
			error = "%s: a number where a command was expected in \"%s\"" % [file_name, d.left(40)]
			return []
		var count: int = _OPERANDS[command]
		var operands := tokens.slice(index + 1, index + 1 + count)
		if operands.size() != count or operands.any(func(operand: String) -> bool: return _OPERANDS.has(operand)):
			error = "%s: %s needs %d numbers in \"%s\"" % [file_name, command, count, d.left(40)]
			return []
		var step: Array = [command]
		for operand in operands:
			step.append(float(operand))
		commands.append(step)
		index += 1 + count
	return commands
