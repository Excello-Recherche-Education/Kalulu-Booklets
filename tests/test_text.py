from kalulu_booklets.text import lower, upper, word_spans, words_of


def test_cuts_where_the_prof_tool_cuts():
    assert words_of("L'ours, «Salut» — dit-il… (oui)") == ["l", "ours", "salut", "dit-il", "oui"]
    assert words_of("l’île|la mer") == ["l", "île", "la", "mer"]


def test_a_no_break_space_does_not_cut():
    assert words_of("a b c") == ["a b", "c"]


def test_spans_point_into_the_text():
    text = "La lune."
    assert [text[start:end] for start, end in word_spans(text)] == ["La", "lune"]


def test_case_changes_keep_positions():
    assert upper("straße") == "STRAßE"
    assert len(lower("İstanbul")) == len("İstanbul")
