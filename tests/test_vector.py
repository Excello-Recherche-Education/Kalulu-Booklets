"""The cover's vector artwork (vector.py): read from art/, drawn as filled paths."""

import pytest

from kalulu_booklets import layout, vector


@pytest.mark.parametrize("name", ["kalulu-logo", "cover-star"])
def test_the_cover_artwork_reads(name):
    drawing = vector.read(layout.ART / f"{name}.svg")
    assert drawing.shapes and drawing.width > 0 and drawing.height > 0


def test_the_logo_keeps_its_translucent_cheeks():
    drawing = vector.read(layout.ART / "kalulu-logo.svg")
    assert sorted({round(shape.opacity, 2) for shape in drawing.shapes}) == [0.2, 0.39, 1.0]


def test_a_path_command_it_does_not_read_is_refused(tmp_path):
    svg = tmp_path / "relative.svg"
    svg.write_text('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">'
                   '<path fill="#000000" d="M0 0 l5 5 Z"/></svg>')
    with pytest.raises(ValueError, match="does not read"):
        vector.read(svg)


def test_an_element_it_does_not_read_is_refused(tmp_path):
    svg = tmp_path / "circle.svg"
    svg.write_text('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">'
                   '<circle cx="5" cy="5" r="5"/></svg>')
    with pytest.raises(ValueError, match="circle"):
        vector.read(svg)
