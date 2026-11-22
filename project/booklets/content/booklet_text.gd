class_name BookletText
extends RefCounted
## How booklet text is cut into words, exactly as the Prof Tool cuts it.
##
## The Prof Tool matches the text a chapter prints to the pack's ``Words`` word
## by word, case ignored (``BookletData.words_of()`` in Kalulu-ProfTool). The
## generator must cut at the same places, or a word the Prof Tool found would
## lose its decomposition here, and with it its grey silent letters.

## BookletData.SEPARATORS in Kalulu-ProfTool: the Sentence List's parser, plus
## the typography of a story. An apostrophe cuts too, so "l'ours" is "l" + "ours".
const SEPARATORS := "'’!()[]{};:\"\\,<>./?@#$%^&*_~«»…–—|¡¿"

## The Prof Tool also cuts at these, and nowhere else: a no-break space does not.
const _BLANKS := " \n\t"

## The euphonic t of "a-t-il", which is no word.
const _EUPHONIC := "t"

static var _cuts: Dictionary = {}


## The [start, end] of every word of ``text``, in order.
##
## A hyphenated form is one word when ``words`` (lowercased spellings: the
## pack's ``Words``, usually, as a Dictionary keyed by spelling) has it,
## "tam-tam" or "arc-en-ciel"; otherwise it is the words between its hyphens,
## "as-tu" being "as" and "tu", and the euphonic t of "a-t-il" is left out
## (``BookletData.hyphenated_words()``).
static func word_spans(text: String, words: Dictionary = {}) -> Array:
	if _cuts.is_empty():
		for character in SEPARATORS + _BLANKS:
			_cuts[character] = true
	var spans: Array = []
	var start := -1
	for index in text.length():
		if _cuts.has(text[index]):
			if start >= 0:
				spans.append_array(_hyphenated(text, start, index, words))
				start = -1
		elif start < 0:
			start = index
	if start >= 0:
		spans.append_array(_hyphenated(text, start, text.length(), words))
	return spans


static func _hyphenated(text: String, start: int, end: int, words: Dictionary) -> Array:
	var token := text.substr(start, end - start)
	if not token.contains("-") or words.has(lower(token)):
		return [[start, end]]
	var parts: Array = []
	var part_start := start
	for index in range(start, end + 1):
		if index == end or text[index] == "-":
			if index > part_start:
				parts.append([part_start, index])
			part_start = index + 1
	var kept: Array = []
	for position in parts.size():
		var part: Array = parts[position]
		if 0 < position and position < parts.size() - 1 \
				and lower(text.substr(part[0], part[1] - part[0])) == _EUPHONIC:
			continue
		kept.append(part)
	return kept


## The words of ``text``, lowercased, in order (see ``word_spans()``).
static func words_of(text: String, words: Dictionary = {}) -> Array[String]:
	var out: Array[String] = []
	for span: Array in word_spans(text, words):
		out.append(lower(text.substr(span[0], span[1] - span[0])))
	return out


## Lowercase, one character for one, so that positions still match.
static func lower(text: String) -> String:
	return PythonUnicode.lower(text)


## Uppercase, one character for one: "ß" stays "ß" rather than become "SS".
static func upper(text: String) -> String:
	return PythonUnicode.upper(text)
