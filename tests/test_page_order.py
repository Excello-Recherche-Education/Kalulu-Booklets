"""The order of a chapter's pages, the same in every version."""

import pytest

from conftest import add_chapter, execute
from kalulu_booklets import content, fonts, layout
from kalulu_booklets.adapted import AdaptedLayout
from kalulu_booklets.pack import load
from kalulu_booklets.versions import VERSIONS

pytestmark = pytest.mark.skipif(not (fonts.PINNED / fonts.CURSIVE).is_file(),
                                reason="kalulu-languages/ has no fonts/ at its pinned commit")


@pytest.mark.parametrize("version", [version for version in VERSIONS.values() if version.writing], ids=lambda v: v.name)
def test_a_story_comes_after_the_writing_pages(pack_folder, monkeypatch, version):
    chapter = add_chapter(pack_folder, 2, [2], Title="L l", SentencePages=-1)
    execute(pack_folder, "INSERT INTO BookletEntries (ChapterID, Part, Position, Text, Text2, Header) "
                         "VALUES (?, 3, 0, 'la', '', 0)", chapter)
    execute(pack_folder, "INSERT INTO BookletEntries (ChapterID, Part, Position, Text, Text2, Header) "
                         "VALUES (?, 5, 0, 'la', '', 0)", chapter)
    execute(pack_folder, "INSERT INTO BookletStories (ChapterID, Position, Title, Text) VALUES (?, 0, 'Luna', ?)",
            chapter, "La lune.")

    kind = AdaptedLayout if version.adapted else layout.Layout
    calls = []
    for name in ("writing", "story", "fluency"):
        original = getattr(kind, name)
        monkeypatch.setattr(kind, name,
                            lambda self, *args, _name=name, _original=original: (calls.append(_name),
                                                                                  _original(self, *args))[1])
    layout.layout_for(content.booklet(load(pack_folder), 1), fonts.load(fonts.PINNED), version).run()
    assert calls == ["writing", "story", "fluency"]
