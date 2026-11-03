"""Drawing the vector artwork of ``art/`` (its SVG files) on a page.

The cover's logo and star are kept as SVG, so they print as sharp as the
previous booklets they come from. ReportLab reads no SVG, and these files use
very little of it: filled ``<path>`` elements in absolute ``M``, ``L``, ``C``
and ``Z`` commands, each with a ``fill`` colour, a ``fill-rule`` and at times a
``fill-opacity``, which is what this reads. A file using more is refused
rather than drawn wrong.
"""

from __future__ import annotations

import re
import xml.etree.ElementTree as ElementTree
from dataclasses import dataclass
from pathlib import Path

from reportlab.lib.colors import Color, HexColor
from reportlab.pdfgen.canvas import FILL_EVEN_ODD, FILL_NON_ZERO, Canvas

_SVG = "{http://www.w3.org/2000/svg}"
_COMMANDS = {"M": 2, "L": 2, "C": 6, "Z": 0}
_TOKEN = re.compile(r"[MLCZ]|-?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?")


@dataclass(frozen=True)
class Shape:
    color: Color
    opacity: float
    even_odd: bool
    # (command, its numbers), in the file's units, y pointing down.
    commands: tuple[tuple[str, tuple[float, ...]], ...]


@dataclass(frozen=True)
class Vector:
    width: float
    height: float
    shapes: tuple[Shape, ...]

    def draw(self, canvas: Canvas, left: float, top: float, width: float) -> None:
        """Draws it ``width`` wide, its top-left corner at (``left``, ``top``)."""
        scale = width / self.width
        canvas.saveState()
        canvas.translate(left, top)
        canvas.scale(scale, -scale)
        for shape in self.shapes:
            path = canvas.beginPath()
            for command, numbers in shape.commands:
                if command == "M":
                    path.moveTo(*numbers)
                elif command == "L":
                    path.lineTo(*numbers)
                elif command == "C":
                    path.curveTo(*numbers)
                else:
                    path.close()
            canvas.setFillColor(shape.color)
            canvas.setFillAlpha(shape.opacity)
            canvas.drawPath(path, stroke=0, fill=1, fillMode=FILL_EVEN_ODD if shape.even_odd else FILL_NON_ZERO)
        canvas.restoreState()


def read(path: Path) -> Vector:
    root = ElementTree.parse(path).getroot()
    left, top, width, height = (float(value) for value in root.get("viewBox", "").split())
    if left or top:
        raise ValueError(f"{path.name}: a viewBox not starting at 0 0")
    shapes = []
    for element in root.iter():
        if element.tag == f"{_SVG}svg":
            continue
        if element.tag != f"{_SVG}path":
            raise ValueError(f"{path.name}: <{element.tag.removeprefix(_SVG)}> is not read")
        shapes.append(Shape(HexColor(element.get("fill", "#000000")),
                            float(element.get("fill-opacity", "1")),
                            element.get("fill-rule") == "evenodd",
                            _commands(path, element.get("d", ""))))
    return Vector(width, height, tuple(shapes))


def _commands(path: Path, d: str) -> tuple[tuple[str, tuple[float, ...]], ...]:
    tokens = _TOKEN.findall(d)
    if "".join(tokens).replace(" ", "") != re.sub(r"[\s,]", "", d):
        raise ValueError(f"{path.name}: a path command this does not read in {d[:40]!r}")
    commands = []
    index = 0
    while index < len(tokens):
        command = tokens[index]
        count = _COMMANDS.get(command)
        if count is None:
            raise ValueError(f"{path.name}: a number where a command was expected in {d[:40]!r}")
        operands = tokens[index + 1:index + 1 + count]
        if len(operands) != count or any(operand in _COMMANDS for operand in operands):
            raise ValueError(f"{path.name}: {command} needs {count} numbers in {d[:40]!r}")
        commands.append((command, tuple(float(operand) for operand in operands)))
        index += 1 + count
    return tuple(commands)
