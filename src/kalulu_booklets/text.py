"""How booklet text is cut into words, exactly as the Prof Tool cuts it.

The Prof Tool matches the text a chapter prints to the pack's ``Words`` word by
word, case ignored (``BookletData.words_of()`` in Kalulu-ProfTool). The
generator must cut at the same places, or a word the Prof Tool found would lose
its decomposition here, and with it its grey silent letters.
"""

from __future__ import annotations

# BookletData.SEPARATORS in Kalulu-ProfTool: the Sentence List's parser, plus
# the typography of a story. An apostrophe cuts too, so "l'ours" is "l" + "ours".
SEPARATORS = "'’!()[]{};:\"\\,<>./?@#$%^&*_~«»…–—|"

# The Prof Tool also cuts at these, and nowhere else: a no-break space does not.
_BLANKS = " \n\t"
_CUTS = frozenset(SEPARATORS + _BLANKS)


def word_spans(text: str) -> list[tuple[int, int]]:
    """The (start, end) of every word of ``text``, in order."""
    spans: list[tuple[int, int]] = []
    start = -1
    for index, character in enumerate(text):
        if character in _CUTS:
            if start >= 0:
                spans.append((start, index))
                start = -1
        elif start < 0:
            start = index
    if start >= 0:
        spans.append((start, len(text)))
    return spans


def words_of(text: str) -> list[str]:
    """The words of ``text``, lowercased, in order."""
    return [lower(text[start:end]) for start, end in word_spans(text)]


def lower(text: str) -> str:
    """Lowercase, one character for one, so that positions still match."""
    return "".join(_one_for_one(character, character.lower()) for character in text)


def upper(text: str) -> str:
    """Uppercase, one character for one: "ß" stays "ß" rather than become "SS"."""
    return "".join(_one_for_one(character, character.upper()) for character in text)


def _one_for_one(original: str, changed: str) -> str:
    return changed if len(changed) == 1 else original
