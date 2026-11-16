"""Font measurements for the mockups, read from the installed font files with fontTools.

`ui_width` measures chrome text in the system font (SF, opsz 17) so that labels can be checked
against their columns; `glyph` gives advance and ink bounds in em for the two compared fonts.
"""

from __future__ import annotations

from functools import cache

from fontTools.pens.boundsPen import BoundsPen
from fontTools.ttLib import TTCollection, TTFont
from fontTools.varLib.models import normalizeLocation, piecewiseLinearMap
from fontTools.varLib.varStore import VarStoreInstancer

SF = TTFont("/System/Library/Fonts/SFNS.ttf")
FACES: dict[str, TTFont] = {
    "a": TTCollection("/System/Library/Fonts/HelveticaNeue.ttc").fonts[0],
    "b": TTFont("/System/Library/Fonts/Supplemental/Arial.ttf"),
}
_CMAP = {k: f.getBestCmap() for k, f in FACES.items()}
_SETS = {k: f.getGlyphSet() for k, f in FACES.items()}
_SF_CMAP = SF.getBestCmap()


@cache
def _sf_instancer(weight: int) -> VarStoreInstancer:
    axes = {a.axisTag: (a.minValue, a.defaultValue, a.maxValue) for a in SF["fvar"].axes}
    loc = normalizeLocation({"opsz": 17, "wght": weight, "wdth": 100, "GRAD": 400}, axes)
    if "avar" in SF:
        loc = {k: piecewiseLinearMap(v, SF["avar"].segments[k]) for k, v in loc.items()}
    return VarStoreInstancer(SF["HVAR"].table.VarStore, SF["fvar"].axes, loc)


def ui_width(text: str, size: float, weight: int = 400) -> float:
    """Width in px of `text` in the system font. Tabular figures are no wider than these."""
    hvar = SF["HVAR"].table
    inst = _sf_instancer(weight)
    order = SF.getGlyphOrder()
    total = 0.0
    for ch in text:
        name = _SF_CMAP.get(ord(ch), ".notdef")
        base = SF["hmtx"][name][0]
        idx = hvar.AdvWidthMap.mapping[name] if hvar.AdvWidthMap else order.index(name)
        total += base + inst[idx]
    return total * size / SF["head"].unitsPerEm


def has(side: str, ch: str) -> bool:
    return ord(ch) in _CMAP[side]


@cache
def glyph(side: str, ch: str) -> dict[str, float] | None:
    """Advance, side bearings and ink bounds in em; None when the font has no glyph."""
    name = _CMAP[side].get(ord(ch))
    if name is None:
        return None
    upm = FACES[side]["head"].unitsPerEm
    adv = FACES[side]["hmtx"][name][0]
    pen = BoundsPen(_SETS[side])
    _SETS[side][name].draw(pen)
    x0, y0, x1, y1 = pen.bounds or (0, 0, 0, 0)
    return {
        "adv": adv / upm, "lsb": x0 / upm, "rsb": (adv - x1) / upm, "x1": x1 / upm,
        "y0": y0 / upm, "y1": y1 / upm, "adv_u": adv, "lsb_u": x0, "rsb_u": adv - x1,
    }  # fmt: skip


def text_width(side: str, text: str, size: float) -> float:
    f = FACES[side]
    return sum(f["hmtx"][_CMAP[side][ord(c)]][0] for c in text) * size / f["head"].unitsPerEm


if __name__ == "__main__":
    for t, s, w in [("Tracking +0.004 em", 11, 400), ("Size ×0.977", 11, 400), ("Link A and B", 11, 400),
                    ("Only A", 11, 400), ("Shared", 11, 400), ("26.616", 13, 400), ("auto", 13, 400),
                    ("Optimize", 11, 400), ("COMMERCIAL AT", 20, 600),
                    ("LATIN CAPITAL LETTER K WITH HOOK", 20, 600), ("Frequency", 13, 400), ("Differences", 11, 400)]:
        print(f"{t!r:40} {s}px w{w}: {ui_width(t, s, w):.1f}")
    print(text_width("a", "Helvetica Neue", 26), text_width("b", "Arial", 26))
    print(glyph("a", "@"), glyph("b", "@"), glyph("a", "Ƙ"), glyph("b", "Ƙ"))
