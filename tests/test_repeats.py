"""Syllables and words repeated for want of more (content.arranged): shuffled,
never beside or under themselves (the PO's rule, 2026-11-17)."""

from collections import Counter

import pytest

from conftest import add_chapter
from kalulu_booklets import content
from kalulu_booklets.content import Styled, arranged
from kalulu_booklets.pack import load


def _grid(items, count, columns, seed="seed"):
    texts = [item.text for item in arranged([Styled(text) for text in items], count, columns, seed)]
    return texts, [texts[start:start + columns] for start in range(0, count, columns)]


SHAPES = [(2, 2, 8), (3, 3, 12), (3, 6, 12), (4, 3, 12), (4, 4, 16), (5, 3, 15), (7, 6, 24), (12, 6, 36)]


@pytest.mark.parametrize("distinct, columns, count", SHAPES)
def test_a_repeat_is_never_beside_itself_nor_under_itself(distinct, columns, count):
    texts, rows = _grid("abcdefghijkl"[:distinct], count, columns)
    assert all(left != right for row in rows for left, right in zip(row, row[1:]))
    assert all(texts[index] != texts[index - columns] for index in range(columns, count))


@pytest.mark.parametrize("distinct, columns, count", SHAPES)
def test_every_item_comes_up_as_often_as_another(distinct, columns, count):
    texts, _ = _grid("abcdefghijkl"[:distinct], count, columns)
    times = Counter(texts)
    assert len(times) == distinct and max(times.values()) - min(times.values()) <= 1


def test_the_first_round_keeps_its_order():
    texts, _ = _grid("abcd", 12, 3)
    assert texts[:4] == list("abcd")


def test_as_many_rows_as_items_put_each_once_in_every_column():
    _, rows = _grid("abcd", 16, 4)
    assert all(sorted(column) == list("abcd") for column in zip(*rows))


def test_the_same_pack_prints_the_same_grid():
    assert _grid("abcde", 30, 6) == _grid("abcde", 30, 6)


def test_enough_items_are_not_repeated():
    assert _grid("abcdef", 6, 3)[0] == list("abcdef")


def test_an_adapted_grid_is_arranged_for_its_own_columns(pack_folder):
    # Three syllables in 6 columns, printed in 3 by an adapted version: in the
    # pack's arrangement each would sit under itself.
    add_chapter(pack_folder, 3, [3, 4, 5], SyllableCount=12, SyllableColumns=6)
    chapter = next(chapter for chapter in content.booklet(load(pack_folder), 1).chapters if chapter.chapter.lesson == 3)
    in_three = [item.text for item in chapter.syllables_in(3)]
    assert len(in_three) == 12 and all(in_three[index] != in_three[index - 3] for index in range(3, 12))
    assert chapter.syllables_in(6) is chapter.syllables


def test_a_syllable_picked_twice_is_one_item_of_a_round():
    # "la le la le al al", then rounds of three: each comes up as often.
    texts, _ = _grid(["la", "le", "la", "le", "al", "al"], 18, 6)
    assert Counter(texts) == {"la": 6, "le": 6, "al": 6}
    assert all(texts[index] != texts[index - 6] for index in range(6, 18))
