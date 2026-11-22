extends GutTest
## How booklet text is cut into words (BookletText). Ported from the Python
## generator's tests/test_text.py.


func _words(text: String, words: Array = []) -> Array:
	var known := {}
	for word: String in words:
		known[word] = true
	return Array(BookletText.words_of(text, known))


func test_cuts_where_the_prof_tool_cuts() -> void:
	assert_eq(_words("L'ours, «Salut» — dit-il… (oui)"), ["l", "ours", "salut", "dit", "il", "oui"])
	assert_eq(_words("l’île|la mer"), ["l", "île", "la", "mer"])


func test_a_hyphenated_word_stays_whole_only_when_it_is_a_word() -> void:
	var words := ["tam-tam", "arc-en-ciel", "grand-mère"]
	assert_eq(_words("Le Tam-tam de grand-mère", words), ["le", "tam-tam", "de", "grand-mère"])
	assert_eq(_words("Un arc-en-ciel, as-tu vu ?", words), ["un", "arc-en-ciel", "as", "tu", "vu"])
	assert_eq(_words("grand mère", words), ["grand", "mère"])


func test_the_euphonic_t_is_no_word() -> void:
	assert_eq(_words("A-t-il dit, fera-t-il"), ["a", "il", "dit", "fera", "il"])
	assert_eq(_words("t-shirt"), ["t", "shirt"])
	var text := "a-t-il"
	assert_eq(BookletText.word_spans(text).map(func(span: Array) -> String:
		return text.substr(span[0], span[1] - span[0])), ["a", "il"])


func test_a_no_break_space_does_not_cut() -> void:
	assert_eq(_words("a b c"), ["a b", "c"])


func test_spans_point_into_the_text() -> void:
	var text := "La lune."
	assert_eq(BookletText.word_spans(text).map(func(span: Array) -> String:
		return text.substr(span[0], span[1] - span[0])), ["La", "lune"])


func test_case_changes_keep_positions() -> void:
	assert_eq(BookletText.upper("straße"), "STRAßE")
	assert_eq(BookletText.lower("İstanbul").length(), "İstanbul".length())
