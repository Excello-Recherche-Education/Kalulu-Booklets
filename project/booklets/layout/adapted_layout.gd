class_name AdaptedLayout
extends BookletLayout
## The adapted versions' layout: dyslexia, dyspraxia and adhd ("versions
## différenciées", BookletVersion).
##
## They print the base booklet's content (a chapter that picks no sentence
## prints the ones the base booklet chose for it) bigger and airier, measured
## on the printed examples (Kalulu-Main's docs/booklet-versions/):
##
## - script text 20 or 24 pt, with letter and word spacing; cursive is never
##   spaced out, its letters are joined;
## - a chapter over several pages: the title, the syllables and as many words
##   as fit, then the words left, then the sentences on pages of their own, a
##   sentence block never split across two pages;
## - words in two columns or one per line, centred;
## - the multi-letter graphemes coloured, and every silent letter grey
##   (dyspraxia, adhd);
## - the fluency test's items in 3 columns, on as many pages of 3 × 4 as they
##   take (the PO's rule, 2026-11-03);
## - a sentence table one column per page;
## - writing pages on a wider ruling, the copies drawn as outlines to trace
##   over, in dyspraxia too: its only cursive (the PO's rule, 2026-11-03);
## - no animal drawn in adhd: no penguin above the tables, no caterpillar on the
##   writing pages;
## - the page number bottom right, and an "adaptations" page before the back
##   cover saying what this version changes.
##
## Every measurement is a baseline-to-baseline distance or a position from the
## page's top or left edge, in millimetres, as the reports give them.
##
## A port of the Python generator's ``adapted.py``.

const ADAPTED_SILENT := Color(0x7f / 255.0, 0x7f / 255.0, 0x7f / 255.0)
const TINTS := {
	BookletContent.OWN: Color(0xf3 / 255.0, 0xb2 / 255.0, 0x67 / 255.0),
	BookletContent.EARLIER: Color(0x3d / 255.0, 0x32 / 255.0, 0x9f / 255.0),
	BookletContent.TOUCHING: Color(0x9c / 255.0, 0x48 / 255.0, 0x4c / 255.0),
}
## The writing pages' ruling: fine blue lines, main grey ones, grey verticals.
const RULE_FINE := Color(0xb2 / 255.0, 0xd1 / 255.0, 0xed / 255.0)
const RULE_MAIN := Color(0x7f / 255.0, 0x7f / 255.0, 0x7f / 255.0)
const COPY_FILL := Color(0xbf / 255.0, 0xbf / 255.0, 0xbf / 255.0)
const COPY_EDGE := Color(0xa4 / 255.0, 0xa3 / 255.0, 0xa4 / 255.0)

const TEXT_LEFT := 12.7 * MM
const TEXT_RIGHT := 135.5 * MM
const TEXT_WIDTH := TEXT_RIGHT - TEXT_LEFT
## The grids' columns: equal cells across 127 mm, each item centred in its own.
const GRID_LEFT := 10.5 * MM
const GRID_WIDTH := 127.0 * MM

const STYLES := {
	"dyslexia": {
		"size": 20.0, "cursive_size": 20.0 * CURSIVE_SENTENCE_SIZE / SENTENCE_SIZE, "cursive": true, "tinted": false,
		"all_silent": false, "one_sentence_a_line": false, "title_sizes": {1: 36.0, 2: 30.0, 3: 26.0, 4: 26.0, 5: 26.0},
		"first": 20.8, "last": 194.0, "line": 9.9, "cursive_line": 11.6, "block": 25.0, "after_title": 20.4,
		"syllable_row": 12.0, "after_syllables": 20.8, "word_row": 10.9, "word_centres": [2.0 / 7.0, 5.0 / 7.0],
		"table_row": 15.4, "table_cells": 19.3, "story_size": 18.0, "story_title_size": 20.0, "story_line": 8.8,
		"story_paragraph": 17.6, "fluency_size": 24.0, "animals": true},
	"dyspraxia": {
		"size": 24.0, "cursive_size": 24.0, "cursive": false, "tinted": true, "all_silent": true,
		"one_sentence_a_line": true, "title_sizes": {1: 40.0, 2: 36.0, 3: 30.0, 4: 30.0, 5: 30.0}, "first": 22.0,
		"last": 186.0, "line": 17.6, "cursive_line": 17.6, "block": 42.3, "after_title": 27.5, "syllable_row": 19.8,
		"after_syllables": 32.1, "word_row": 19.8, "word_centres": [1.0 / 2.0], "table_row": 25.0,
		"table_cells": 42.3, "story_size": 24.0, "story_title_size": 24.0, "story_line": 17.6,
		"story_paragraph": 35.3, "fluency_size": 24.0, "animals": true},
	"adhd": {
		"size": 24.0, "cursive_size": 24.0 * CURSIVE_SENTENCE_SIZE / SENTENCE_SIZE, "cursive": true, "tinted": true,
		"all_silent": true, "one_sentence_a_line": false, "title_sizes": {1: 40.0, 2: 36.0, 3: 30.0, 4: 30.0, 5: 30.0},
		"first": 22.0, "last": 186.0, "line": 17.6, "cursive_line": 17.6, "block": 42.3, "after_title": 27.0,
		"syllable_row": 19.75, "after_syllables": 32.0, "word_row": 19.75, "word_centres": [1.0 / 2.0],
		"table_row": 25.0, "table_cells": 42.3, "story_size": 24.0, "story_title_size": 24.0, "story_line": 17.6,
		"story_paragraph": 35.3, "fluency_size": 24.0, "animals": false},
}

## The most columns for which the widest syllable fits its cell with 0.3 em to
## spare: the printed booklets keep "coi cou" in 6 and put "vou mou" in 4.
const SYLLABLE_COLUMNS: Array[int] = [6, 4, 3]
const SYLLABLE_SPARE := 0.3

## The fluency test: 3 columns of 4 rows a page, in a rounded box.
const ADAPTED_FLUENCY_COLUMNS: Array[float] = [29.5, 74.0, 118.6]  # centres, from the left
const FLUENCY_ROWS: Array[float] = [63.1, 93.0, 123.0, 153.0]  # baselines, from the top
const FLUENCY_BOX: Array[float] = [4.2, 35.8, 143.8, 174.2]  # left, top, right, bottom
const ADAPTED_STOPWATCH := 9.5
const STOPWATCH_TOP := 184.0  # the first one's centre, below the box

## The writing pages: main lines every 15.93 mm, four fine intervals between
## them; a model row on every other main line; verticals every 15.95 mm.
const RULE_INTERVAL := 15.93 / 4.0
const RULE_MAIN_TOP := 31.9
const RULE_MAINS := 11
const RULE_LEFT := 4.5
const RULE_RIGHT := 142.4
const VERTICAL_FIRST := 20.6
const VERTICAL_STEP := 15.95
const MODEL_LEFT := 21.3
const COPY_ROOM := 6.0  # the least room before the next copy
const ADAPTED_CATERPILLAR_HEIGHT := 9.0

const ADAPTED_FOLIO_SIZE := 14.0
const FOLIO_RIGHT := 138.5
const FOLIO_BASELINE := 200.5

## The adaptations page (the examples' text), by language. A language missing
## here has no such page, and the build says so.
const ADAPTATIONS: Array[String] = ["font", "word spacing", "letter spacing", "line spacing", "fewer items",
		"graphemes coloured", "silent letters coloured", "script only"]
const ADAPTATIONS_TEXT := {
	"fr": {
		"intro": "Ce livret différencié est conçu pour répondre à certains symptômes fréquents des troubles de "
				+ "l’apprentissage. Il existe plusieurs versions des livrets différenciés, chaque version répond à "
				+ "des symptômes différents. Ce livret suit les adaptations suivantes :",
		"heading": "Adaptation :",
		"rows": {
			"font": "Augmentation de la police",
			"word spacing": "Augmentation de l’espacement entre les mots",
			"letter spacing": "Augmentation de l’espacement entre les lettres",
			"line spacing": "Augmentation de l’interligne",
			"fewer items": "Réduction du nombre d’items par page",
			"graphemes coloured": "Coloration des digrammes et trigrammes",
			"silent letters coloured": "Coloration des graphèmes silencieux",
			"script only": "Utiliser uniquement une police script",
		},
		"closing": ["Si on suit les données scientifiques sur le sujet, nous conseillons ces adaptations {readers}.",
				"N’hésitez pas à nous envoyer vos commentaires à contact@excellolab.org."],
	},
}
const ADAPTATIONS_SIZE := 11.0
const ADAPTATIONS_LINE := 6.2
const ADAPTATIONS_ROW := 8.5


## A printed line of a block.
class Line:
	var face: FontFace
	var size: float
	var words: Array
	var spacing: TextSpacing
	var pitch: float  # from the line above, in a block
	var centred: bool

	func _init(line_face: FontFace, line_size: float, line_words: Array, line_spacing: TextSpacing,
			line_pitch: float, is_centred: bool = false) -> void:
		face = line_face
		size = line_size
		words = line_words
		spacing = line_spacing
		pitch = line_pitch
		centred = is_centred


## Script only: +0.12 em after every letter, and a space of 0.52 em in all.
var adapted_spacing := TextSpacing.new(0.12, 0.52)
var style: Dictionary
## The last baseline placed on this page, or null.
var baseline: Variant = null


func _init(laid_out: BookletContent.Booklet, faces: FontSet, booklet_version: BookletVersion = null,
		chosen_sentences: Variant = null) -> void:
	super(laid_out, faces, booklet_version, chosen_sentences)
	style = STYLES[version.adapted]
	if chosen_sentences == null:
		# The sentences the base booklet chose, laid out apart so its notes are
		# not said twice.
		var notes := booklet.notes.duplicate()
		var base := BookletLayout.new(booklet, fonts, BookletVersion.named("base"))
		base.run()
		booklet.notes.assign(notes)
		chosen = base.chosen


## A height ``millimetres`` from the top of the page.
static func from_top(millimetres: float) -> float:
	return PAGE_HEIGHT - millimetres * MM


# --- Pages -------------------------------------------------------------------------

func new_page(numbered: bool = true, shares_next_number: bool = false) -> Page:
	var made := super(numbered, shares_next_number)
	baseline = null
	return made


## The baseline of something ``gap`` below the last one placed (the page's
## first baseline on a fresh page), reaching ``below`` further down with its
## other lines; on a new page when it does not fit here.
func place(gap: float, below: float = 0.0) -> float:
	var last := from_top(style["last"])
	if baseline != null:
		var first: float = baseline - gap
		if first - below >= last:
			baseline = first - below
			return first
		new_page()
	var first := from_top(style["first"])
	baseline = first - below
	return first


func draw_folio(surface: DrawingSurface, number: int) -> void:
	var text := str(number)
	var face := fonts.script_regular
	face.draw(surface, FOLIO_RIGHT * MM - face.width(text, ADAPTED_FOLIO_SIZE), from_top(FOLIO_BASELINE), text,
			ADAPTED_FOLIO_SIZE, INK)


func run() -> Array[Page]:
	cover()
	for chapter in booklet.chapters:
		lay_chapter(chapter)
	var text: Variant = ADAPTATIONS_TEXT.get(booklet.locale.split("_")[0])
	if text == null:
		booklet.notes.append(("the %s version has no adaptations page in this language: its text is to be "
				+ "written (adapted.ADAPTATIONS_TEXT)") % version.name)
	# The adaptations page and the back cover close the last folded sheet.
	while (pages.size() + (2 if text != null else 1)) % 4 != 0:
		new_page(false)
	if text != null:
		adaptations(text)
	back_cover()
	return pages


# --- Text --------------------------------------------------------------------------

func face_for(font: String) -> FontFace:
	return fonts.cursive if font == BookletContent.CURSIVE and style["cursive"] else fonts.script_regular


func font_of(font: String) -> String:
	return BookletContent.CURSIVE if font == BookletContent.CURSIVE and style["cursive"] else BookletContent.SCRIPT


func spacing_for(face: FontFace) -> TextSpacing:
	return null if face == fonts.cursive else adapted_spacing


## The letters printed grey, and the colours of the others.
func marks(item: BookletContent.Styled) -> Array:
	var grey: Dictionary = item.silent if style["all_silent"] else item.grey
	var colors := {}
	if style["tinted"]:
		for tint: Array in item.tints:
			for index in range(tint[0], tint[1]):
				colors[index] = TINTS[tint[2]]
	return [grey, colors]


func draw_text(surface: DrawingSurface, face: FontFace, x: float, y: float, item: BookletContent.Styled,
		size: float, tinted: bool = true) -> float:
	var marked := marks(item)
	return face.draw(surface, x, y, item.text, size, INK, marked[0], ADAPTED_SILENT, marked[1] if tinted else {},
			spacing_for(face))


func spaced_width(face: FontFace, text: String, size: float) -> float:
	return face.width(text, size, spacing_for(face))


func draw_block_line(surface: DrawingSurface, line: Line, line_baseline: float, left: float = TEXT_LEFT,
		width: float = TEXT_WIDTH) -> void:
	var space := line.face.width(" ", line.size, line.spacing)
	var total := 0.0
	for word: BookletContent.Styled in line.words:
		total += spaced_width(line.face, word.text, line.size)
	total += space * (line.words.size() - 1)
	var x := left + (width - total) / 2.0 if line.centred else left
	for word: BookletContent.Styled in line.words:
		x += draw_text(surface, line.face, x, line_baseline, word, line.size) + space


## ``pieces`` (lines of sentences sharing them) wrapped at ``width``.
func lines_of(font: String, pieces: Array, size: float = 0.0, centred: bool = false, width: float = TEXT_WIDTH,
		pitch: float = 0.0) -> Array[Line]:
	font = font_of(font)
	var face := face_for(font)
	if size == 0.0:
		size = style["cursive_size"] if font == BookletContent.CURSIVE else style["size"]
	if pitch == 0.0:
		pitch = (style["cursive_line"] if font == BookletContent.CURSIVE else style["line"]) * MM
	var spacing := spacing_for(face)
	var out: Array[Line] = []
	for words: Array in wrap_lines(face, BookletContent.Paragraph.new(font, pieces), size, width, spacing):
		out.append(Line.new(face, size, words, spacing, pitch, centred))
	return out


## A block of lines on one page, never split; one taller than a page runs over,
## as in the printed booklets.
func put_block(_content: BookletContent.ChapterContent, lines: Array[Line], gap: float, left: float = TEXT_LEFT,
		width: float = TEXT_WIDTH) -> void:
	if lines.is_empty():
		return
	var below := 0.0
	for line in lines.slice(1):
		below += line.pitch
	if below > from_top(style["first"]) - from_top(style["last"]):
		for index in lines.size():
			var line := lines[index]
			var line_baseline := place(gap if index == 0 else line.pitch)
			add(func(surface: DrawingSurface) -> void: draw_block_line(surface, line, line_baseline, left, width))
		return
	var first := place(gap, below)
	var baselines: Array[float] = [first]
	for line in lines.slice(1):
		baselines.append(baselines[-1] - line.pitch)
	add(func(surface: DrawingSurface) -> void:
		for index in lines.size():
			draw_block_line(surface, lines[index], baselines[index], left, width))


# --- A chapter ---------------------------------------------------------------------

func lay_chapter(content: BookletContent.ChapterContent) -> void:
	if content.has_chapter_page():
		new_page()
	if not content.title.is_empty():
		y = from_top(17.0)
		baseline = title(content.title, style["title_sizes"], style["cursive"])
	var gap: float = style["after_title"] * MM
	if not content.syllables.is_empty():
		var columns := syllable_columns(content.syllables)
		adapted_grid(content, content.syllables_in(columns), columns, style["syllable_row"], gap, false)
		gap = style["after_syllables"] * MM
	if not content.words.is_empty():
		words(content, gap)
	chapter_sentences(content)
	for index in content.tables.size():
		table(content, content.tables[index], index == 0)
	if version.writing and not content.writing.is_empty() and content.writing_models + content.writing_tracings > 0:
		writing(content)
	# The long reading texts always come after the writing pages (the PO's rule, 2026-11-17).
	for story: Array in content.stories:
		lay_story(content, story[0], story[1])
	if not content.fluency.is_empty():
		fluency(content, content.fluency)


func syllable_columns(items: Array[BookletContent.Styled]) -> int:
	var face := fonts.script_regular
	var size: float = style["size"]
	var widest := -INF
	for item in items:
		widest = maxf(widest, spaced_width(face, item.text, size))
	for columns in SYLLABLE_COLUMNS:
		if widest + SYLLABLE_SPARE * size <= GRID_WIDTH / columns:
			return columns
	return SYLLABLE_COLUMNS[-1]


## Rows of ``columns`` items, each centred in its cell, ``row`` mm apart; rows
## that do not fit go on the next page. ``centres`` gives the cells' centres
## instead.
func adapted_grid(content: BookletContent.ChapterContent, items: Array[BookletContent.Styled], columns: int,
		row: float, gap: float, tinted: bool = true, given_centres: Array = []) -> void:
	var face := fonts.script_regular
	var size: float = style["size"]
	var centres := given_centres.duplicate()
	if centres.is_empty():
		for column in columns:
			centres.append(GRID_LEFT + (column + 0.5) * GRID_WIDTH / columns)
	var cell := GRID_WIDTH / centres.size()
	for item in items:
		if spaced_width(face, item.text, size) > cell:
			note(content, "\"%s\" is wider than its cell: check it does not run into its neighbour" % item.text)
	for start in range(0, items.size(), centres.size()):
		var row_baseline := place(gap if start == 0 else row * MM)
		var chunk := items.slice(start, start + centres.size())
		add(func(surface: DrawingSurface) -> void:
			for index in mini(chunk.size(), centres.size()):
				var item: BookletContent.Styled = chunk[index]
				draw_text(surface, face, centres[index] - spaced_width(face, item.text, size) / 2.0, row_baseline,
						item, size, tinted))


func words(content: BookletContent.ChapterContent, gap: float) -> void:
	var centres: Array = []
	for centre: float in style["word_centres"]:
		centres.append(PAGE_WIDTH * centre)
	adapted_grid(content, content.words_in(style["word_centres"].size()), 0, style["word_row"], gap, true, centres)


## On pages of their own, block after block: the chapter's paragraphs, or each
## sentence the base booklet chose for it.
func chapter_sentences(content: BookletContent.ChapterContent) -> void:
	var blocks: Array = []
	if not content.paragraphs.is_empty():
		for paragraph in content.paragraphs:
			var lines: Array = paragraph.lines
			if style["one_sentence_a_line"]:
				var single: Array = []
				for line: Array in lines:
					for piece: BookletContent.Styled in line:
						single.append([piece])
				lines = single
			blocks.append([paragraph.font, lines])
	elif not content.sentence_pool.is_empty():
		var pool := {}
		for pair: Array in content.sentence_pool:
			pool[pair[0]] = pair[1]
		var picked: Array = []
		for sentence_id: int in chosen.get(content.chapter.id, []):
			if pool.has(sentence_id):
				picked.append(sentence_id)
		for placed in picked.size():
			var text: BookletContent.Styled = pool[picked[placed]]
			blocks.append([content.sentence_fonts[placed % 2], _one_a_line(text.lines())])
	if blocks.is_empty():
		return
	new_page()
	for block: Array in blocks:
		put_block(content, lines_of(block[0], block[1]), style["block"] * MM)


func table(content: BookletContent.ChapterContent, rows: Array, with_penguin: bool = false) -> void:
	for row: BookletContent.TableRow in rows:
		if not row.bold and (_is_sentence(row.left.text) or _is_sentence(row.right.text)):
			sentence_table(content, rows)
			return
	new_page()
	var size: float = style["size"]
	var table_row: float = style["table_row"]
	if with_penguin and style["animals"]:
		add(func(surface: DrawingSurface) -> void:
			draw_picture(surface, "penguin", PAGE_WIDTH / 2.0, from_top(8.0), PENGUIN_HEIGHT * 1.25, true))
		# The first row's baseline 0.6 of a row under the penguin.
		baseline = from_top(8.0) - PENGUIN_HEIGHT * 1.25 + 0.4 * table_row * MM
	var centres := [PAGE_WIDTH * 2.0 / 7.0, PAGE_WIDTH * 5.0 / 7.0]
	for row: BookletContent.TableRow in rows:
		var row_baseline := place(table_row * MM)
		var face := fonts.script_bold if row.bold else fonts.script_regular
		add(func(surface: DrawingSurface) -> void:
			var cells := [row.left, row.right]
			for side in 2:
				var cell: BookletContent.Styled = cells[side]
				if not cell.text.is_empty():
					draw_text(surface, face, centres[side] - spaced_width(face, cell.text, size) / 2.0, row_baseline,
							cell, size)
			if row.bold:
				surface.stroke_color(BookletLayout.TABLE_RULE)
				surface.line_width(0.75)
				var rule := row_baseline - 0.35 * table_row * MM
				draw_line(surface, GRID_LEFT, rule, GRID_LEFT + GRID_WIDTH, rule))


## Each column on pages of its own: its header, then its sentences, centred and
## wrapped.
func sentence_table(content: BookletContent.ChapterContent, rows: Array) -> void:
	for side in 2:
		var cells: Array = []
		for row: BookletContent.TableRow in rows:
			var cell := row.left if side == 0 else row.right
			if not cell.text.is_empty():
				cells.append([row.bold, cell])
		if cells.is_empty():
			continue
		new_page()
		for pair: Array in cells:
			var cell: BookletContent.Styled = pair[1]
			var lines: Array[Line] = []
			if pair[0]:
				var face := fonts.script_bold
				for words_of: Array in wrap_lines(face, BookletContent.Paragraph.new(BookletContent.SCRIPT, [[cell]]),
						style["size"], TEXT_WIDTH, adapted_spacing):
					lines.append(Line.new(face, style["size"], words_of, adapted_spacing, style["line"] * MM, true))
			else:
				lines = lines_of(BookletContent.SCRIPT, [[cell]], 0.0, true)
			put_block(content, lines, style["table_cells"] * MM)


## Paragraphs flowing from page to page, left aligned.
func lay_story(_content: BookletContent.ChapterContent, story_title: String, paragraphs: Array) -> void:
	new_page()
	if not story_title.is_empty():
		var bold := fonts.script_bold
		var title_lines := wrap_lines(bold, BookletContent.Paragraph.new(BookletContent.SCRIPT,
				[[BookletContent.Styled.new(story_title)]]), style["story_title_size"], TEXT_WIDTH, adapted_spacing)
		for number in title_lines.size():
			var line_baseline := place(style["story_line"] * MM if number > 0 else 0.0)
			var line := Line.new(bold, style["story_title_size"], title_lines[number], adapted_spacing, 0.0)
			add(func(surface: DrawingSurface) -> void: draw_block_line(surface, line, line_baseline))
	var face := fonts.script_regular
	for index in paragraphs.size():
		var text: BookletContent.Styled = paragraphs[index]
		var lines := wrap_lines(face, BookletContent.Paragraph.new(BookletContent.SCRIPT, _one_a_line(text.lines())),
				style["story_size"], TEXT_WIDTH, adapted_spacing)
		for number in lines.size():
			var gap: float = (style["story_paragraph"] if number == 0 and index > 0 else style["story_line"]) * MM
			if number == 0 and index == 0:
				gap = 2.0 * style["story_line"] * MM
			var line_baseline := place(gap)
			var line := Line.new(face, style["story_size"], lines[number], adapted_spacing, 0.0)
			add(func(surface: DrawingSurface) -> void: draw_block_line(surface, line, line_baseline))


## A model in black then its copies to trace over, outlined, on every other
## main line; the main line between is left to write on.
func writing(content: BookletContent.ChapterContent) -> void:
	var face := fonts.cursive if content.writing_font == BookletContent.CURSIVE else fonts.script_regular
	var size := RULE_INTERVAL * MM / face.x_height
	var model_lines: Array[float] = []
	for line in range(1, RULE_MAINS, 2):
		model_lines.append(from_top(RULE_MAIN_TOP + line * 4 * RULE_INTERVAL))
	var verticals: Array[float] = []
	for index in 20:
		if VERTICAL_FIRST + index * VERTICAL_STEP < RULE_RIGHT:
			verticals.append(VERTICAL_FIRST + index * VERTICAL_STEP)
	var copies: Array[bool] = []
	for _model in content.writing_models:
		copies.append(false)
	for _tracing in content.writing_tracings:
		copies.append(true)
	var rows: Array = []
	for item in content.writing:
		var width := face.width(item, size)
		var current: Array = []
		var x := MODEL_LEFT
		for traced in copies:
			if not current.is_empty() and x + width / MM > RULE_RIGHT:
				rows.append(current)
				current = []
				x = MODEL_LEFT
			current.append([x, item, traced])
			# The next copy starts at a vertical line, a little room after.
			var end := x + width / MM + COPY_ROOM
			x = end
			for vertical in verticals:
				if vertical >= end:
					x = vertical
					break
		rows.append(current)
	var animals: bool = style["animals"]
	for start in range(0, rows.size(), model_lines.size()):
		new_page()
		var page_rows := rows.slice(start, start + model_lines.size())
		add(func(surface: DrawingSurface) -> void:
			ruling(surface, verticals)
			if animals:
				draw_picture(surface, "caterpillar", 6.0 * MM, from_top(4.0), ADAPTED_CATERPILLAR_HEIGHT * MM)
			for index in mini(model_lines.size(), page_rows.size()):
				for copy: Array in page_rows[index]:
					if copy[2]:
						face.draw(surface, copy[0] * MM, model_lines[index], copy[1], size, COPY_FILL, [], null, {},
								null, [COPY_EDGE, 0.5])
					else:
						face.draw(surface, copy[0] * MM, model_lines[index], copy[1], size, INK))


## Every item, in reading order, 3 a row and 4 rows a page.
func fluency(content: BookletContent.ChapterContent, items: Array[BookletContent.Styled]) -> void:
	var face := fonts.script_regular
	var size: float = style["fluency_size"]
	var cell := (ADAPTED_FLUENCY_COLUMNS[1] - ADAPTED_FLUENCY_COLUMNS[0]) * MM
	for item in items:
		if spaced_width(face, item.text, size) > cell:
			note(content, "\"%s\" is wider than its cell: check it does not run into its neighbour" % item.text)
	var per_page := ADAPTED_FLUENCY_COLUMNS.size() * FLUENCY_ROWS.size()
	for start in range(0, items.size(), per_page):
		new_page()
		var chunk := items.slice(start, start + per_page)
		add(func(surface: DrawingSurface) -> void:
			var left := FLUENCY_BOX[0]
			var top := FLUENCY_BOX[1]
			var right := FLUENCY_BOX[2]
			var bottom := FLUENCY_BOX[3]
			surface.fill_color(WHITE)
			surface.stroke_color(INK)
			surface.line_width(1.0)
			surface.path(PathCode.new().round_rect(left * MM, from_top(bottom), (right - left) * MM,
					(bottom - top) * MM, 6.0 * MM).code, true, true)
			for index in 2:
				stopwatch(surface, 17.0 * MM, from_top(STOPWATCH_TOP + index * 12), ADAPTED_STOPWATCH * MM)
			for index in chunk.size():
				var item: BookletContent.Styled = chunk[index]
				var centre := ADAPTED_FLUENCY_COLUMNS[index % ADAPTED_FLUENCY_COLUMNS.size()] * MM
				@warning_ignore("integer_division")
				var row_baseline := from_top(FLUENCY_ROWS[index / ADAPTED_FLUENCY_COLUMNS.size()])
				draw_text(surface, face, centre - spaced_width(face, item.text, size) / 2.0, row_baseline, item, size))


# --- The adaptations page ----------------------------------------------------------

## What this version changes, as the examples' table, and who it is advised for.
func adaptations(text: Dictionary) -> void:
	new_page(false)
	var face := fonts.script_regular
	var bold := fonts.script_bold
	var size := ADAPTATIONS_SIZE
	var line := ADAPTATIONS_LINE * MM
	var language := booklet.locale.split("_")[0]
	var readers: String = version.readers.get(language, "")
	var paragraph := func(words_of: String, at: float) -> Array:
		var placed: Array = []
		for words_on: Array in wrap_lines(face, BookletContent.Paragraph.new(BookletContent.SCRIPT,
				[[BookletContent.Styled.new(words_of)]]), size, TEXT_WIDTH):
			placed.append([words_on, at])
			at -= line
		return [placed, at]
	var first: Array = paragraph.call(text["intro"], from_top(30.0))
	var lines: Array = first[0]
	var table_top: float = first[1] - line / 2.0
	var rows: Array = []
	for key in ADAPTATIONS:
		rows.append([text["rows"][key], version.adaptations.has(key)])
	var after := table_top - (rows.size() + 1) * ADAPTATIONS_ROW * MM - line
	for piece: String in text["closing"]:
		var more: Array = paragraph.call(piece.replace("{readers}", readers).replace(" .", "."), after)
		lines.append_array(more[0])
		after = more[1]
		after -= line / 2.0
	var mark_x := TEXT_RIGHT - 12.0 * MM
	var heading: String = text["heading"]
	add(func(surface: DrawingSurface) -> void:
		var space := face.width(" ", size)
		for placed: Array in lines:
			var x := TEXT_LEFT
			for word: BookletContent.Styled in placed[0]:
				x += face.draw(surface, x, placed[1], word.text, size, INK) + space
		surface.stroke_color(BookletLayout.TABLE_RULE)
		surface.line_width(0.6)
		var row := ADAPTATIONS_ROW * MM
		var bottom := table_top - (rows.size() + 1) * row
		surface.path([["re", TEXT_LEFT, bottom, TEXT_WIDTH, table_top - bottom]], true, false)
		draw_line(surface, mark_x - 12.0 * MM, table_top, mark_x - 12.0 * MM, bottom)
		var labelled: Array = [[heading, false]] + rows
		for index in labelled.size():
			var top := table_top - index * row
			if index > 0:
				draw_line(surface, TEXT_LEFT, top, TEXT_LEFT + TEXT_WIDTH, top)
			var row_baseline := top - row / 2.0 - face.x_height * size / 2.0
			(bold if index == 0 else face).draw(surface, TEXT_LEFT + 2.0 * MM, row_baseline, labelled[index][0], size,
					INK)
			if labelled[index][1]:
				face.draw(surface, mark_x - face.width("x", size) / 2.0, row_baseline, "x", size, INK))


static func _is_sentence(text: String) -> bool:
	var trimmed := PythonUnicode.rstrip(text)
	return trimmed.ends_with(".") or trimmed.ends_with("!") or trimmed.ends_with("?") or trimmed.ends_with("…")


## The writing page's ruling: four fine blue intervals between grey main lines,
## and grey verticals the whole height of the page.
static func ruling(surface: DrawingSurface, verticals: Array[float]) -> void:
	var left := RULE_LEFT * MM
	var right := RULE_RIGHT * MM
	surface.line_width(0.35)
	surface.stroke_color(RULE_FINE)
	for main in RULE_MAINS - 1:
		for fine in range(1, 4):
			var y_at := from_top(RULE_MAIN_TOP + (main * 4 + fine) * RULE_INTERVAL)
			draw_line(surface, left, y_at, right, y_at)
	surface.stroke_color(RULE_MAIN)
	surface.line_width(0.5)
	for main in RULE_MAINS:
		var y_at := from_top(RULE_MAIN_TOP + main * 4 * RULE_INTERVAL)
		draw_line(surface, left, y_at, right, y_at)
	for vertical in verticals:
		draw_line(surface, vertical * MM, 0.0, vertical * MM, PAGE_HEIGHT)
