from kalulu_booklets.text import lower, upper, word_spans, words_of


def test_cuts_where_the_prof_tool_cuts():
    assert words_of("L'ours, «Salut» — dit-il… (oui)") == ["l", "ours", "salut", "dit", "il", "oui"]
    assert words_of("l’île|la mer") == ["l", "île", "la", "mer"]


def test_a_hyphenated_word_stays_whole_only_when_it_is_a_word():
    words = {"tam-tam", "arc-en-ciel", "grand-mère"}
    assert words_of("Le Tam-tam de grand-mère", words) == ["le", "tam-tam", "de", "grand-mère"]
    assert words_of("Un arc-en-ciel, as-tu vu ?", words) == ["un", "arc-en-ciel", "as", "tu", "vu"]
    assert words_of("grand mère", words) == ["grand", "mère"]


def test_the_euphonic_t_is_no_word():
    assert words_of("A-t-il dit, fera-t-il") == ["a", "il", "dit", "fera", "il"]
    assert words_of("t-shirt") == ["t", "shirt"]
    text = "a-t-il"
    assert [text[start:end] for start, end in word_spans(text)] == ["a", "il"]


def test_a_no_break_space_does_not_cut():
    assert words_of("a b c") == ["a b", "c"]


def test_spans_point_into_the_text():
    text = "La lune."
    assert [text[start:end] for start, end in word_spans(text)] == ["La", "lune"]


def test_case_changes_keep_positions():
    assert upper("straße") == "STRAßE"
    assert len(lower("İstanbul")) == len("İstanbul")
