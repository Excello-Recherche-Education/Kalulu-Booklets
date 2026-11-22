class_name BookletArt
extends RefCounted
## The pictures the booklets draw: the game's characters and the cover's
## drawings, in ``art/`` beside the generator (art/LICENSE.md says where each
## comes from), and the pack's own pictures for the teacher's pages.
##
## Pictures are read from their files' bytes, not imported as textures, so the
## PDF gets the file's pixels as they are. An exported project carries an
## imported texture instead of the file: whoever exports one must include
## ``booklets/art/*`` (the Prof Tool's presets do).

const FOLDER := "res://booklets/art"

static var _pictures: Dictionary = {}
static var _vectors: Dictionary = {}


## One of the characters: "parakeet", "penguin", "caterpillar".
static func picture(name: String) -> Image:
	if not _pictures.has(name):
		_pictures[name] = picture_at(FOLDER.path_join(name + ".png"))
	return _pictures[name]


## The PNG or JPEG at ``path``; an empty image when it cannot be read.
static func picture_at(path: String) -> Image:
	var bytes := FileAccess.get_file_as_bytes(path)
	var image := Image.new()
	if bytes.size() >= 3 and bytes[0] == 0xFF and bytes[1] == 0xD8 and bytes[2] == 0xFF:
		image.load_jpg_from_buffer(bytes)
	else:
		image.load_png_from_buffer(bytes)
	return image


## One of the cover's drawings: "kalulu-logo", "cover-star".
static func vector(name: String) -> VectorArt:
	if not _vectors.has(name):
		_vectors[name] = VectorArt.read(FOLDER.path_join(name + ".svg"))
	return _vectors[name]


## Lets go of the pictures read so far.
static func forget() -> void:
	_pictures.clear()
	_vectors.clear()
