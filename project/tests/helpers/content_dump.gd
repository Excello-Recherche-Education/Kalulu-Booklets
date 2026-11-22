extends RefCounted
## The pack and its chapters' content as tools/godot_content.py writes them
## from the Python generator, key for key, so the two can be compared.


static func styled(item: BookletContent.Styled) -> Dictionary:
	return {"text": item.text, "grey": _sorted(item.grey), "silent": _sorted(item.silent), "tints": item.tints}


static func styled_list(items: Array) -> Array:
	return items.map(func(item: BookletContent.Styled) -> Dictionary: return styled(item))


static func chapter(item: BookletPack.Chapter) -> Dictionary:
	var entries := {}
	for part: int in item.entries:
		entries[str(part)] = item.entries[part].map(func(entry: BookletPack.Entry) -> Array:
			return [entry.text, entry.text2, entry.header])
	return {
		"id": item.id, "lesson": item.lesson, "position": item.position, "booklet": item.booklet,
		"title": item.title, "image_gp_id": item.image_gp_id, "grey_silent": item.grey_silent,
		"overrides": item.overrides, "gp_ids": item.gp_ids, "image_id": item.image_id,
		"sentences": item.sentences.map(func(sentence: BookletPack.ChapterSentence) -> Array:
			return [sentence.sentence_id, sentence.brk]),
		"entries": entries,
		"stories": item.stories.map(func(story: BookletPack.Story) -> Array: return [story.title, story.text]),
		"name": item.name(),
	}


static func chapter_content(item: BookletContent.ChapterContent, pack: BookletPack) -> Dictionary:
	var syllables_in := {}
	var words_in := {}
	for columns in [1, 2, 3, 4, 5]:
		syllables_in[str(columns)] = styled_list(item.syllables_in(columns))
		words_in[str(columns)] = styled_list(item.words_in(columns))
	return {
		"chapter": item.chapter.id,
		"title": item.title,
		"syllables": styled_list(item.syllables),
		"syllable_columns": item.syllable_columns,
		"words": styled_list(item.words),
		"word_columns": item.word_columns,
		"paragraphs": item.paragraphs.map(func(paragraph: BookletContent.Paragraph) -> Dictionary:
			return {"font": paragraph.font, "lines": paragraph.lines.map(func(line: Array) -> Array:
				return styled_list(line))}),
		"sentence_pool": item.sentence_pool.map(func(pair: Array) -> Array: return [pair[0], styled(pair[1])]),
		"sentence_fonts": item.sentence_fonts,
		"sentence_pages": item.sentence_pages,
		"tables": item.tables.map(func(table: Array) -> Array:
			return table.map(func(row: BookletContent.TableRow) -> Dictionary:
				return {"left": styled(row.left), "right": styled(row.right), "bold": row.bold})),
		"writing": item.writing,
		"writing_font": item.writing_font,
		"writing_models": item.writing_models,
		"writing_tracings": item.writing_tracings,
		"fluency": styled_list(item.fluency),
		"stories": item.stories.map(func(story: Array) -> Array: return [story[0], styled_list(story[1])]),
		"sentences_teaching": _sorted(item.sentences_teaching),
		"picture": relative(item.picture, pack),
		"syllable_choice": styled_list(item.syllable_choice),
		"word_choice": styled_list(item.word_choice),
		"has_chapter_page": item.has_chapter_page(),
		"is_empty": item.is_empty(),
		"syllables_in": syllables_in,
		"words_in": words_in,
	}


static func pack_dump(pack: BookletPack) -> Dictionary:
	var items := func(table: Dictionary) -> Dictionary:
		var out := {}
		for key: int in table:
			var item: BookletPack.Item = table[key]
			out[str(key)] = [item.text, item.exception, item.reading, item.booklet_only, item.gp_ids, item.lesson,
					item.uppercase]
		return out
	var gps := {}
	var pictures := {}
	for key: int in pack.gps:
		var gp: BookletPack.GP = pack.gps[key]
		gps[str(key)] = [gp.grapheme, gp.phoneme, gp.type, gp.exception, gp.lesson]
		pictures[str(key)] = relative(pack.picture(key), pack)
	var sentences := {}
	for key: int in pack.sentences:
		var sentence: BookletPack.Sentence = pack.sentences[key]
		sentences[str(key)] = [sentence.text, sentence.word_ids, sentence.exception, sentence.reading,
				sentence.booklet_only, sentence.uppercase]
	var fonts := {}
	for role: String in pack.fonts:
		fonts[role] = [pack.fonts[role].name, pack.fonts[role].file]
	var images := {}
	for key: int in pack.images:
		images[str(key)] = [pack.images[key].name, pack.images[key].file]
	var chapter_pictures := {}
	for item in pack.chapters:
		chapter_pictures[str(item.id)] = relative(pack.chapter_picture(item), pack)
	return {
		"locale": pack.locale,
		"gps": gps,
		"words": items.call(pack.words),
		"syllables": items.call(pack.syllables),
		"sentences": sentences,
		"settings": pack.settings,
		"chapters": pack.chapters.map(func(item: BookletPack.Chapter) -> Dictionary: return chapter(item)),
		"words_by_text": pack.words_by_text,
		"syllables_by_text": pack.syllables_by_text,
		"fonts": fonts,
		"images": images,
		"made_chapters_for": pack.made_chapters_for,
		"series": pack.series(),
		"versions": pack.versions(),
		"capitals": pack.capitals(),
		"booklets": pack.booklets(),
		"pictures": pictures,
		"chapter_pictures": chapter_pictures,
	}


static func booklet(item: BookletContent.Booklet, pack: BookletPack) -> Dictionary:
	return {"locale": item.locale, "number": item.number, "cursive": item.cursive, "notes": item.notes,
			"chapters": item.chapters.map(func(content: BookletContent.ChapterContent) -> Dictionary:
				return chapter_content(content, pack))}


static func relative(path: String, pack: BookletPack) -> Variant:
	return null if path.is_empty() else path.trim_prefix(pack.folder + "/")


## Where ``actual`` first differs from ``expected`` (a JSON value Python
## wrote), as a path and the two values; "" when they agree. Numbers compare
## by value: JSON gives floats, the port ints.
static func difference(expected: Variant, actual: Variant, path: String = "") -> String:
	if expected is Dictionary and actual is Dictionary:
		for key: Variant in expected:
			if not actual.has(key):
				return "%s: %s is missing" % [path, key]
			var found := difference(expected[key], actual[key], "%s/%s" % [path, key])
			if not found.is_empty():
				return found
		for key: Variant in actual:
			if not expected.has(key):
				return "%s: %s is not expected" % [path, key]
		return ""
	if expected is Array and actual is Array:
		for index in mini(expected.size(), actual.size()):
			var found := difference(expected[index], actual[index], "%s[%d]" % [path, index])
			if not found.is_empty():
				return found
		if expected.size() != actual.size():
			return "%s: %d items, expected %d" % [path, actual.size(), expected.size()]
		return ""
	if (expected is float or expected is int) and (actual is float or actual is int) and not actual is bool:
		return "" if absf(float(expected) - float(actual)) <= 1e-12 * maxf(1.0, absf(float(expected))) \
				else "%s: %s, expected %s" % [path, actual, expected]
	if typeof(expected) == typeof(actual) and expected == actual:
		return ""
	return "%s: %s, expected %s" % [path, var_to_str(actual), var_to_str(expected)]


static func _sorted(positions: Dictionary) -> Array:
	var out := positions.keys()
	out.sort()
	return out
