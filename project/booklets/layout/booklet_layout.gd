class_name BookletLayout
extends RefCounted
## Placing a booklet's content on A5 pages.
##
## Every measurement is here, in millimetres or points, so that the look of the
## booklets can be tuned in one place.
##
## A booklet is laid out in two passes: the layout decides what goes on which
## page, as a list of drawing steps per page, and BookletWriter draws them on a
## DrawingSurface, so that blank pages can be added before the back cover to
## reach a multiple of four (a booklet is printed on folded sheets).
##
## Ported from the Python generator's ``layout.py``, operation for operation:
## the first release this port built matched the last Python one page for page.

const MM := 72.0 / 25.4
const PAGE_WIDTH := 148.0 * MM
const PAGE_HEIGHT := 210.0 * MM
const MARGIN_SIDE := 14.0 * MM
const MARGIN_TOP := 14.0 * MM
const MARGIN_BOTTOM := 18.0 * MM
const LEFT := MARGIN_SIDE
const RIGHT := PAGE_WIDTH - MARGIN_SIDE
const TOP := PAGE_HEIGHT - MARGIN_TOP
const BOTTOM := MARGIN_BOTTOM
const WIDTH := RIGHT - LEFT

const INK := Color(0, 0, 0)
const WHITE := Color(1, 1, 1)
const SILENT := Color(0x9b / 255.0, 0x9b / 255.0, 0x9b / 255.0)  # silent letters
const TRACE := Color(0xc9 / 255.0, 0xc9 / 255.0, 0xc9 / 255.0)  # writing copies to trace over
const FOLIO := Color(0x7a / 255.0, 0x7a / 255.0, 0x7a / 255.0)  # page numbers
const TABLE_RULE := Color(0x8a / 255.0, 0x8a / 255.0, 0x8a / 255.0)
const BUBBLE := WHITE  # the fluency bubble, white and outlined in black as in the printed booklets
const BUBBLE_EDGE := INK
const SEYES_MAIN := Color(0x94 / 255.0, 0x88 / 255.0, 0xd4 / 255.0)
const SEYES_FINE := Color(0xd3 / 255.0, 0xcd / 255.0, 0xef / 255.0)
const SEYES_MARGIN := Color(0xe2 / 255.0, 0x82 / 255.0, 0x7f / 255.0)

const GAP := 7.0 * MM  # between the blocks of a page
## Between a chapter's sections, measured ink to ink on the printed booklets
## (2026-11-09, the PO found ours too tight): about 12.8 mm from the title to
## the syllables, from the syllables to the words and from the words to the
## sentences. A grid row already holds some of it around its letters.
const TITLE_GAP := 10.9 * MM  # below the title's ink
const GRID_GAP := 7.9 * MM  # below a grid's last row
const BEFORE_SENTENCES := 3.6 * MM  # more, from a grid to the sentences

## Sizes measured on the printed booklets (2026-10-29). Text is never made
## smaller than these to fit: what is too wide spills over and is said
## (_wider_than()). By the number of lines: a title of four or five keeps the
## three-line size, since every title of several graphemes is a column, one per
## line, and a smaller one leaves its cursive column too small to read.
const TITLE_SIZES := {1: 36.0, 2: 30.0, 3: 26.0, 4: 26.0, 5: 26.0}
const TITLE_LEADING := 1.25
const TITLE_LINE_GAP := 0.4  # the least room between two title lines' ink, in em
const CURSIVE_TITLE_SCALE := 0.52  # of the script size: the printed titles' two columns stand as tall

const SYLLABLE_SIZE := 16.0
const SYLLABLE_ROW := 9.5 * MM  # 26.8 pt in the printed booklets
const WORD_SIZE := 16.0
const WORD_ROW := 8.8 * MM  # 25 pt in the printed booklets
const CELL_PADDING := 2.0 * MM

const SENTENCE_SIZE := 16.0
const CURSIVE_SENTENCE_SIZE := 14.6  # Marelle stands taller: the printed booklets set it smaller
## Measured on the printed booklets: script lines 23.2 pt apart at 16 pt,
## cursive ones about 27 pt, and 40.6 pt from a cursive line to the next
## paragraph's first script line.
const SCRIPT_LEADING := 1.45
const CURSIVE_LEADING := 1.85  # of CURSIVE_SENTENCE_SIZE: 27 pt
const PARAGRAPH_GAP := 0.67  # of the next paragraph's line

const TABLE_SIZE := 16.0
const TABLE_LEADING := 1.3  # a cell's wrapped lines
const TABLE_ROW := 9.0 * MM
const TABLE_WIDTH := 0.8 * WIDTH

const STORY_TITLE_SIZE := 16.0
const STORY_SIZE := 13.0
const STORY_LEADING := 1.5

const FLUENCY_SIZE := 14.0
const FLUENCY_COLUMNS := 5
const FLUENCY_ROW := 9.0 * MM  # at least; rows stretch to fill the page, up to FLUENCY_ROW_MOST
const FLUENCY_ROW_MOST := 12.0 * MM
## A shorter test keeps a full test's bubble and row spacing, its rows at the
## top, as the printed Brazilian booklet's 25-item test does.
const FLUENCY_FULL_ROWS := 10
const FLUENCY_PADDING := 4.0 * MM
## The bubble reaches further out than the text margins, so that its words
## have room (the PO found them tight on the last rows, 2026-11-09).
const FLUENCY_LEFT := 7.0 * MM
const FLUENCY_WIDTH := PAGE_WIDTH - 2.0 * FLUENCY_LEFT

## Seyès ruling: a thick line every four fine intervals. Lowercase letters are
## one interval high, as on a French school notebook.
const SEYES_INTERVAL := 3.0 * MM
const SEYES_LINES := 12  # writing lines per page
const SEYES_MARGIN_LINE := LEFT + 12.0 * MM
const COPY_GAP := 8.0 * MM

const FOLIO_SIZE := 9.0
const FOLIO_Y := 9.0 * MM

## The game's characters (art/LICENSE.md): the parakeet under the fluency
## test's bubble, the penguin above the tables, the caterpillar on the writing
## pages.
const PARAKEET_HEIGHT := 24.0 * MM
const PENGUIN_HEIGHT := 12.0 * MM
const CATERPILLAR_HEIGHT := 9.0 * MM
const BUBBLE_TAIL := 8.0 * MM  # how far the fluency bubble's tail reaches down
const STOPWATCH := 5.0 * MM

## The cover: the Kalulu logo, its rabbit in the "u", and the booklet's number
## in white on a star, placed as on the printed booklets (2026-11-03): the logo
## 87 mm wide, its top 52.2 mm from the page's; the star 27.2 mm across, its
## top 139.4 mm down; the number in Mulish Bold, 28.2 pt, its baseline 155.8 mm
## down.
const COVER_LOGO_WIDTH := 87.0 * MM
const COVER_LOGO_TOP := PAGE_HEIGHT - 52.2 * MM
const COVER_STAR_WIDTH := 27.2 * MM
const COVER_STAR_TOP := PAGE_HEIGHT - 139.4 * MM
const COVER_NUMBER_SIZE := 28.2
const COVER_NUMBER_Y := PAGE_HEIGHT - 155.8 * MM

## The cover's version line (BookletVersion), measured on the printed teacher
## and adapted booklets: 20.7 pt, its baseline 178 mm from the top. The
## teacher's is in Mulish Bold; the adapted ones are in Mulish Light, which the
## packs do not have: the regular weight stands in.
const COVER_LABEL_SIZE := 20.7
const COVER_LABEL_Y := PAGE_HEIGHT - 178.0 * MM

const OPENING := "«“‘([{¿¡"


## A page: its drawing steps, Callables taking the DrawingSurface.
class Page:
	var steps: Array[Callable] = []
	var numbered := true
	## A teacher's page carries the number of the chapter page after it.
	var shares_next_number := false
	## The IDs of the chapters laid out on it (keys; the values mean nothing):
	## none for the covers and the blank pages, sometimes two where a chapter
	## starts on the page another ends on. The Prof Tool previews a chapter's
	## pages by them.
	var chapter_ids: Dictionary = {}

	func _init(is_numbered: bool = true, shares_next: bool = false) -> void:
		numbered = is_numbered
		shares_next_number = shares_next


var booklet: BookletContent.Booklet
## The chapter being laid out, null outside the chapters (Page.chapter_ids).
var laying: BookletContent.ChapterContent = null
var fonts: FontSet
var version: BookletVersion
## Chapter ID -> the sentences chosen for a chapter that picks none, in the
## order printed: this layout's own, or, given, another's (an adapted version
## prints what the base booklet chose).
var chosen: Dictionary = {}
var pages: Array[Page] = []
var y := TOP
## Sentences this booklet has printed, so a chosen one is not repeated while
## others are left.
var printed_sentences: Dictionary = {}
## Whether the last thing placed on this page is a grid: the sentences stand
## further from one (BEFORE_SENTENCES).
var after_grid := false


func _init(laid_out: BookletContent.Booklet, faces: FontSet, booklet_version: BookletVersion = null,
		chosen_sentences: Variant = null) -> void:
	booklet = laid_out
	fonts = faces
	version = booklet_version if booklet_version != null else BookletVersion.named("base")
	if chosen_sentences != null:
		chosen = (chosen_sentences as Dictionary).duplicate()


# --- Pages -------------------------------------------------------------------------

## Lets go of the pages once they are drawn. Their steps are lambdas that may
## hold this layout, which holds them: a cycle reference counting never frees,
## so whoever lays a booklet out calls this when done with its pages (the
## writer does), or every preview drawn would stay in memory.
func release() -> void:
	pages.clear()


func new_page(numbered: bool = true, shares_next_number: bool = false) -> Page:
	pages.append(Page.new(numbered, shares_next_number))
	if laying != null:
		pages[-1].chapter_ids[laying.chapter.id] = true
	y = TOP
	after_grid = false
	return pages[-1]


func page() -> Page:
	return pages[-1]


func room() -> float:
	return y - BOTTOM


func add(step: Callable) -> void:
	page().steps.append(step)
	if laying != null:
		page().chapter_ids[laying.chapter.id] = true


func note(chapter: BookletContent.ChapterContent, text: String) -> void:
	booklet.notes.append("%s: %s" % [chapter.chapter.name(), text])


## Text is never made smaller to fit a cell: one wider than its whole cell is
## printed at its size all the same, reaching into the next one, and said, so
## that the pack can be changed if it runs into its neighbour.
func _wider_than(chapter: BookletContent.ChapterContent, face: FontFace, texts: Array, size: float,
		width: float) -> void:
	for text: String in texts:
		if not text.is_empty() and face.width(text, size) > width:
			note(chapter, "\"%s\" is wider than its cell: check it does not run into its neighbour" % text)


# --- The booklet -------------------------------------------------------------------

func run() -> Array[Page]:
	cover()
	for chapter in booklet.chapters:
		laying = chapter
		lay_chapter(chapter)
	laying = null
	# Blank pages before the back cover, to fill the last folded sheet. A
	# version not printed as a booklet (the teacher's) is not folded.
	while version.folded and (pages.size() + 1) % 4 != 0:
		new_page(false)
	back_cover()
	return pages


func cover() -> void:
	new_page(false)
	var number := str(booklet.number)
	var bold := fonts.script_bold
	var label := version.label(booklet.locale)
	var label_face := bold if version.label_bold else fonts.script_regular
	var label_color: Color = version.label_color if version.label_color != null else INK
	add(func(surface: DrawingSurface) -> void:
		draw_vector(surface, "kalulu-logo", COVER_LOGO_TOP, COVER_LOGO_WIDTH)
		draw_vector(surface, "cover-star", COVER_STAR_TOP, COVER_STAR_WIDTH)
		centered(surface, bold, number, COVER_NUMBER_Y, COVER_NUMBER_SIZE, WHITE)
		if not label.is_empty():
			centered(surface, label_face, label, COVER_LABEL_Y, COVER_LABEL_SIZE, label_color))


func draw_folio(surface: DrawingSurface, number: int) -> void:
	centered(surface, fonts.script_regular, str(number), FOLIO_Y, FOLIO_SIZE, FOLIO)


func back_cover() -> void:
	new_page(false)
	var face := fonts.script_black
	add(func(surface: DrawingSurface) -> void: centered(surface, face, "Kalulu", 24.0 * MM, 20.0, FOLIO))


# --- A chapter ---------------------------------------------------------------------

func lay_chapter(content: BookletContent.ChapterContent) -> void:
	if version.teacher and not content.picture.is_empty():
		teacher_page(content)
	if content.has_chapter_page():
		new_page()
	if not content.title.is_empty():
		title(content.title)
	if not content.syllables.is_empty():
		grid(content, content.syllables, content.syllable_columns, SYLLABLE_SIZE, SYLLABLE_ROW)
	if not content.words.is_empty():
		grid(content, content.words, content.word_columns, WORD_SIZE, WORD_ROW)
	if not content.paragraphs.is_empty():
		sentences(content)
	elif not content.sentence_pool.is_empty():
		chosen_sentences(content)
	for index in content.tables.size():
		table(content, content.tables[index], index == 0)
	if version.writing and not content.writing.is_empty() and content.writing_models + content.writing_tracings > 0:
		writing(content)
	# The long reading texts always come after the writing pages (the PO's rule, 2026-11-17).
	for story: Array in content.stories:
		lay_story(content, story[0], story[1])
	if not content.fluency.is_empty():
		fluency(content, content.fluency)


## The chapter's title and its picture, as large as the page allows, before the
## chapter page and under its number: the teacher shows it to the class while
## the pupils read the page after it.
func teacher_page(content: BookletContent.ChapterContent) -> void:
	new_page(true, true)
	if not content.title.is_empty():
		title(content.title)
	var picture := BookletArt.picture_at(content.picture)
	var width := float(picture.get_width())
	var height := float(picture.get_height())
	var scale := minf(WIDTH / width, (y - BOTTOM) / height)
	var shown_width := width * scale
	var shown_height := height * scale
	var left := (PAGE_WIDTH - shown_width) / 2.0
	var bottom := BOTTOM + (y - BOTTOM - shown_height) / 2.0
	var key := content.picture
	add(func(surface: DrawingSurface) -> void: surface.image(key, picture, left, bottom, shown_width, shown_height))
	y = BOTTOM


## Script on the left; cursive, when the language has it, on the right.
## ``sizes`` by the number of lines; ``cursive_too`` false prints the script
## alone, centred. Returns the last line's baseline, or null.
func title(lines: Array[String], sizes: Dictionary = TITLE_SIZES, cursive_too: bool = true) -> Variant:
	var script := fonts.script_regular
	var cursive := fonts.cursive
	var with_cursive := booklet.cursive and cursive_too
	var half := WIDTH / 2.0 - 3.0 * MM if with_cursive else WIDTH
	var size: float = sizes.get(lines.size(), 22.0)
	for line in lines:
		size = minf(size, minf(fit(script, line, half),
				fit(cursive, line, half) / CURSIVE_TITLE_SCALE if with_cursive else size))
	var cursive_size := size * CURSIVE_TITLE_SCALE
	# Each line is placed by the ink of both columns, accents and loops
	# included, so that no line runs into the one above.
	var tops: Array[float] = []
	var bottoms: Array[float] = []
	for line in lines:
		var faces: Array = [[script, size], [cursive, cursive_size]] if with_cursive else [[script, size]]
		var top := -INF
		var bottom := INF
		for pair: Array in faces:
			var ink: Array = pair[0].ink(line)
			top = maxf(top, ink[0] * pair[1])
			bottom = minf(bottom, ink[1] * pair[1])
		tops.append(top)
		bottoms.append(bottom)
	var baselines: Array[float] = []
	if not lines.is_empty():
		baselines.append(y - tops[0])
	for index in range(1, lines.size()):
		var step := maxf(size * TITLE_LEADING, -bottoms[index - 1] + tops[index] + TITLE_LINE_GAP * size)
		baselines.append(baselines[-1] - step)
	var drawn_size := size
	add(func(surface: DrawingSurface) -> void:
		# Each column centred in its half of the page, as printed, and each of
		# its lines centred on it (the PO's rule, 2026-11-09).
		var script_centre := LEFT + WIDTH / 4.0 if with_cursive else PAGE_WIDTH / 2.0
		var cursive_centre := LEFT + 3.0 * WIDTH / 4.0
		for index in lines.size():
			var line := lines[index]
			script.draw(surface, script_centre - script.width(line, drawn_size) / 2.0, baselines[index], line,
					drawn_size, INK)
			if with_cursive:
				cursive.draw(surface, cursive_centre - cursive.width(line, cursive_size) / 2.0, baselines[index],
						line, cursive_size, INK))
	if not lines.is_empty():
		y = baselines[-1] + bottoms[-1] - TITLE_GAP
		return baselines[-1]
	y -= TITLE_GAP
	return null


func grid(content: BookletContent.ChapterContent, items: Array[BookletContent.Styled], columns: int, size: float,
		row: float) -> void:
	columns = maxi(1, mini(columns, items.size()))
	var rows := ceili(float(items.size()) / columns)
	if rows * row > room():
		new_page()
	var face := fonts.script_regular
	var cell := WIDTH / columns
	var top := y
	_wider_than(content, face, items.map(func(item: BookletContent.Styled) -> String: return item.text), size, cell)
	# Every item at the same size, a long one spilling out of its cell: a
	# smaller one among the others reads as different.
	add(func(surface: DrawingSurface) -> void:
		for index in items.size():
			var item := items[index]
			var center_x := LEFT + (index % columns + 0.5) * cell
			@warning_ignore("integer_division")
			var center_y := top - (index / columns + 0.5) * row
			face.draw(surface, center_x - face.width(item.text, size) / 2.0, center_y - face.x_height * size / 2.0,
					item.text, size, INK, item.grey, SILENT))
	y -= rows * row + GRID_GAP
	after_grid = true


## The room between a grid and the sentences under it.
func below_grid() -> void:
	if after_grid:
		y -= BEFORE_SENTENCES
		after_grid = false


## On the page they start on, then on at most ``sentence_pages`` more; lines
## past that are left out and said. A paragraph is never cut across two pages
## (the PO's rule, 2026-11-09: a sentence starts and ends on the same page): one
## that does not fit where it would start goes on the next page whole, unless
## it is taller than a page on its own.
func sentences(content: BookletContent.ChapterContent) -> void:
	var limit := content.sentence_pages
	var extra := 0
	var dropped := 0
	for item in content.chapter.sentences:
		printed_sentences[item.sentence_id] = true
	below_grid()
	for index in content.paragraphs.size():
		var paragraph := content.paragraphs[index]
		var cursive := paragraph.font == BookletContent.CURSIVE
		var face := fonts.cursive if cursive else fonts.script_regular
		var size := CURSIVE_SENTENCE_SIZE if cursive else SENTENCE_SIZE
		var leading := size * (CURSIVE_LEADING if cursive else SCRIPT_LEADING)
		var lines := wrap_lines(face, paragraph, size, WIDTH)
		var gap := leading * PARAGRAPH_GAP if index > 0 else 0.0
		if dropped > 0:
			dropped += lines.size()
			continue
		var whole := lines.size() * leading
		if gap + whole > room() and whole <= TOP - BOTTOM:
			if extra >= limit:
				dropped += lines.size()
				continue
			new_page()
			extra += 1
			gap = 0.0
		y -= gap
		for line: Array in lines:
			if dropped > 0 or leading > room():
				if dropped > 0 or extra >= limit:
					dropped += 1
					continue
				new_page()
				extra += 1
			var baseline := y - leading + (leading - face.x_height * size) / 2.0
			add(line_step(face, line, baseline, size))
			y -= leading
	if dropped > 0:
		var where := "the page they start on" if limit == 0 else "that page and %d more" % limit
		note(content, "the sentences do not fit on %s (SentencePages is %d): %d line(s) are not printed"
				% [where, limit, dropped])
	y -= GAP


## A chapter that picks no sentence: as many of its pool as fit on the page they
## start on and on ``sentence_pages`` more, each whole. One that would run onto
## the next page is passed over for a later one that fits; one already printed
## in this booklet comes after the others. When too few of the pool hold one of
## the chapter's GPs to fill its pages, the others, earlier lessons' content,
## are printed too, and the build says so.
func chosen_sentences(content: BookletContent.ChapterContent) -> void:
	var pool := StableSort.sorted(content.sentence_pool, func(candidate: Array) -> bool:
		return printed_sentences.has(candidate[0]))
	below_grid()
	var printed: Array[int] = []
	var extra := 0
	var placed := 0
	var top_of_page := false
	while not pool.is_empty():
		var fitting: Array = []
		for index in pool.size():
			var font: String = content.sentence_fonts[placed % 2]
			var cursive := font == BookletContent.CURSIVE
			var face := fonts.cursive if cursive else fonts.script_regular
			var size := CURSIVE_SENTENCE_SIZE if cursive else SENTENCE_SIZE
			var leading := size * (CURSIVE_LEADING if cursive else SCRIPT_LEADING)
			var text: BookletContent.Styled = pool[index][1]
			var lines := wrap_lines(face, BookletContent.Paragraph.new(font, _one_a_line(text.lines())), size, WIDTH)
			var gap := leading * PARAGRAPH_GAP if placed > 0 and not top_of_page else 0.0
			if gap + lines.size() * leading <= room():
				fitting = [index, pool[index][0], face, leading, lines, gap, size]
				break
		if fitting.is_empty():
			# Nothing left fits here: another page, if one is allowed and this
			# is not already a fresh one.
			if top_of_page or extra >= content.sentence_pages:
				break
			new_page()
			extra += 1
			top_of_page = true
			continue
		var face: FontFace = fitting[2]
		var leading: float = fitting[3]
		var size: float = fitting[6]
		y -= fitting[5]
		for line: Array in fitting[4]:
			var baseline := y - leading + (leading - face.x_height * size) / 2.0
			add(line_step(face, line, baseline, size))
			y -= leading
		printed_sentences[fitting[1]] = true
		printed.append(fitting[1])
		pool.pop_at(fitting[0])
		placed += 1
		top_of_page = false
	chosen[content.chapter.id] = printed
	var earlier := printed.filter(func(sentence_id: int) -> bool:
		return not content.sentences_teaching.has(sentence_id))
	if not earlier.is_empty():
		var own := content.sentences_teaching.size()
		var readable := "no readable sentence holds one" if own == 0 else (
				"only 1 readable sentence holds one" if own == 1 else "only %d readable sentences hold one" % own)
		note(content, ("not enough content of its own: %d of its %d sentences %s none of its GPs, taken from "
				+ "earlier lessons to fill its pages (%s)") % [earlier.size(), printed.size(),
				"holds" if earlier.size() == 1 else "hold", readable])
	y -= GAP


func table(content: BookletContent.ChapterContent, rows: Array, with_penguin: bool = false) -> void:
	var penguin := PENGUIN_HEIGHT + GAP / 2.0 if with_penguin else 0.0
	if rows.size() * TABLE_ROW + penguin > room():
		new_page()
	if with_penguin:
		var top_of_art := y
		add(func(surface: DrawingSurface) -> void:
			draw_picture(surface, "penguin", PAGE_WIDTH / 2.0, top_of_art, PENGUIN_HEIGHT, true))
		y -= penguin
	var regular := fonts.script_regular
	var bold := fonts.script_bold
	var left := LEFT + (WIDTH - TABLE_WIDTH) / 2.0
	var column := TABLE_WIDTH / 2.0
	var inside := column - 2.0 * CELL_PADDING
	var leading := TABLE_SIZE * TABLE_LEADING
	# A cell holding a sentence wraps onto more lines, as in the printed
	# booklets, and its row grows; a word too wide for the cell spills over.
	var cells: Array = []
	var heights: Array[float] = []
	for row: BookletContent.TableRow in rows:
		var face := bold if row.bold else regular
		var wrapped: Array = []
		for cell: BookletContent.Styled in [row.left, row.right]:
			wrapped.append(wrap_lines(face, BookletContent.Paragraph.new(BookletContent.SCRIPT, [[cell]]), TABLE_SIZE, inside)
					if not cell.text.is_empty() else [])
		for lines: Array in wrapped:
			var words: Array = []
			for line: Array in lines:
				for word: BookletContent.Styled in line:
					words.append(word.text)
			_wider_than(content, face, words, TABLE_SIZE, column)
		cells.append(wrapped)
		var tallest := 1
		for lines: Array in wrapped:
			tallest = maxi(tallest, lines.size())
		heights.append(maxf(TABLE_ROW, tallest * leading + 2.0 * CELL_PADDING))
	var height := 0.0
	for row_height in heights:
		height += row_height
	if height > room():
		new_page()
	var top := y
	add(func(surface: DrawingSurface) -> void:
		surface.stroke_color(TABLE_RULE)
		surface.line_width(0.75)
		surface.path([["re", left, top - height, TABLE_WIDTH, height]], true, false)
		draw_line(surface, left + column, top, left + column, top - height)
		var row_top := top
		for index in rows.size():
			var row: BookletContent.TableRow = rows[index]
			var row_height := heights[index]
			if index > 0:
				draw_line(surface, left, row_top, left + TABLE_WIDTH, row_top)
			var face := bold if row.bold else regular
			var space := face.width(" ", TABLE_SIZE)
			for side in 2:
				var lines: Array = cells[index][side]
				var x := left if side == 0 else left + column
				var first := row_top - (row_height - lines.size() * leading) / 2.0 - leading / 2.0
				for number in lines.size():
					var line: Array = lines[number]
					var width := 0.0
					for word: BookletContent.Styled in line:
						width += face.width(word.text, TABLE_SIZE)
					width += space * (line.size() - 1)
					var cursor := x + (column - width) / 2.0
					var baseline := first - number * leading - face.x_height * TABLE_SIZE / 2.0
					for word: BookletContent.Styled in line:
						cursor += face.draw(surface, cursor, baseline, word.text, TABLE_SIZE, INK, word.grey, SILENT) \
								+ space
			row_top -= row_height)
	y -= height + GAP


func lay_story(content: BookletContent.ChapterContent, story_title: String,
		paragraphs: Array) -> void:
	new_page()
	if not story_title.is_empty():
		var bold := fonts.script_bold
		var top := y
		add(func(surface: DrawingSurface) -> void:
			centered(surface, bold, story_title, top - bold.cap_height * STORY_TITLE_SIZE, STORY_TITLE_SIZE, INK))
		y -= bold.cap_height * STORY_TITLE_SIZE + GAP
	var face := fonts.script_regular
	var leading := STORY_SIZE * STORY_LEADING
	for index in paragraphs.size():
		var text: BookletContent.Styled = paragraphs[index]
		if index > 0:
			y -= leading * PARAGRAPH_GAP
		for line: Array in wrap_lines(face, BookletContent.Paragraph.new(BookletContent.SCRIPT, _one_a_line(text.lines())),
				STORY_SIZE, WIDTH):
			if leading > room():
				new_page()
			var baseline := y - leading + (leading - face.x_height * STORY_SIZE) / 2.0
			add(line_step(face, line, baseline, STORY_SIZE))
			y -= leading
	y -= GAP


## Each item on its own ruled line, in black then in grey to trace over, and
## the line after it left empty to write on.
func writing(content: BookletContent.ChapterContent) -> void:
	var face := fonts.cursive if content.writing_font == BookletContent.CURSIVE else fonts.script_regular
	var size := SEYES_INTERVAL / face.x_height
	var copies: Array[Color] = []
	for _model in content.writing_models:
		copies.append(INK)
	for _tracing in content.writing_tracings:
		copies.append(TRACE)
	var lines: Array = []
	for item in content.writing:
		var width := face.width(item, size)
		var current: Array = []
		var x := SEYES_MARGIN_LINE + 3.0 * MM
		for color in copies:
			if not current.is_empty() and x + width > RIGHT:
				lines.append(current)
				current = []
				x = SEYES_MARGIN_LINE + 3.0 * MM
			current.append([x, item, color])
			x += width + COPY_GAP
		lines.append(current)
		lines.append([])
	if not lines.is_empty() and lines[-1].is_empty():
		lines.pop_back()
	for start in range(0, lines.size(), SEYES_LINES):
		new_page()
		var page_lines := lines.slice(start, start + SEYES_LINES)
		add(func(surface: DrawingSurface) -> void: seyes(surface, face, size, page_lines))


## A speech bubble the parakeet says, with two stopwatches beside it: the child
## reads the bubble aloud against the clock.
func fluency(content: BookletContent.ChapterContent, items: Array[BookletContent.Styled]) -> void:
	var face := fonts.script_regular
	var below := BUBBLE_TAIL + PARAKEET_HEIGHT
	var per_page := int(floorf((TOP - BOTTOM - below - 2.0 * FLUENCY_PADDING) / FLUENCY_ROW)) * FLUENCY_COLUMNS
	var cell := (FLUENCY_WIDTH - 2.0 * FLUENCY_PADDING) / FLUENCY_COLUMNS
	_wider_than(content, face, items.map(func(item: BookletContent.Styled) -> String: return item.text),
			FLUENCY_SIZE, cell)
	for start in range(0, items.size(), per_page):
		new_page()
		var chunk := items.slice(start, start + per_page)
		var rows := maxi(ceili(float(chunk.size()) / FLUENCY_COLUMNS), FLUENCY_FULL_ROWS)
		# The bubble takes the page down to the parakeet, as the printed
		# booklets have it, its rows no further apart than FLUENCY_ROW_MOST.
		var row_height := minf(FLUENCY_ROW_MOST, (room() - below - 2.0 * FLUENCY_PADDING) / rows)
		var height := rows * row_height + 2.0 * FLUENCY_PADDING
		var top := y
		add(func(surface: DrawingSurface) -> void:
			var bottom := top - height
			bubble(surface, FLUENCY_LEFT, bottom, FLUENCY_WIDTH, height, 6.0 * MM, PAGE_WIDTH / 2.0, BUBBLE_TAIL)
			draw_picture(surface, "parakeet", PAGE_WIDTH / 2.0, bottom - BUBBLE_TAIL - 1.0 * MM, PARAKEET_HEIGHT, true)
			for row in 2:
				stopwatch(surface, RIGHT - 18.0 * MM, bottom - BUBBLE_TAIL - 6.0 * MM - row * (STOPWATCH + 2.0 * MM),
						STOPWATCH)
			var each := (FLUENCY_WIDTH - 2.0 * FLUENCY_PADDING) / FLUENCY_COLUMNS
			# One size for all: a test read against the clock must not have a
			# word printed smaller than the others.
			for index in chunk.size():
				var item: BookletContent.Styled = chunk[index]
				var center_x := FLUENCY_LEFT + FLUENCY_PADDING + (index % FLUENCY_COLUMNS + 0.5) * each
				@warning_ignore("integer_division")
				var center_y := top - FLUENCY_PADDING - (index / FLUENCY_COLUMNS + 0.5) * row_height
				face.draw(surface, center_x - face.width(item.text, FLUENCY_SIZE) / 2.0,
						center_y - face.x_height * FLUENCY_SIZE / 2.0, item.text, FLUENCY_SIZE, INK, item.grey, SILENT))
		y -= height + below + GAP


# --- Drawing helpers ---------------------------------------------------------------

## One of the game's characters, ``height`` high, its top at ``top``; ``x`` is
## its left edge, or its middle when ``centred``.
static func draw_picture(surface: DrawingSurface, name: String, x: float, top: float, height: float,
		centred: bool = false) -> void:
	var picture := BookletArt.picture(name)
	var width := height * picture.get_width() / picture.get_height()
	var left := x - width / 2.0 if centred else x
	surface.image("art/%s.png" % name, picture, left, top - height, width, height)


## One of the vector drawings of art/, ``width`` wide, centred across the page,
## its top at ``top``.
static func draw_vector(surface: DrawingSurface, name: String, top: float, width: float) -> void:
	BookletArt.vector(name).draw(surface, (PAGE_WIDTH - width) / 2.0, top, width)


static func draw_line(surface: DrawingSurface, x1: float, y1: float, x2: float, y2: float) -> void:
	surface.path([["m", x1, y1], ["l", x2, y2]], true, false)


## A rounded speech bubble whose tail points down at ``tail_x``.
static func bubble(surface: DrawingSurface, x: float, bottom: float, width: float, height: float, radius: float,
		tail_x: float, tail: float) -> void:
	var half := tail * 0.75
	var path := PathCode.new()
	path.move_to(x + radius, bottom)
	path.line_to(tail_x - half, bottom)
	path.line_to(tail_x, bottom - tail)
	path.line_to(tail_x + half, bottom)
	path.line_to(x + width - radius, bottom)
	path.arc_to(x + width - 2.0 * radius, bottom, x + width, bottom + 2.0 * radius, -90.0, 90.0)
	path.line_to(x + width, bottom + height - radius)
	path.arc_to(x + width - 2.0 * radius, bottom + height - 2.0 * radius, x + width, bottom + height, 0.0, 90.0)
	path.line_to(x + radius, bottom + height)
	path.arc_to(x, bottom + height - 2.0 * radius, x + 2.0 * radius, bottom + height, 90.0, 90.0)
	path.line_to(x, bottom + radius)
	path.arc_to(x, bottom, x + 2.0 * radius, bottom + 2.0 * radius, 180.0, 90.0)
	path.close()
	surface.fill_color(BUBBLE)
	surface.stroke_color(BUBBLE_EDGE)
	surface.line_width(1.0)
	surface.path(path.code, true, true)


## A stopwatch ``size`` across, its dial centred at (x, y): a ring, the crown
## on top, the side button and one hand.
static func stopwatch(surface: DrawingSurface, x: float, y: float, size: float) -> void:
	var radius := size / 2.0
	var stroke := size * 0.1
	surface.stroke_color(INK)
	surface.fill_color(INK)
	surface.line_width(stroke)
	surface.path(PathCode.new().circle(x, y, radius - stroke / 2.0).code, true, false)
	surface.path([["re", x - size * 0.12, y + radius, size * 0.24, size * 0.1]], false, true)
	surface.path([["re", x - size * 0.2, y + radius + size * 0.1, size * 0.4, size * 0.08]], false, true)
	var side := deg_to_rad(45.0)
	draw_line(surface, x + radius * cos(side), y + radius * sin(side),
			x + (radius + size * 0.12) * cos(side), y + (radius + size * 0.12) * sin(side))
	surface.line_width(stroke * 0.8)
	draw_line(surface, x, y, x + radius * 0.45, y + radius * 0.45)
	surface.path(PathCode.new().circle(x, y, stroke * 0.6).code, false, true)


## The largest size at which ``text`` fits in ``width``.
static func fit(face: FontFace, text: String, width: float) -> float:
	var at_one := face.width(text, 1.0)
	return width / at_one if at_one != 0.0 else 1000.0


static func centered(surface: DrawingSurface, face: FontFace, text: String, baseline: float, size: float,
		color: Color) -> void:
	face.draw(surface, (PAGE_WIDTH - face.width(text, size)) / 2.0, baseline, text, size, color)


## A paragraph's printed lines, cut between words, as Arrays of Styled words,
## with the letter and word ``spacing`` they are drawn with.
static func wrap_lines(face: FontFace, paragraph: BookletContent.Paragraph, size: float, width: float,
		spacing: TextSpacing = null) -> Array:
	var space := face.width(" ", size, spacing)
	var printed: Array = []
	for pieces: Array in paragraph.lines:
		var line := BookletContent.Styled.joined(pieces)
		var current: Array = []
		var used := 0.0
		var start := -1
		var bounds: Array = []
		var padded := line.text + " "
		for index in padded.length():
			if padded[index] == " ":
				if start >= 0:
					bounds.append([start, index])
					start = -1
			elif start < 0:
				start = index
		for span: Array in unbreakable(line.text, bounds):
			var word := line.slice(span[0], span[1])
			var word_width := face.width(word.text, size, spacing)
			if not current.is_empty() and used + space + word_width > width:
				printed.append(current)
				current = []
				used = 0.0
			used += (space if not current.is_empty() else 0.0) + word_width
			current.append(word)
		if not current.is_empty():
			printed.append(current)
	return printed


## ``bounds`` (each word's [start, end] in ``text``) joined where a line must
## not break: French sets a space before "!", "?", ":", ";" and "»", and after
## "«", and a mark alone at the start or end of a line reads as a mistake (the
## PO's rule, 2026-11-09). A run of punctuation with no letter or digit is kept
## with the word before it, an opening one with the word after.
static func unbreakable(text: String, bounds: Array) -> Array:
	var joined: Array = []
	var pending := -1  # where an opening mark waiting for its word starts
	for span: Array in bounds:
		var start: int = span[0]
		var end: int = span[1]
		if pending >= 0:
			start = pending
			pending = -1
		var bare := not PythonUnicode.has_alnum(BookletContent.substring(text, start, end))
		if bare and _all_opening(BookletContent.substring(text, start, end)):
			pending = start
			continue
		if not joined.is_empty() and bare:
			joined[-1] = [joined[-1][0], end]
		else:
			joined.append([start, end])
	if pending >= 0:
		joined.append([pending, bounds[-1][1]])
	return joined


static func _all_opening(text: String) -> bool:
	for character in text:
		if not OPENING.contains(character):
			return false
	return true


static func line_step(face: FontFace, words: Array, baseline: float, size: float) -> Callable:
	return func(surface: DrawingSurface) -> void:
		var x := LEFT
		var space := face.width(" ", size)
		for word: BookletContent.Styled in words:
			x += face.draw(surface, x, baseline, word.text, size, INK, word.grey, SILENT) + space


## A page of Seyès ruling, with the writing models on its lines.
static func seyes(surface: DrawingSurface, face: FontFace, size: float, lines: Array) -> void:
	var step := 4.0 * SEYES_INTERVAL
	var top := TOP - step  # room above the first writing line for tall letters
	surface.line_width(0.35)
	for line in SEYES_LINES + 1:
		var main := top - line * step
		surface.stroke_color(SEYES_MAIN)
		draw_line(surface, LEFT, main, RIGHT, main)
		if line < SEYES_LINES:
			surface.stroke_color(SEYES_FINE)
			for fine in range(1, 4):
				draw_line(surface, LEFT, main - fine * SEYES_INTERVAL, RIGHT, main - fine * SEYES_INTERVAL)
	surface.stroke_color(SEYES_MARGIN)
	surface.line_width(0.6)
	draw_line(surface, SEYES_MARGIN_LINE, top + step / 2.0, SEYES_MARGIN_LINE, top - SEYES_LINES * step)
	# The caterpillar, top left, in the room above the ruling.
	draw_picture(surface, "caterpillar", LEFT, top + step / 2.0 + CATERPILLAR_HEIGHT + 1.0 * MM, CATERPILLAR_HEIGHT)
	for index in lines.size():
		var baseline := top - (index + 1) * step
		for copy: Array in lines[index]:
			face.draw(surface, copy[0], baseline, copy[1], size, copy[2])


## Each piece on a line of its own, as ``[[piece] for piece in pieces]``.
static func _one_a_line(pieces: Array) -> Array:
	return pieces.map(func(piece: BookletContent.Styled) -> Array: return [piece])
