class_name DrawingSurface
extends RefCounted
## What the layout draws on: a page, in PDF points, origin at the bottom left,
## y up, as ReportLab's canvas. The layout never draws to a PDF directly, so the
## same code writes the booklet (PdfSurface), draws the Prof Tool's preview
## (CanvasSurface) and records what it drew for the parity checks
## (RecordingSurface).
##
## The operations are the list the prototype recorded from the Python
## generator, and nothing more:
## - save / restore / transform;
## - fill and stroke colour, line width, fill opacity;
## - path, with PDF's m l c h re operators, stroke or fill, even-odd or not;
## - image;
## - glyphs, placed one by one with a colour each, and an optional outline;
## - vector, a whole VectorArt drawing (paths, unless a surface does better).
##
## Every method here does nothing: a surface overrides what it draws.

var page_size: Vector2


func _init(size: Vector2) -> void:
	page_size = size


func save() -> void:
	pass


func restore() -> void:
	pass


## Concatenates [a, b, c, d, e, f] to the current transform, as PDF's ``cm``.
func transform(_matrix: Array) -> void:
	pass


func fill_color(_color: Color) -> void:
	pass


func stroke_color(_color: Color) -> void:
	pass


func line_width(_width: float) -> void:
	pass


func fill_alpha(_alpha: float) -> void:
	pass


## ``code``: [operator, numbers...] steps, with "m" (x y), "l" (x y),
## "c" (x1 y1 x2 y2 x3 y3), "h" () and "re" (x y width height).
func path(_code: Array, _stroke: bool, _fill: bool, _even_odd: bool = false) -> void:
	pass


## ``picture`` drawn ``width`` × ``height`` with its bottom left at (x, y).
## ``key`` names it, so a surface can keep it once however often it is drawn.
func image(_key: String, _picture: Image, _x: float, _y: float, _width: float, _height: float) -> void:
	pass


## ``placed``: [glyph index, x, y, colour, text, advance] each, positioned on
## the page; ``text`` is what the glyph stands for, for copying, and
## ``advance`` its advance in font units. ``outline``: [colour, width] strokes
## each glyph around its fill, or null.
func glyphs(_face: FontFace, _size: float, _placed: Array, _outline: Variant = null) -> void:
	pass


## ``art`` drawn ``width`` wide, its top left corner at (left, top).
func vector(art: VectorArt, left: float, top: float, width: float) -> void:
	art.draw_paths(self, left, top, width)


func end_page() -> void:
	pass
