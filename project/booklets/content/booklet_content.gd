class_name BookletContent
extends RefCounted
## What each chapter of a booklet prints, decided from the pack.
##
## This is where the PO's rules are applied (Kalulu-Main
## ``docs/BOOKLETS-FROM-PACKS.md``, and ``SCHEMA.md`` "The reading booklets"):
## the automatic syllables and words, the entries in capitals, the paragraphs
## and their fonts, the silent letters to print in grey. Nothing here knows
## about pages; the layout places what comes out of it.
##
## Ported from the Python generator's ``content.py``: it gave the same content,
## to the letter and to the grid, on every pack.

const SCRIPT := "script"
const CURSIVE := "cursive"

## What a multi-letter grapheme is coloured as (Styled.tints), in the versions
## that colour them (BookletVersion): one the chapter teaches, one an earlier
## lesson taught, or one whose colour changes because it touches another
## coloured one ("chou": ch then ou), so that each stays visible; "qu" always
## has that colour.
const OWN := "own"
const EARLIER := "earlier"
const TOUCHING := "touching"

## What a repeat costs where it lands, in arranged(): beside itself on its row,
## or under itself, is what the PO asked to avoid (2026-11-17); at the end of
## one row and the start of the next it is barely seen; two cells away on its
## row ("d e d") still reads as a repeat; in a column it held in an earlier
## row, only a little.
const _BESIDE := 100
const _ABOVE := 100
const _ACROSS_ROWS := 10
const _NEAR := 5
const _SAME_COLUMN := 1
const _ATTEMPTS := 200
const _CHEAPEST := 0.7
const _ROWS_LOOKED_AT := 5


## Text to print, with what its letters are: the positions to print in grey
## where the chapter asks for it (``grey``), every silent letter whatever the
## chapter asks (``silent``), and its multi-letter graphemes, as [start, end,
## kind] spans (``tints``). ``grey`` and ``silent`` are sets: position -> true.
class Styled:
	var text: String
	var grey: Dictionary
	var silent: Dictionary
	var tints: Array

	func _init(styled_text: String, grey_positions: Dictionary = {}, silent_positions: Dictionary = {},
			tint_spans: Array = []) -> void:
		text = styled_text
		grey = grey_positions
		silent = silent_positions
		tints = tint_spans

	func upper() -> Styled:
		return Styled.new(BookletText.upper(text), grey, silent, tints)

	## The characters ``start`` to ``end``, with what is marked among them.
	func slice(start: int, end: int) -> Styled:
		var inside := func(positions: Dictionary) -> Dictionary:
			var out := {}
			for index: int in positions:
				if start <= index and index < end:
					out[index - start] = true
			return out
		var cut: Array = []
		for tint: Array in tints:
			if tint[0] < end and tint[1] > start:
				cut.append([maxi(tint[0], start) - start, mini(tint[1], end) - start, tint[2]])
		return Styled.new(BookletContent.substring(text, start, end), inside.call(grey), inside.call(silent), cut)

	## Pieces one space apart, as sentences sharing a line.
	static func joined(pieces: Array) -> Styled:
		var text_parts := PackedStringArray()
		var grey_set := {}
		var silent_set := {}
		var tint_spans: Array = []
		var offset := 0
		for piece: Styled in pieces:
			if not text_parts.is_empty():
				text_parts.append(" ")
				offset += 1
			text_parts.append(piece.text)
			for index: int in piece.grey:
				grey_set[offset + index] = true
			for index: int in piece.silent:
				silent_set[offset + index] = true
			for tint: Array in piece.tints:
				tint_spans.append([offset + tint[0], offset + tint[1], tint[2]])
			offset += piece.text.length()
		return Styled.new("".join(text_parts), grey_set, silent_set, tint_spans)

	## Split at the line breaks a sentence may hold (SCHEMA.md).
	func lines() -> Array[Styled]:
		var pieces: Array[Styled] = []
		var ends: Array[int] = []
		for index in text.length():
			if text[index] == "\n":
				ends.append(index)
		ends.append(text.length())
		var start := 0
		for end in ends:
			var raw := BookletContent.substring(text, start, end)
			var first := start + raw.length() - PythonUnicode.lstrip(raw).length()
			pieces.append(slice(first, first + PythonUnicode.strip(raw).length()))
			start = end + 1
		return pieces


class Paragraph:
	var font: String
	## Printed lines, each an Array of the Styled sentences that share it.
	var lines: Array

	func _init(paragraph_font: String, paragraph_lines: Array) -> void:
		font = paragraph_font
		lines = paragraph_lines


class TableRow:
	var left: Styled
	var right: Styled
	var bold: bool

	func _init(left_cell: Styled, right_cell: Styled, is_bold: bool) -> void:
		left = left_cell
		right = right_cell
		bold = is_bold


class ChapterContent:
	var chapter: BookletPack.Chapter
	var title: Array[String] = []
	var syllables: Array[Styled] = []
	var syllable_columns: int
	var words: Array[Styled] = []
	var word_columns: int
	var paragraphs: Array[Paragraph] = []
	## When the chapter picks no sentence: the ones the layout may choose from,
	## in order, as many as fit (each a paragraph of its own), those flagged
	## Uppercase already in capitals: [sentence ID, Styled] each. The fonts
	## paragraphs alternate between.
	var sentence_pool: Array = []
	var sentence_fonts: Array[String] = []
	## Pages the sentences may take after the one they start on; 0 for none.
	var sentence_pages: int
	## Tables, each an Array of TableRow.
	var tables: Array = []
	var writing: Array[String] = []
	var writing_font: String
	var writing_models: int
	var writing_tracings: int
	var fluency: Array[Styled] = []
	## [title, Array of Styled paragraphs] each.
	var stories: Array = []
	## The pool's sentences that hold one of the chapter's GPs, as a set: the
	## others are earlier lessons' content, taken only to fill the pages.
	var sentences_teaching: Dictionary = {}
	## The chapter's picture for the teacher's page: its own booklet image,
	## else the Look & Learn image of its ImageGPID; "" when it has none, or the
	## pack's images are not checked out.
	var picture := ""
	## The syllables and words chosen, each once: what ``syllables`` and
	## ``words`` repeat when there are too few (see arranged()).
	var syllable_choice: Array[Styled] = []
	var word_choice: Array[Styled] = []

	## Whether it prints a chapter page: a chapter holding only stories, as the
	## Argentine booklet 3 does, starts on its first story.
	func has_chapter_page() -> bool:
		return not (title.is_empty() and syllables.is_empty() and words.is_empty() and paragraphs.is_empty()
				and sentence_pool.is_empty() and tables.is_empty())

	func is_empty() -> bool:
		return not has_chapter_page() and writing.is_empty() and fluency.is_empty() and stories.is_empty()

	## The syllables for a grid of ``columns``: an adapted version prints them
	## in fewer, and a repeat must not land in the column it held above.
	func syllables_in(columns: int) -> Array[Styled]:
		if columns == syllable_columns:
			return syllables
		return BookletContent.arranged(syllable_choice, syllables.size(), columns,
				BookletContent.seed_of(chapter, BookletPack.SYLLABLES))

	func words_in(columns: int) -> Array[Styled]:
		if columns == word_columns:
			return words
		return BookletContent.arranged(word_choice, words.size(), columns,
				BookletContent.seed_of(chapter, BookletPack.WORDS))


class Booklet:
	var locale: String
	var number: int
	var cursive: bool
	var chapters: Array[ChapterContent] = []
	## What a person should look at: content that cannot be printed as asked.
	var notes: Array[String] = []

	func _init(booklet_locale: String, booklet_number: int, is_cursive: bool) -> void:
		locale = booklet_locale
		number = booklet_number
		cursive = is_cursive


## Booklet ``number`` of the ``series`` given, "script" or "cursive" (by
## default the first the language prints, SCHEMA.md ``ScriptSeries`` /
## ``CursiveSeries``). The cursive series also prints its titles, sentences and
## writing pages in cursive; capitals are printed in the script series only, as
## the printed Brazilian booklets have them.
static func booklet(pack: BookletPack, number: int, series: String = "") -> Booklet:
	if series.is_empty():
		series = pack.series()[0]
	var cursive := series == CURSIVE
	var capitals := pack.capitals() and not cursive
	var result := Booklet.new(pack.locale, number, cursive)
	for chapter in pack.chapters:
		if chapter.booklet != number:
			continue
		var notes: Array[String] = []
		var content := _chapter(pack, chapter, notes, cursive, capitals)
		for note in notes:
			result.notes.append("%s: %s" % [chapter.name(), note])
		if content.is_empty():
			result.notes.append("%s: prints nothing, so it has no page" % chapter.name())
			continue
		result.chapters.append(content)
	return result


static func _chapter(pack: BookletPack, chapter: BookletPack.Chapter, notes: Array[String], cursive: bool,
		capitals: bool) -> ChapterContent:
	var grey := chapter.grey_silent
	if chapter.image_id != null and pack.chapter_picture(chapter).is_empty():
		var image: BookletPack.BookletImage = pack.images.get(chapter.image_id)
		notes.append(("its booklet image %s cannot be printed: missing, not a PNG or JPEG, or not checked out "
				+ "(Git LFS); its teacher page is left out") % ("booklet_images/" + image.file if image != null
				else str(chapter.image_id)))
	var content := ChapterContent.new()
	content.chapter = chapter
	content.syllable_columns = int(pack.setting(chapter, "SyllableColumns"))
	content.word_columns = int(pack.setting(chapter, "WordColumns"))
	var syllable_count := _whole_rows(int(pack.setting(chapter, "SyllableCount")), content.syllable_columns,
			"Syllable", notes)
	var word_count := _whole_rows(int(pack.setting(chapter, "WordCount")), content.word_columns, "Word", notes)
	content.syllable_choice = _picked(pack, chapter, BookletPack.SYLLABLES, syllable_count, notes, capitals)
	content.word_choice = _picked(pack, chapter, BookletPack.WORDS, word_count, notes, capitals)
	content.syllables = arranged(content.syllable_choice, syllable_count, content.syllable_columns,
			seed_of(chapter, BookletPack.SYLLABLES))
	content.words = arranged(content.word_choice, word_count, content.word_columns,
			seed_of(chapter, BookletPack.WORDS))
	# -1 prints no sentence at all.
	var sentence_pages := int(pack.setting(chapter, "SentencePages"))
	if sentence_pages < 0 and not chapter.sentences.is_empty():
		notes.append("SentencePages is -1, so its %d sentence(s) are not printed" % chapter.sentences.size())
	if sentence_pages >= 0 and chapter.sentences.is_empty():
		var pool := _sentence_pool(pack, chapter, grey, capitals)
		content.sentence_pool = pool[0]
		content.sentences_teaching = pool[1]
		if content.sentence_pool.is_empty():
			notes.append("no sentence is readable at this lesson")

	if not PythonUnicode.strip(chapter.title).is_empty():
		for line in chapter.title.split("\n"):
			content.title.append(PythonUnicode.strip(line))
	if sentence_pages >= 0:
		content.paragraphs = _paragraphs(pack, chapter, grey, notes, cursive, capitals)
	content.sentence_fonts.assign([_paragraph_font(pack, chapter, 0, cursive),
			_paragraph_font(pack, chapter, 1, cursive)])
	content.sentence_pages = maxi(sentence_pages, 0)
	content.tables = _tables(pack, chapter, grey)
	for entry: BookletPack.Entry in chapter.entries.get(BookletPack.WRITING, []):
		content.writing.append(entry.text)
	content.writing_font = CURSIVE if cursive else SCRIPT
	content.writing_models = int(pack.setting(chapter, "WritingModels"))
	content.writing_tracings = int(pack.setting(chapter, "WritingTracings"))
	for entry: BookletPack.Entry in chapter.entries.get(BookletPack.FLUENCY, []):
		content.fluency.append(styled(pack, entry.text, grey, [], false, chapter))
	for story in chapter.stories:
		var paragraphs: Array[Styled] = []
		for paragraph in _story_paragraphs(story.text):
			paragraphs.append(styled(pack, paragraph, grey, [], false, chapter))
		content.stories.append([PythonUnicode.strip(story.title), paragraphs])
	content.picture = pack.chapter_picture(chapter)
	return content


# --- Syllables and words ---------------------------------------------------------

## A grid fills every row it starts (the PO's rule, 2026-11-09): 7 words in 3
## columns leave one alone on the last row, so 6 are printed. A count below one
## row is kept: it prints as one row of its own.
static func _whole_rows(count: int, columns: int, kind: String, notes: Array[String]) -> int:
	if columns < 1 or count <= columns or _python_mod(count, columns) == 0:
		return count
	var whole := count - _python_mod(count, columns)
	notes.append("%sCount is %d in %d columns: %d are printed, so that every row is full" % [kind, count, columns, whole])
	return whole


## Up to ``count`` syllables or words, each once (SCHEMA.md): the chapter's
## picks first, in their order, the last ones left out past the count. Short
## of it, the rest is filled from the pack (``_automatic``); when that runs out
## too, arranged() repeats what was chosen until the count is reached.
static func _picked(pack: BookletPack, chapter: BookletPack.Chapter, part: int, count: int, notes: Array[String],
		capitals: bool) -> Array[Styled]:
	var kind := "syllable" if part == BookletPack.SYLLABLES else "word"
	var column := "SyllableCount" if part == BookletPack.SYLLABLES else "WordCount"
	var entries: Array = chapter.entries.get(part, [])
	# Syllables are never coloured: only words get their graphemes' colours.
	var tinted: BookletPack.Chapter = chapter if part == BookletPack.WORDS else null
	var listed: Array[Styled] = []
	for entry: BookletPack.Entry in entries:
		listed.append(_in_capitals(styled(pack, entry.text, chapter.grey_silent, [], part == BookletPack.SYLLABLES,
				tinted), capitals and _pick_flagged(pack, entry.text, part)))
	if listed.size() > count:
		notes.append("%d %ss picked and %d printed: the last %d are left out"
				% [listed.size(), kind, count, listed.size() - count])
		return listed.slice(0, count)
	# A pick printed "la Lune" is the pack's "lune": it is not filled in twice.
	var picked := {}
	for entry: BookletPack.Entry in entries:
		for word in BookletText.words_of(entry.text, pack.words_by_text):
			picked[word] = true
	var items: Dictionary = pack.syllables if part == BookletPack.SYLLABLES else pack.words
	var chosen: Array[Styled] = listed.duplicate()
	for item: BookletPack.Item in _automatic(pack, items, chapter):
		if chosen.size() >= count:
			break
		if not picked.has(BookletText.lower(item.text)):
			chosen.append(_in_capitals(_styled_item(pack, item, chapter.grey_silent, tinted),
					capitals and item.uppercase))
	if count != 0 and chosen.is_empty():
		notes.append("no %s readable at this lesson holds one of the chapter's GPs" % kind)
		return [] as Array[Styled]
	# A syllable grid repeats its syllables by design; words only for want of more.
	if part == BookletPack.WORDS and chosen.size() < count:
		notes.append("%s is %d, and only %d words qualify: they are repeated" % [column, count, chosen.size()])
	return chosen


## A fixed seed: the same pack prints the same booklet every time.
static func seed_of(chapter: BookletPack.Chapter, part: int) -> String:
	return "%d:%d" % [chapter.id, part]


## ``count`` items read row by row in ``columns``: ``choice`` once in its
## order, then, when there are too few, again in shuffled rounds (the PO's
## rule, 2026-11-17), each using every item once so that none comes up more
## than another. No item sits beside itself or under itself where that can be
## helped, and as little as can be in a column it held before: of many random
## grids, the one that costs least (``_cost``). The random numbers are
## Python's, from the same seed, so the grids are the ones the PO reviewed.
static func arranged(choice: Array[Styled], count: int, columns: int, seed: String) -> Array[Styled]:
	var result: Array[Styled] = choice.slice(0, count)
	if choice.is_empty() or result.size() == count:
		return result
	# A chapter may pick the same syllable twice: a round holds each spelling
	# once, at its first place, as the last of its kind (a dict in Python).
	var by_key := {}
	for item in choice:
		by_key[BookletText.lower(item.text)] = item
	var distinct: Array[Styled] = []
	distinct.assign(by_key.values())
	if distinct.size() == 1:
		var repeated: Array[Styled] = []
		for index in count:
			repeated.append(result[index % result.size()])
		return repeated
	var keys: Array[String] = []
	for item in distinct:
		keys.append(BookletText.lower(item.text))
	var rng := PythonRandom.new(seed)
	var result_keys: Array[String] = []
	for item in result:
		result_keys.append(BookletText.lower(item.text))
	var best: Array[Styled] = []
	var best_cost := -1
	# A round can corner the next one, so whole grids are compared, not rounds.
	# Fewer attempts for a long grid, which costs more to lay.
	@warning_ignore("integer_division")
	var attempts := mini(_ATTEMPTS, maxi(20, 4800 / count))
	for _attempt in attempts:
		var laid: Array[Styled] = result.duplicate()
		var laid_keys: Array[String] = result_keys.duplicate()
		var cost := 0
		while laid.size() < count:
			cost += _one_round(distinct, keys, mini(distinct.size(), count - laid.size()), laid, laid_keys, columns,
					rng)
		if best_cost < 0 or cost < best_cost:
			best = laid
			best_cost = cost
		if cost == 0:
			break
	return best


## Adds ``size`` of ``items`` to ``laid``, each among those not beside or under
## themselves there: mostly the cheapest, sometimes any of them, since taking
## the cheapest every time walks into the same dead end on every attempt.
## Returns what they cost. ``keys`` and ``laid_keys`` are the items' spellings,
## lowercased, which is how two items are told apart.
static func _one_round(items: Array[Styled], keys: Array[String], size: int, laid: Array[Styled],
		laid_keys: Array[String], columns: int, rng: PythonRandom) -> int:
	var left := items.duplicate()
	var left_keys := keys.duplicate()
	var total := 0
	for _step in size:
		var costs: Array[int] = []
		for key in left_keys:
			costs.append(_cost(key, laid_keys, columns))
		var fitting: Array = []
		for index in costs.size():
			if costs[index] < mini(_BESIDE, _ABOVE):
				fitting.append(index)
		if fitting.is_empty():
			fitting = range(left.size())
		if rng.random() < _CHEAPEST:
			var cheapest: int = costs[fitting[0]]
			for other: int in fitting:
				cheapest = mini(cheapest, costs[other])
			fitting = fitting.filter(func(index: int) -> bool: return costs[index] == cheapest)
		var index: int = rng.choice(fitting)
		total += costs[index]
		laid.append(left.pop_at(index))
		laid_keys.append(left_keys.pop_at(index))
	return total


static func _cost(key: String, sequence: Array[String], columns: int) -> int:
	var position := sequence.size()
	var column := position % columns if columns > 0 else 0
	var cost := 0
	if position > 0 and sequence[-1] == key:
		cost += _BESIDE if column != 0 or columns <= 1 else _ACROSS_ROWS
	if column >= 2 and sequence[-2] == key:
		cost += _NEAR
	if columns > 0 and position >= columns and sequence[position - columns] == key:
		cost += _ABOVE
	if columns > 0:
		# The rows just above: further up, nobody compares.
		for earlier in range(maxi(column, position - _ROWS_LOOKED_AT * columns), position - columns, columns):
			if sequence[earlier] == key:
				cost += _SAME_COLUMN
	return cost


## What fills a chapter's syllables or words (SCHEMA.md): the entries readable
## at its lesson that hold at least one of its GPs. Exceptions are left out, as
## the game leaves them out, and so is an entry with no vowel: such a "word" is
## the elided form a sentence needs ("l" of "l'ours"), never read alone.
## Booklet-only entries first, then in the pack's order; one entry per
## spelling.
static func _automatic(pack: BookletPack, items: Dictionary, chapter: BookletPack.Chapter) -> Array[BookletPack.Item]:
	var taught := {}
	for gp_id in chapter.gp_ids:
		taught[gp_id] = true
	var vowels := {}
	for gp: BookletPack.GP in pack.gps.values():
		if gp.type == BookletPack.VOWEL:
			vowels[gp.id] = true
	var candidates: Array = []
	for item: BookletPack.Item in items.values():
		if not item.exception and item.reading and item.lesson != null and item.lesson <= chapter.lesson \
				and _meets(taught, item.gp_ids) and _meets(vowels, item.gp_ids):
			candidates.append(item)
	candidates = StableSort.sorted(candidates, func(item: BookletPack.Item) -> Array:
		return [not item.booklet_only, item.id])
	var seen := {}
	var chosen: Array[BookletPack.Item] = []
	for item: BookletPack.Item in candidates:
		var key := BookletText.lower(item.text)
		if not seen.has(key):
			seen[key] = true
			chosen.append(item)
	return chosen


static func _in_capitals(item: Styled, flagged: bool) -> Styled:
	return item.upper() if flagged else item


## Whether a chapter's pick prints in capitals (SCHEMA.md, ``Uppercase``): when
## every syllable or word of the pack it is made of is flagged, "la Lune" only
## if both "la" and "lune" are. A word of no list leaves it as written.
static func _pick_flagged(pack: BookletPack, text: String, part: int) -> bool:
	if not pack.capitals():
		return false
	var lists := [[pack.syllables_by_text, pack.syllables], [pack.words_by_text, pack.words]]
	if part == BookletPack.WORDS:
		lists.reverse()
	var spellings := BookletText.words_of(text, pack.words_by_text)
	if spellings.is_empty():
		return false
	for spelling in spellings:
		var flagged := false
		for pair: Array in lists:
			for item_id: int in pair[0].get(spelling, []):
				if pair[1][item_id].uppercase:
					flagged = true
		if not flagged:
			return false
	return true


static func _sentence_text(pack: BookletPack, sentence: BookletPack.Sentence, grey: bool,
		chapter: BookletPack.Chapter, capitals: bool) -> Styled:
	return _in_capitals(styled(pack, sentence.text, grey, sentence.word_ids, false, chapter),
			capitals and sentence.uppercase)


# --- Sentences ---------------------------------------------------------------------

static func _paragraphs(pack: BookletPack, chapter: BookletPack.Chapter, grey: bool, notes: Array[String],
		cursive: bool, capitals: bool) -> Array[Paragraph]:
	var paragraphs: Array[Paragraph] = []
	var found: Array = []
	for item in chapter.sentences:
		var sentence: BookletPack.Sentence = pack.sentences.get(item.sentence_id)
		if sentence == null:
			notes.append("sentence %d is not in the Sentence List" % item.sentence_id)
		else:
			found.append([item, sentence])
	for pair: Array in found:
		var item: BookletPack.ChapterSentence = pair[0]
		var sentence: BookletPack.Sentence = pair[1]
		var lesson: Variant = _sentence_lesson(pack, sentence)
		if lesson == null:
			notes.append("sentence \"%s\" is never readable" % sentence.text)
		elif lesson > chapter.lesson:
			notes.append("sentence \"%s\" is readable from lesson %d" % [sentence.text, lesson])
		var pieces := _sentence_text(pack, sentence, grey, chapter, capitals).lines()
		if paragraphs.is_empty() or item.brk == BookletPack.NEW_PARAGRAPH:
			paragraphs.append(Paragraph.new(_paragraph_font(pack, chapter, paragraphs.size(), cursive), [[]]))
		elif item.brk == BookletPack.NEW_LINE:
			paragraphs[-1].lines.append([])
		paragraphs[-1].lines[-1].append(pieces[0])
		for piece in pieces.slice(1):
			paragraphs[-1].lines.append([piece])
	return paragraphs


## What a chapter that picks no sentence chooses from: the sentences readable
## at its lesson, exceptions left out. Those with a word holding one of its GPs
## come first, then the others, since the point is to fill the pages; within
## each, booklet-only ones first, then in the pack's order. The layout takes as
## many as fit, whole. Also the IDs of those holding one of its GPs: the layout
## says when it had to print others. Returns [pool, set of those IDs].
static func _sentence_pool(pack: BookletPack, chapter: BookletPack.Chapter, grey: bool, capitals: bool) -> Array:
	var taught := {}
	for gp_id in chapter.gp_ids:
		taught[gp_id] = true
	var ranked: Array = []
	for sentence: BookletPack.Sentence in pack.sentences.values():
		var lesson: Variant = _sentence_lesson(pack, sentence)
		if sentence.exception or not sentence.reading or lesson == null or lesson > chapter.lesson:
			continue
		var teaches := false
		for word_id in sentence.word_ids:
			if _meets(taught, pack.words[word_id].gp_ids):
				teaches = true
				break
		ranked.append([[not teaches, not sentence.booklet_only, sentence.id], sentence])
	ranked = StableSort.sorted(ranked, func(pair: Array) -> Array: return pair[0])
	var teaching := {}
	var pool: Array = []
	for pair: Array in ranked:
		var sentence: BookletPack.Sentence = pair[1]
		if not pair[0][0]:
			teaching[sentence.id] = true
		pool.append([sentence.id, _sentence_text(pack, sentence, grey, chapter, capitals)])
	return [pool, teaching]


## Script and cursive alternate by paragraph, unless the chapter asks for one
## only; the script series prints everything in script.
static func _paragraph_font(pack: BookletPack, chapter: BookletPack.Chapter, index: int, cursive: bool) -> String:
	if not cursive:
		return SCRIPT
	var font := int(pack.setting(chapter, "SentenceFont"))
	if font == BookletPack.SCRIPT:
		return SCRIPT
	if font == BookletPack.CURSIVE:
		return CURSIVE
	var first := CURSIVE if int(pack.setting(chapter, "SentenceFirstFont")) == BookletPack.CURSIVE else SCRIPT
	var other := SCRIPT if first == CURSIVE else CURSIVE
	return first if index % 2 == 0 else other


static func _sentence_lesson(pack: BookletPack, sentence: BookletPack.Sentence) -> Variant:
	if sentence.word_ids.is_empty():
		return null
	var last := 0
	for word_id in sentence.word_ids:
		var lesson: Variant = pack.words[word_id].lesson if pack.words.has(word_id) else null
		if lesson == null:
			return null
		last = maxi(last, lesson)
	return last


# --- Tables and stories -------------------------------------------------------------

## Two-column tables; a header row is bold and starts a new table.
static func _tables(pack: BookletPack, chapter: BookletPack.Chapter, grey: bool) -> Array:
	var tables: Array = []
	for entry: BookletPack.Entry in chapter.entries.get(BookletPack.TABLES, []):
		if entry.header or tables.is_empty():
			tables.append([])
		tables[-1].append(TableRow.new(styled(pack, entry.text, grey, [], false, chapter),
				styled(pack, entry.text2, grey, [], false, chapter), entry.header))
	return tables


## Paragraphs are separated by an empty line (SCHEMA.md); a single line break
## inside one is kept. As Python's ``re.split(r"\n\s*\n", text.strip())``:
## a separator runs from a line break to the last line break of the whitespace
## that follows it.
static func _story_paragraphs(text: String) -> Array[String]:
	var whole := PythonUnicode.strip(text)
	var pieces: Array[String] = []
	var start := 0
	var index := 0
	while index < whole.length():
		if whole[index] == "\n":
			var last := -1
			var scan := index + 1
			while scan < whole.length() and PythonUnicode.is_space(whole[scan]):
				if whole[scan] == "\n":
					last = scan
				scan += 1
			if last >= 0:
				pieces.append(substring(whole, start, index))
				start = last + 1
				index = last + 1
				continue
		index += 1
	pieces.append(substring(whole, start, whole.length()))
	var out: Array[String] = []
	for piece in pieces:
		if not PythonUnicode.strip(piece).is_empty():
			out.append(PythonUnicode.strip(piece))
	return out


# --- Silent letters -------------------------------------------------------------------

## ``text`` with what its letters are: its silent letters, in ``grey`` too when
## ``grey`` is set, and, given the ``chapter`` it prints in, its multi-letter
## graphemes to colour.
##
## Each word is matched as the Prof Tool matches it: to the sentence's own
## words (``linked``, from WordsInSentences) when they follow in order, else to
## ``Words`` by its spelling, case ignored. A word's silent letters are its GPs
## of type 0; a word that is in no list, or whose GPs do not spell it, has none.
static func styled(pack: BookletPack, text: String, grey: bool, linked: Array[int] = [], syllables_too: bool = false,
		chapter: BookletPack.Chapter = null) -> Styled:
	var silent := {}
	var tints: Array = []
	var next_linked := 0
	for span: Array in BookletText.word_spans(text, pack.words_by_text):
		var start: int = span[0]
		var end: int = span[1]
		var spelling := substring(text, start, end)
		var word := BookletText.lower(spelling)
		var item: BookletPack.Item = null
		if next_linked < linked.size() and pack.words.has(linked[next_linked]) \
				and BookletText.lower(pack.words[linked[next_linked]].text) == word:
			item = pack.words[linked[next_linked]]
			next_linked += 1
		else:
			item = _by_spelling(pack, word, syllables_too)
		if item != null:
			var spans := _gp_spans(pack, item, spelling)
			for offset in _silent_of(pack, spans):
				silent[start + offset] = true
			if chapter != null:
				for tint: Array in _tints(pack, spans, chapter):
					tints.append([start + tint[0], start + tint[1], tint[2]])
	return Styled.new(text, silent if grey else {}, silent, tints)


static func _styled_item(pack: BookletPack, item: BookletPack.Item, grey: bool,
		chapter: BookletPack.Chapter = null) -> Styled:
	var spans := _gp_spans(pack, item, item.text)
	var silent := {}
	for offset in _silent_of(pack, spans):
		silent[offset] = true
	return Styled.new(item.text, silent if grey else {}, silent, _tints(pack, spans, chapter) if chapter != null else [])


## The word spelled ``word``; of several, the one readable first, which is the
## one a child is likeliest to have met.
static func _by_spelling(pack: BookletPack, word: String, syllables_too: bool) -> BookletPack.Item:
	var candidates: Array = []
	for item_id: int in pack.words_by_text.get(word, []):
		candidates.append(pack.words[item_id])
	if candidates.is_empty() and syllables_too:
		for item_id: int in pack.syllables_by_text.get(word, []):
			candidates.append(pack.syllables[item_id])
	if candidates.is_empty():
		return null
	var best: BookletPack.Item = null
	var best_key: Array = []
	for item: BookletPack.Item in candidates:
		var key := [item.lesson == null, item.lesson if item.lesson != null else 0, item.exception, item.id]
		if best == null or StableSort.compare(key, best_key) < 0:
			best = item
			best_key = key
	return best


## Where in ``spelling`` each of ``item``'s GPs is, as [start, end, GP ID], or
## nothing when its GPs do not spell it exactly. A hyphen between two of them
## is no GP: "tam-tam" is t-a-m-t-a-m.
static func _gp_spans(pack: BookletPack, item: BookletPack.Item, spelling: String) -> Array:
	var spans: Array = []
	var position := 0
	for index in item.gp_ids.size():
		var gp_id := item.gp_ids[index]
		if index > 0 and substring(spelling, position, position + 1) == "-":
			position += 1
		var gp: BookletPack.GP = pack.gps.get(gp_id)
		if gp == null:
			return []
		var grapheme := BookletText.lower(gp.grapheme)
		if BookletText.lower(substring(spelling, position, position + grapheme.length())) != grapheme:
			return []
		spans.append([position, position + grapheme.length(), gp_id])
		position += grapheme.length()
	return spans if position == spelling.length() else []


static func _silent_of(pack: BookletPack, spans: Array) -> Array[int]:
	var out: Array[int] = []
	for span: Array in spans:
		if pack.gps[span[2]].silent():
			for offset in range(span[0], span[1]):
				out.append(offset)
	return out


## The multi-letter graphemes of a word to colour (Kalulu-Main's
## docs/BOOKLETS-FROM-PACKS.md, section 7): those this chapter's lesson
## teaches, those an earlier lesson taught, and, when two coloured ones touch,
## one of the two in the third colour so that each stays visible. That is the
## second, unless the second is the lesson's own: the lesson's own colour never
## changes, so the one before it does. "qu" always has the third colour. A
## single letter, a doubled one ("ss") and a silent grapheme (grey instead) are
## not coloured.
static func _tints(pack: BookletPack, spans: Array, chapter: BookletPack.Chapter) -> Array:
	var tints: Array = []
	for span: Array in spans:
		var gp: BookletPack.GP = pack.gps[span[2]]
		var grapheme := BookletText.lower(gp.grapheme)
		if gp.silent() or grapheme.length() < 2 or _distinct_letters(grapheme) < 2:
			continue
		var kind := ""
		if chapter.gp_ids.has(span[2]) or (gp.lesson != null and gp.lesson == chapter.lesson):
			kind = OWN
		elif gp.lesson != null and gp.lesson < chapter.lesson:
			kind = EARLIER
		else:
			continue
		var before: Variant = tints[-1] if not tints.is_empty() and tints[-1][1] == span[0] else null
		if grapheme == "qu":
			kind = TOUCHING
		elif before != null and before[2] != TOUCHING:
			if kind != OWN:
				kind = TOUCHING
			elif before[2] != OWN:
				tints[-1] = [before[0], before[1], TOUCHING]
		tints.append([span[0], span[1], kind])
	return tints


## Python's ``text[start:end]``: indices past the end are clamped.
static func substring(text: String, start: int, end: int) -> String:
	start = clampi(start, 0, text.length())
	end = clampi(end, start, text.length())
	return text.substr(start, end - start)


static func _distinct_letters(text: String) -> int:
	var letters := {}
	for character in text:
		letters[character] = true
	return letters.size()


## Whether ``ids`` holds one of the set ``wanted``'s keys.
static func _meets(wanted: Dictionary, ids: Array[int]) -> bool:
	for item_id in ids:
		if wanted.has(item_id):
			return true
	return false


## Python's ``%``, which takes the sign of the divisor.
static func _python_mod(value: int, divisor: int) -> int:
	return posmod(value, divisor) if divisor > 0 else -posmod(-value, -divisor)
