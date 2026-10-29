# Artwork

The characters the booklets print are the Kalulu game's own: each is one frame
of a minigame's sprite sheet in
[Kalulu-Frontend](https://github.com/Excello-Recherche-Education/Kalulu-Frontend),
trimmed to its drawing and reduced to 400 pixels at most. They are Excello's,
under the same license as this repository and the game:
**Creative Commons Attribution-ShareAlike 4.0 International**, copyright (c)
2023 Excello.

| File | Printed on | From Kalulu-Frontend | Frame |
|---|---|---|---|
| `parakeet.png` | the fluency test, under its bubble | `assets/minigames/parakeets/graphic/green_parakeet_spritesheet.png` | row 1, column 1 of 8 × 8 |
| `penguin.png` | above a chapter's penguin tables | `assets/minigames/penguin/graphic/penguin.png` | row 1, column 1 of 8 × 5 |
| `caterpillar.png` | the writing pages, top left | `assets/minigames/caterpillar/graphics/caterpillar_spritesheet.png` | row 1, column 1 of 8 × 6 |

Taken from Kalulu-Frontend commit `d5f8b006`. The previous booklets printed
other drawings of the same characters, whose origin is not recorded, so they
are not used here.

The fluency test's two stopwatches are not an image: the generator draws them
(`layout._stopwatch()`).
