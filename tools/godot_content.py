"""Writes what the Python generator reads from every pack and puts in every
chapter, for the Godot port's tests to compare against (Kalulu-Main's
docs/BOOKLETS-GODOT-PORT.md, phase 3: ``ChapterContent`` identical to Python's
for every pack, booklet and series).

    .venv/bin/python tools/godot_content.py [pack folder ...]

By default every ``xx_XX`` pack of ``kalulu-languages/``. One file per pack,
``project/tests/generated/content/<locale>.json``, holding the pack as
``pack.load()`` reads it and every booklet of every series it prints as
``content.booklet()`` makes it.

Unlike ``godot_fixtures.py``'s, these files are not committed: they follow the
packs, which move with every pointer bump, so they are written again wherever the
tests run (the *Godot Tests* workflow does it before running GUT). Paths are
written relative to the pack's folder, so they compare across machines.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "project" / "tests" / "generated" / "content"
sys.path.insert(0, str(ROOT / "src"))

from kalulu_booklets import content as contents  # noqa: E402
from kalulu_booklets import pack as packs  # noqa: E402
from kalulu_booklets.content import ChapterContent, Paragraph, Styled, TableRow  # noqa: E402

# The grids an adapted version may print in, besides the chapter's own.
COLUMNS = (1, 2, 3, 4, 5)


def relative(path: Path | None, pack: packs.Pack) -> str | None:
    return None if path is None else path.relative_to(pack.path.parent).as_posix()


def styled(item: Styled) -> dict:
    return {"text": item.text, "grey": sorted(item.grey), "silent": sorted(item.silent),
            "tints": [list(tint) for tint in item.tints]}


def paragraph(item: Paragraph) -> dict:
    return {"font": item.font, "lines": [[styled(piece) for piece in line] for line in item.lines]}


def row(item: TableRow) -> dict:
    return {"left": styled(item.left), "right": styled(item.right), "bold": item.bold}


def chapter(item: packs.Chapter) -> dict:
    return {
        "id": item.id, "lesson": item.lesson, "position": item.position, "booklet": item.booklet,
        "title": item.title, "image_gp_id": item.image_gp_id, "grey_silent": item.grey_silent,
        "overrides": item.overrides, "gp_ids": item.gp_ids, "image_id": item.image_id,
        "sentences": [[sentence.sentence_id, sentence.brk] for sentence in item.sentences],
        "entries": {str(part): [[entry.text, entry.text2, entry.header] for entry in entries]
                    for part, entries in item.entries.items()},
        "stories": [[story.title, story.text] for story in item.stories],
        "name": item.name,
    }


def chapter_content(item: ChapterContent, pack: packs.Pack) -> dict:
    return {
        "chapter": item.chapter.id,
        "title": item.title,
        "syllables": [styled(piece) for piece in item.syllables],
        "syllable_columns": item.syllable_columns,
        "words": [styled(piece) for piece in item.words],
        "word_columns": item.word_columns,
        "paragraphs": [paragraph(piece) for piece in item.paragraphs],
        "sentence_pool": [[sentence_id, styled(piece)] for sentence_id, piece in item.sentence_pool],
        "sentence_fonts": list(item.sentence_fonts),
        "sentence_pages": item.sentence_pages,
        "tables": [[row(piece) for piece in table] for table in item.tables],
        "writing": item.writing,
        "writing_font": item.writing_font,
        "writing_models": item.writing_models,
        "writing_tracings": item.writing_tracings,
        "fluency": [styled(piece) for piece in item.fluency],
        "stories": [[title, [styled(piece) for piece in paragraphs]] for title, paragraphs in item.stories],
        "sentences_teaching": sorted(item.sentences_teaching),
        "picture": relative(item.picture, pack),
        "syllable_choice": [styled(piece) for piece in item.syllable_choice],
        "word_choice": [styled(piece) for piece in item.word_choice],
        "has_chapter_page": item.has_chapter_page(),
        "is_empty": item.is_empty(),
        "syllables_in": {str(columns): [styled(piece) for piece in item.syllables_in(columns)] for columns in COLUMNS},
        "words_in": {str(columns): [styled(piece) for piece in item.words_in(columns)] for columns in COLUMNS},
    }


def pack_dump(pack: packs.Pack) -> dict:
    items = lambda table: {str(key): [item.text, item.exception, item.reading, item.booklet_only,  # noqa: E731
                                      list(item.gp_ids), item.lesson, item.uppercase]
                           for key, item in table.items()}
    return {
        "locale": pack.locale,
        "gps": {str(key): [gp.grapheme, gp.phoneme, gp.type, gp.exception, gp.lesson]
                for key, gp in pack.gps.items()},
        "words": items(pack.words),
        "syllables": items(pack.syllables),
        "sentences": {str(key): [sentence.text, list(sentence.word_ids), sentence.exception, sentence.reading,
                                 sentence.booklet_only, sentence.uppercase]
                      for key, sentence in pack.sentences.items()},
        "settings": pack.settings,
        "chapters": [chapter(item) for item in pack.chapters],
        "words_by_text": pack.words_by_text,
        "syllables_by_text": pack.syllables_by_text,
        "fonts": {role: [font.name, font.file] for role, font in pack.fonts.items()},
        "images": {str(key): [image.name, image.file] for key, image in pack.images.items()},
        "made_chapters_for": pack.made_chapters_for,
        "series": list(pack.series),
        "versions": list(pack.versions),
        "capitals": pack.capitals,
        "booklets": pack.booklets(),
        "pictures": {str(key): relative(pack.picture(key), pack) for key in pack.gps},
        "chapter_pictures": {str(item.id): relative(pack.chapter_picture(item), pack) for item in pack.chapters},
    }


def dump(folder: Path) -> dict:
    pack = packs.load(folder)
    booklets = {}
    for series in pack.series:
        for number in pack.booklets():
            booklet = contents.booklet(pack, number, series)
            booklets[f"{series}/{number}"] = {
                "locale": booklet.locale, "number": booklet.number, "cursive": booklet.cursive,
                "notes": booklet.notes,
                "chapters": [chapter_content(item, pack) for item in booklet.chapters],
            }
    return {"pack": pack_dump(pack), "booklets": booklets}


def main(arguments: list[str]) -> int:
    folders = [Path(argument) for argument in arguments] or sorted(
        path for path in (ROOT / "kalulu-languages").glob("??_??") if (path / "language.db").is_file())
    if not folders:
        print("no pack found: is kalulu-languages/ checked out?", file=sys.stderr)
        return 1
    OUT.mkdir(parents=True, exist_ok=True)
    for folder in folders:
        data = dump(folder)
        path = OUT / f"{data['pack']['locale']}.json"
        path.write_text(json.dumps(data, ensure_ascii=False) + "\n", encoding="utf-8")
        print(f"wrote {path.relative_to(ROOT)} ({path.stat().st_size // 1024} KB)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
