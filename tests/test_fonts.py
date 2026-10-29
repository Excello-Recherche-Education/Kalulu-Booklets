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


def test_a_replacing_font_must_be_in_the_folder(tmp_path):
    shutil.copytree(pinned_or_skip(), tmp_path / "fonts")
    (tmp_path / "xx_XX").mkdir()
    pack_file = tmp_path / "xx_XX" / "language.db"
    assert fonts.find(pack_file, {"cursive": "marelle/Marelle2-Regular.ttf"}) == tmp_path / "fonts"
    with pytest.raises(fonts.FontError, match="andika/Andika-Regular.ttf"):
        fonts.find(pack_file, {"script": "andika/Andika-Regular.ttf"})


def test_a_replacing_font_prints_its_role():
    folder = pinned_or_skip()
    faces = fonts.load(folder, (("cursive", "marelle/MarelleBaton-Regular.ttf"),))
    assert faces.cursive.file == "marelle/MarelleBaton-Regular.ttf"
    assert faces.script.file == fonts.SCRIPT
    assert faces.cursive.name != fonts.load(folder).cursive.name


def test_a_letter_a_font_lacks_is_noted_but_one_it_composes_is_not():
    faces = fonts.load(pinned_or_skip(), (("script_black", "marelle/Marelle2-Regular.ttf"),))
    # Marelle has no precomposed "á": HarfBuzz prints it as "a" and an accent.
    faces.script_black.shape("canción")
    assert not faces.script_black.missing
    faces.script_black.shape("ŋa")
    assert faces.script_black.missing == {"ŋ"}
    notes = fonts.missing_notes(faces, {"script_black": "Loops"})
    assert notes == ["the black script font, Loops (fonts/marelle/Marelle2-Regular.ttf), has no ŋ: printed as an empty box"]


def test_an_empty_text_has_no_glyphs():
    faces = fonts.load(pinned_or_skip())
    assert faces.script.shape("") == () and faces.script.width("", 12) == 0
