"""The whole way, from a pack to a PDF."""

import re

import pytest

from conftest import add_chapter, execute
from kalulu_booklets import fonts
from kalulu_booklets.cli import main

# The test pack has no Kalulu-Languages checkout around it, so its fonts are
# the pinned ones.
pytestmark = pytest.mark.skipif(not (fonts.PINNED / fonts.CURSIVE).is_file(),
                                reason="kalulu-languages/ has no fonts/ at its pinned commit")


def page_count(path):
    return len(re.findall(rb"/Type\s*/Page[^s]", path.read_bytes()))


def test_builds_one_pdf_per_booklet(pack_folder, tmp_path, capsys):
    first = add_chapter(pack_folder, 2, [2], Title="L l")
    add_chapter(pack_folder, 3, [3, 4, 5], Booklet=2, Title="u n", GreySilent=1)
    for part, text, text2, header in ((3, "lune", "", 0), (4, "la", "une", 1), (5, "lune", "", 0)):
        execute(pack_folder, "INSERT INTO BookletEntries (ChapterID, Part, Position, Text, Text2, Header) "
                             "VALUES (?, ?, 0, ?, ?, ?)", first, part, text, text2, header)
    execute(pack_folder, "INSERT INTO BookletStories (ChapterID, Position, Title, Text) VALUES (?, 0, 'Luna', ?)",
            first, "La lune.\n\nUne lune nue.")

    out = tmp_path / "out"
    assert main(["build", str(pack_folder), "--out", str(out)]) == 0

    for number in (1, 2):
        path = out / "xx_XX" / f"xx_XX-booklet-{number}.pdf"
        assert path.read_bytes().startswith(b"%PDF")
        assert page_count(path) % 4 == 0  # printed on folded sheets
    assert "xx_XX-booklet-1.pdf" in capsys.readouterr().out


def test_says_when_there_is_no_chapter(pack_folder, tmp_path, capsys):
    assert main(["build", str(pack_folder), "--out", str(tmp_path)]) == 1
    assert "no booklet chapter yet" in capsys.readouterr().err


def test_refuses_a_booklet_the_pack_does_not_have(pack_folder, tmp_path, capsys):
    add_chapter(pack_folder, 2, [2], Title="L l")
    assert main(["build", str(pack_folder), "--booklet", "3", "--out", str(tmp_path)]) == 2
    assert "has no booklet 3" in capsys.readouterr().err


def test_sentences_beyond_their_pages_are_said(pack_folder, tmp_path, capsys):
    chapter = add_chapter(pack_folder, 3, [3], SentencePages=1, SyllableCount=0, WordCount=0)
    for position in range(60):
        execute(pack_folder, "INSERT INTO BookletSentences (ChapterID, SentenceID, Position, Break) VALUES (?, 1, ?, 1)",
                chapter, position)
    assert main(["build", str(pack_folder), "--out", str(tmp_path)]) == 0
    assert "take more than 1 page(s) (SentencePages)" in capsys.readouterr().out
