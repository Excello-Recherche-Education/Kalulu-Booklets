import shutil

import pytest

from kalulu_booklets import fonts


def pinned_or_skip():
    if not (fonts.PINNED / fonts.CURSIVE).is_file():
        pytest.skip("kalulu-languages/ has no fonts/ at its pinned commit")
    return fonts.PINNED


def test_the_fonts_beside_the_pack_come_first(tmp_path):
    shutil.copytree(pinned_or_skip(), tmp_path / "fonts")
    (tmp_path / "xx_XX").mkdir()
    assert fonts.find(tmp_path / "xx_XX" / "language.db") == tmp_path / "fonts"


def test_without_them_the_pinned_ones_are_used(tmp_path):
    pinned = pinned_or_skip()
    assert fonts.find(tmp_path / "xx_XX" / "language.db") == pinned


def test_a_missing_font_is_an_error(tmp_path, monkeypatch):
    monkeypatch.setattr(fonts, "PINNED", tmp_path / "nowhere")
    with pytest.raises(fonts.FontError, match="Kalulu-Languages keeps them in fonts/"):
        fonts.find(tmp_path / "xx_XX" / "language.db")


def test_mulish_is_converted_and_marelle_joins():
    faces = fonts.load(pinned_or_skip())
    # Kalulu's Mulish is CFF; once converted, every character keeps its glyph.
    assert [glyph.char for glyph in faces.script.shape("Il lit")] == list("Il lit")
    # Marelle's joins are contextual alternates: some glyphs have no character
    # of their own, and ReportLab embeds them under private-use ones.
    assert any(0xE000 <= ord(glyph.char) <= 0xF8FF for glyph in faces.cursive.shape("la lune"))
