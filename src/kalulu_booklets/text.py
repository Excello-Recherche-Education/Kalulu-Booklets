"""How booklet text is cut into words, exactly as the Prof Tool cuts it.

The Prof Tool matches the text a chapter prints to the pack's ``Words`` word by
word, case ignored (``BookletData.words_of()`` in Kalulu-ProfTool). The
generator must cut at the same places, or a word the Prof Tool found would lose
its decomposition here, and with it its grey silent letters.
"""

from __future__ import annotations

from collections.abc import Container

# BookletData.SEPARATORS in Kalulu-ProfTool: the Sentence List's parser, plus
# the typography of a story. An apostrophe cuts too, so "l'ours" is "l" + "ours".
SEPARATORS = "'’!()[]{};:\"\\,<>./?@#$%^&*_~«»…–—|"

# The Prof Tool also cuts at these, and nowhere else: a no-break space does not.
_BLANKS = " \n\t"
_CUTS = frozenset(SEPARATORS + _BLANKS)

# The euphonic t of "a-t-il", which is no word.
_EUPHONIC = "t"


def word_spans(text: str, words: Container[str] = ()) -> list[tuple[int, int]]:
    """The (start, end) of every word of ``text``, in order.

    A hyphenated form is one word when ``words`` (lowercased spellings: the
    pack's ``Words``, usually) has it, "tam-tam" or "arc-en-ciel"; otherwise it
    is the words between its hyphens, "as-tu" being "as" and "tu", and the
    euphonic t of "a-t-il" is left out (``BookletData.hyphenated_words()``).
    """
    spans: list[tuple[int, int]] = []
    start = -1
    for index, character in enumerate(text):
        if character in _CUTS:
            if start >= 0:
                spans.extend(_hyphenated(text, start, index, words))
                start = -1
        elif start < 0:
            start = index
    if start >= 0:
        spans.extend(_hyphenated(text, start, len(text), words))
    return spans


def _hyphenated(text: str, start: int, end: int, words: Container[str]) -> list[tuple[int, int]]:
    token = text[start:end]
    if "-" not in token or lower(token) in words:
        return [(start, end)]
    parts: list[tuple[int, int]] = []
    part_start = start
    for index in range(start, end + 1):
        if index == end or text[index] == "-":
            if index > part_start:
                parts.append((part_start, index))
            part_start = index + 1
    return [(part_start, part_end) for position, (part_start, part_end) in enumerate(parts)
            if not (0 < position < len(parts) - 1 and lower(text[part_start:part_end]) == _EUPHONIC)]


def words_of(text: str, words: Container[str] = ()) -> list[str]:
    """The words of ``text``, lowercased, in order (see ``word_spans()``)."""
    return [lower(text[start:end]) for start, end in word_spans(text, words)]


def lower(text: str) -> str:
    """Lowercase, one character for one, so that positions still match."""
    return "".join(_one_for_one(character, character.lower()) for character in text)


def upper(text: str) -> str:
    """Uppercase, one character for one: "ß" stays "ß" rather than become "SS"."""
    return "".join(_one_for_one(character, character.upper()) for character in text)


def _one_for_one(original: str, changed: str) -> str:
    return changed if len(changed) == 1 else original
