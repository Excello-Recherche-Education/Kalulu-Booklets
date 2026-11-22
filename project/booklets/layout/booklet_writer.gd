class_name BookletWriter
extends RefCounted
## Draws a laid out booklet on a DrawingSurface: its pages with their numbers,
## and, for printing, its A4 sheets. ``pdf()`` writes it as a PDF file's bytes.
##
## Ported from the Python generator (``layout.write()``), removed once a
## release built by this one matched it page for page.

const A4_LANDSCAPE := Vector2(297.0 * BookletLayout.MM, 210.0 * BookletLayout.MM)
const A5 := Vector2(BookletLayout.PAGE_WIDTH, BookletLayout.PAGE_HEIGHT)


## The layout a version is made with: an adapted version's own, or the base one.
static func layout_for(booklet: BookletContent.Booklet, fonts: FontSet, version: BookletVersion = null,
		chosen: Variant = null) -> BookletLayout:
	if version != null and not version.adapted.is_empty():
		return AdaptedLayout.new(booklet, fonts, version, chosen)
	return BookletLayout.new(booklet, fonts, version, chosen)


## Lays out ``booklet`` in ``version`` and draws its pages on ``surface``, one
## after the other; returns the layout, whose ``pages`` say how many. Call its
## ``release()`` when done with them.
static func draw(surface: DrawingSurface, booklet: BookletContent.Booklet, fonts: FontSet,
		version: BookletVersion = null, chosen: Variant = null) -> BookletLayout:
	var laid_out := layout_for(booklet, fonts, version, chosen)
	var pages := laid_out.run()
	var numbers := folios(pages)
	for index in pages.size():
		draw_page(surface, pages[index], numbers[index], laid_out)
		surface.end_page()
	return laid_out


## The same pages for printing: A4 landscape, two pages a sheet, in
## saddle-stitch order (the last and the first, then the second and the
## second-to-last...), so that the printed sheets, folded and stapled, read in
## order. ``surface`` is A4 landscape.
static func draw_imposed(surface: DrawingSurface, laid_out: BookletLayout) -> void:
	var numbers := folios(laid_out.pages)
	for sheet_side: Array in sheet_sides(laid_out.pages.size()):
		for placed: Array in sheet_side:
			surface.save()
			surface.transform([1.0, 0.0, 0.0, 1.0, placed[1], 0.0])
			draw_page(surface, laid_out.pages[placed[0]], numbers[placed[0]], laid_out)
			surface.restore()
		surface.end_page()


## The booklet as PDF files' bytes: the A5 booklet, then, when ``imposed``,
## its A4 printing copy (an empty array otherwise). [a5, a4].
static func pdf(booklet: BookletContent.Booklet, fonts: FontSet, version: BookletVersion = null,
		imposed: bool = false, chosen: Variant = null) -> Array[PackedByteArray]:
	var info := info_for(booklet, version)
	var surface := PdfSurface.new(A5, info)
	var laid_out := draw(surface, booklet, fonts, version, chosen)
	var printed := PackedByteArray()
	if imposed:
		var sheets := PdfSurface.new(A4_LANDSCAPE, info)
		draw_imposed(sheets, laid_out)
		printed = sheets.finish()
	laid_out.release()
	return [surface.finish(), printed]


## Lays out and writes one booklet in one version to ``path``, and, given
## ``imposed_path``, its A4 printing copy there; returns its number of pages,
## or -1 when a file cannot be written. Folders are made as needed.
static func write(booklet: BookletContent.Booklet, fonts: FontSet, path: String, version: BookletVersion = null,
		imposed_path: String = "", chosen: Variant = null) -> int:
	var info := info_for(booklet, version)
	var surface := PdfSurface.new(A5, info)
	var laid_out := draw(surface, booklet, fonts, version, chosen)
	var count := laid_out.pages.size()
	var written := _save(path, surface.finish())
	if written and not imposed_path.is_empty():
		var sheets := PdfSurface.new(A4_LANDSCAPE, info)
		draw_imposed(sheets, laid_out)
		written = _save(imposed_path, sheets.finish())
	laid_out.release()
	return count if written else -1


static func _save(path: String, bytes: PackedByteArray) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(bytes)
	file.close()
	return true


## The PDF's document information.
static func info_for(booklet: BookletContent.Booklet, version: BookletVersion) -> Dictionary:
	var suffix := "" if version == null or version.name == "base" else " - " + version.name
	return {"Title": "Kalulu - %s - %d%s" % [booklet.locale, booklet.number, suffix],
			"Author": "Excello Recherche & Education", "Subject": "Kalulu reading booklet"}


static func draw_page(surface: DrawingSurface, page: BookletLayout.Page, folio: int, laid_out: BookletLayout) -> void:
	for step in page.steps:
		surface.save()
		step.call(surface)
		surface.restore()
	if page.numbered:
		laid_out.draw_folio(surface, folio)


## Each A4 side's two pages (0-based) with how far from the sheet's left edge
## each is drawn: two A5 pages are 296 mm across a 297 mm sheet, so the pair
## is centred, and the fold falls in the middle on both sides. [[left, shift],
## [right, shift]] each.
static func sheet_sides(count: int) -> Array:
	var margin := (A4_LANDSCAPE.x - 2.0 * BookletLayout.PAGE_WIDTH) / 2.0
	var sides: Array = []
	for pair: Array in imposition(count):
		sides.append([[pair[0], margin], [pair[1], margin + BookletLayout.PAGE_WIDTH]])
	return sides


## The pages (0-based) on each side of each A4 sheet, left then right, for a
## booklet of ``count`` pages, a multiple of four.
static func imposition(count: int) -> Array:
	var sides: Array = []
	@warning_ignore("integer_division")
	var side_count := count / 2
	for side in side_count:
		sides.append([count - 1 - side, side] if side % 2 == 0 else [side, count - 1 - side])
	return sides


## Each page's number, counting the cover as 1. A teacher's page takes the
## number of the page after it and is not counted.
static func folios(pages: Array) -> Array[int]:
	var numbers: Array[int] = []
	numbers.resize(pages.size())
	var number := 0
	for index in pages.size():
		if not pages[index].shares_next_number:
			number += 1
			numbers[index] = number
	for index in range(pages.size() - 1, -1, -1):
		if pages[index].shares_next_number:
			numbers[index] = numbers[index + 1] if index + 1 < pages.size() else number + 1
	return numbers
