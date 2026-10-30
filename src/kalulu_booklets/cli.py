"""``kalulu-booklets build``: the booklets of one pack, as PDF files.

    kalulu-booklets build fr_FR                           # the pack pinned in kalulu-languages/
    kalulu-booklets build ../Kalulu-Languages/fr_FR       # any pack folder, saved or not
    kalulu-booklets build fr_FR --booklet 1 --out /tmp/booklets
    kalulu-booklets build fr_FR --version teacher         # one version only (versions.py)

Each version goes to a folder of its own: ``<out>/<locale>/<version>/``, the
printing copies (A4, imposed) beside the A5 ones.

What cannot be printed as the pack asks (a chapter with nothing to print,
sentences that do not fit their pages, a sentence its lesson cannot read yet, a
letter a font has no glyph for) is listed after the files; it never stops the
build. A font the pack names that is not in fonts/ does.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from kalulu_booklets import content, fonts, layout
from kalulu_booklets.pack import PackError, load
from kalulu_booklets.versions import VERSIONS

REPOSITORY = Path(__file__).resolve().parents[2]
PINNED_PACKS = REPOSITORY / "kalulu-languages"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="kalulu-booklets", description="Kalulu reading booklets, as PDF.")
    commands = parser.add_subparsers(dest="command", required=True)
    build = commands.add_parser("build", help="write the booklets of one pack")
    build.add_argument("pack", help="a locale of kalulu-languages/ (fr_FR), a pack folder, or its language.db")
    build.add_argument("--booklet", type=int, action="append",
                       help="only this booklet; may be repeated (default: every booklet)")
    build.add_argument("--version", choices=list(VERSIONS), action="append",
                       help="only this version; may be repeated (default: every version)")
    build.add_argument("--out", type=Path, default=REPOSITORY / "build",
                       help="folder to write to (default: build/)")
    arguments = parser.parse_args(argv)

    try:
        pack = load(_pack_path(arguments.pack))
        replaced = {role: font.file for role, font in pack.fonts.items()}
        faces = fonts.load(fonts.find(pack.path, replaced), tuple(sorted(replaced.items())))
    except (PackError, fonts.FontError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 2

    numbers = arguments.booklet or pack.booklets()
    if not numbers:
        print(f"{pack.path}: no lesson, so no booklet chapter", file=sys.stderr)
        return 1
    if pack.made_chapters_for and not any(chapter.id > 0 for chapter in pack.chapters):
        print(f"{pack.locale} has no booklet chapter: one per lesson, from its GPs, all in booklet 1")
    elif pack.made_chapters_for:
        print(f"{pack.locale}: lesson(s) {', '.join(map(str, pack.made_chapters_for))} have no chapter: "
              "each gets one from its GPs")
    missing = [number for number in numbers if number not in pack.booklets()]
    if missing:
        print(f"error: {pack.locale} has no booklet {', '.join(map(str, missing))}; "
              f"it has {', '.join(map(str, pack.booklets())) or 'none'}", file=sys.stderr)
        return 2

    versions = [VERSIONS[name] for name in arguments.version or VERSIONS]
    if any(version.teacher for version in versions) and not any(
            pack.picture(chapter.image_gp_id) for chapter in pack.chapters):
        print(f"{pack.locale}: no Look & Learn image found (not checked out?): the teacher version has no teacher page")
    notes: list[str] = []
    for number in numbers:
        # The content is the same in every version; only the layout differs.
        # A note from one version's layout is said once, with the versions
        # that gave it when not all of them did.
        said: dict[str, list[str]] = {}
        for version in versions:
            booklet = content.booklet(pack, number)
            folder = arguments.out / pack.locale / version.name
            path = folder / version.file_name(pack.locale, number)
            imposed = folder / version.file_name(pack.locale, number, imposed=True) if version.printed else None
            pages = layout.write(booklet, faces, path, version, imposed)
            print(f"{path}  ({pages} pages, {len(booklet.chapters)} chapter(s))")
            if imposed is not None:
                print(f"{imposed}  ({pages // 2} A4 sheet sides, for printing)")
            for note in booklet.notes:
                said.setdefault(note, []).append(version.name)
        for note, by in said.items():
            which = "" if len(by) == len(versions) else f" [{', '.join(by)}]"
            notes.append(f"booklet {number}, {note}{which}")
    notes.extend(fonts.missing_notes(faces, {role: font.name for role, font in pack.fonts.items()}))
    if notes:
        print("\nTo look at:")
        for note in notes:
            print(f"  - {note}")
    return 0


def _pack_path(argument: str) -> Path:
    """A bare locale means the pack pinned in kalulu-languages/."""
    path = Path(argument).expanduser()
    if not path.exists() and "/" not in argument and (PINNED_PACKS / argument).is_dir():
        return PINNED_PACKS / argument
    return path
