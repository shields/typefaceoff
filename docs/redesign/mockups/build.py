"""Generate the static window mockups for the final Typeface/Off design.

Run with `uv run --no-project --with fonttools python3 build.py`. Output is plain HTML
with no scripts and the style sheet inlined; all geometry is in window coordinates (1440x900), so
each block can be checked by reading its numbers. Measured data comes from data.json (written by
data.py) and from the font files through fontdata.py.
"""

from __future__ import annotations

import html
import json
import math
from dataclasses import dataclass, replace
from pathlib import Path

import fontdata as fd

OUT = Path(__file__).parent
DATA = json.loads((OUT / "data.json").read_text(encoding="utf-8"))
CSS = (OUT / "mock.css").read_text(encoding="utf-8")
HN = "Helvetica Neue"
AR = "Arial"
INK = "#1b1c1f"
INK2 = "#5a5e66"
RED = "#b43b43"
BLUE = "#286b9d"
HAIR = "#c9ccd2"
TRACK = "#8e939b"
FAM = {"a": HN, "b": AR}
FIGURE_SPACE = "\u2007"

def ab(letter: str, live: bool = True, cls: str = "", style: str = "") -> str:
    """A letter that labels a font: bold, and red for A or blue for B.

    A font that is None or not installed has nothing to key: its letter is secondary ink.
    """
    tone = f" kl-{letter.lower()}" if live else " kl-off"
    extra = f" {cls}" if cls else ""
    attr = f' style="{style}"' if style else ""
    return f'<b class="kl{tone}{extra}"{attr}>{letter}</b>'


# ---------------------------------------------------------------- numbers


def computed(v: float) -> str:
    """Measured and computed values (automatic leading, em, distances) always show three decimals."""
    return f"{v:.3f}"


def places(*values: float) -> int:
    """Decimals that typed values need, at most three; a pair shows the larger need on both sides."""
    return max(next((d for d in range(3) if abs(v - round(v, d)) < 5e-7), 3) for v in values)


# ---------------------------------------------------------------- icons


def svg(w: int, h: int, body: str, cls: str = "ic") -> str:
    return (
        f'<svg class="{cls}" width="{w}" height="{h}" viewBox="0 0 {w} {h}" fill="none" '
        f'stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round">{body}</svg>'
    )


CHEV = svg(9, 6, '<path d="M1 1l3.5 3.5L8 1"/>')
UPDOWN = svg(8, 12, '<path d="M1 4.5l3-3 3 3M1 7.5l3 3 3-3"/>')
RIGHT = svg(6, 9, '<path d="M1 1l3.5 3.5L1 8"/>')
DOWN = svg(9, 6, '<path d="M1 1l3.5 3.5L8 1"/>')
SEARCH = svg(14, 14, '<circle cx="6" cy="6" r="4.3"/><path d="M9.3 9.3L13 13"/>')
SIDEBAR = svg(18, 14, '<rect x="1" y="1" width="16" height="12" rx="3.2"/><path d="M11.5 1v12"/>')
SWAP = svg(14, 14, '<path d="M4 12.5V1.5M1.5 4L4 1.5 6.5 4M10 1.5v11M7.5 10l2.5 2.5 2.5-2.5"/>')
RESET = svg(12, 12, '<path d="M2.4 6.3a3.7 3.7 0 1 0 1.1-2.9L2 4.9M2 2.2v2.7h2.7"/>')
CHECK = svg(12, 12, '<path d="M2.2 6.4l2.6 2.6 5-5.8"/>')
MINUS = svg(12, 12, '<path d="M2.5 6h7"/>')
PLUS = svg(12, 12, '<path d="M2.5 6h7M6 2.5v7"/>')
WARN = svg(14, 14, '<path d="M7 1.8l5.6 10H1.4zM7 5.6v3.2M7 10.6v.1"/>', "ic warn")


def cb(on: bool, small: bool = False) -> str:
    return f'<i class="c-cb{" sm" if small else ""}{" on" if on else ""}"></i>'


def chk(label: str, on: bool, small: bool = False, extra: str = "") -> str:
    return f'<span class="c-chk{" sm" if small else ""}{extra}">{cb(on, small)}{label}</span>'


def slider(p: float, style: str = "", auto: bool = False) -> str:
    """`auto`: the value is computed, so the track has no filled part and the thumb is an outline."""
    return f'<div class="c-sl{" auto" if auto else ""}" style="--p:{p:.4f};{style}"><i></i><b></b></div>'


def rule(left: float, top: float, width: float, ink: bool = False) -> str:
    return f'<div class="rule{" ink" if ink else ""}" style="left:{left:g}px;top:{top:g}px;width:{width:g}px"></div>'


def page(title: str, body: str) -> str:
    return (
        '<!doctype html>\n<html lang="en"><head><meta charset="utf-8">'
        f"<title>Typeface/Off — {title}</title>\n<style>\n{CSS}</style></head>\n<body>\n<div class=\"win\">\n"
        f'{body}\n<div class="frame"></div>\n</div>\n</body></html>\n'
    )


# ---------------------------------------------------------------- grid


@dataclass(frozen=True)
class Grid:
    """Column positions shared by the specification and the body, for one content width."""

    cw: int  # content width: the window, less the inspector when it is open
    sty: int
    size: int
    wt: int
    ld: int
    tr: int
    typo: int | None
    col: int  # measure of one text column

    @property
    def right(self) -> int:
        return self.cw - 24

    @property
    def half(self) -> int:
        """Where the right-hand column starts: B's text, the values, the overlay's labels."""
        return 64 + self.col + 64

    @property
    def block(self) -> int:
        """Left edge of the Differences block: the last header column."""
        return self.typo or self.tr


WIDE = Grid(cw=1440, sty=384, size=752, wt=840, ld=912, tr=1016, typo=1152, col=624)
NARROW = Grid(cw=1120, sty=320, size=592, wt=680, ld=744, tr=840, typo=None, col=464)


# ---------------------------------------------------------------- toolbar


def toolbar(view: str, prompt: str, inspector: bool = False, matching: bool = False) -> str:
    """System toolbar. It spans the window; the inspector opens beneath it, so nothing here moves."""
    lights = "".join(
        f'<i class="tb-light" style="left:{x}px;background:{c};box-shadow:inset 0 0 0 .5px rgba(0,0,0,.18)"></i>'
        for x, c in ((20, "#ff5f57"), (42, "#febc2e"), (64, "#28c840"))
    )
    segs = "".join(
        f'<span class="{"on" if name == view else ""}{" dim" if matching and name == "Languages" else ""}">{name}</span>'
        for name in ("Text", "Glyph", "Languages")
    )
    lock = " dim" if matching else ""
    return (
        lights
        + f'<div class="tb-pill tb-sample"><span class="row{lock}" style="gap:8px">Queen Alice{UPDOWN}</span></div>'
        + f'<div class="tb-pill tb-seg">{segs}</div>'
        + f'<div class="tb-pill tb-search">{SEARCH}{prompt}</div>'
        + f'<div class="tb-pill tb-insp{" on" if inspector else ""}"><span class="row{lock}">{SIDEBAR}</span></div>'
    )


# ---------------------------------------------------------------- specification


@dataclass(frozen=True)
class Font:
    key: str
    family: str | None  # None: B is set to None
    style: str = "Regular"
    installed: bool = True
    size: float = 22
    weight: str = "400"
    leading: float = 0  # the computed value while `auto`
    auto: bool = True
    tracking: float = 0
    typo: str = "Default"

    @property
    def live(self) -> bool:
        return self.family is not None and self.installed


A_DEFAULT = Font("A", HN, leading=26.616)
B_DEFAULT = Font("B", AR, leading=25.72)

Figures = dict[str, dict[str, str]]


def figures(a: Font, b: Font, before: Font | None = None) -> Figures:
    """Size, leading and tracking of both fonts as shown, keyed "A" and "B" (and "was" for `before`).

    Typed values take as many decimals as the more precise of the pair needs, the same on both
    sides; automatic leading is computed, so a pair with an automatic side shows three. The shorter
    number is padded with figure spaces, so the two are right-aligned and their points line up.
    `before` is B as it was when Match opened: it joins the pair, so "was" has the column's decimals.
    """
    fonts = {f.key: f for f in (a, b) if f.live}
    if before:
        fonts["was"] = before
    out: Figures = {k: {} for k in fonts}
    for name in ("size", "leading", "tracking"):
        values = {k: float(getattr(f, name)) for k, f in fonts.items()}
        d = 3 if name == "leading" and any(f.auto for f in fonts.values()) else places(*values.values())
        width = max(len(f"{v:.{d}f}") for v in values.values())
        for k, v in values.items():
            out[k][name] = f"{v:.{d}f}".rjust(width, FIGURE_SPACE)
    return out


def number(value: str, unit: str, editable: bool = True, strong: bool = False, focus_width: int = 0) -> str:
    """A field is a number over an underline; a locked one has no underline.

    `focus_width` draws the field focused: the ring round its whole cell and the stepper at its end.
    """
    digits = value.lstrip(FIGURE_SPACE)
    pad = value[: len(value) - len(digits)]
    v = f'<b class="sb">{digits}</b>' if strong else digits
    if editable:
        v = f'<span class="c-num">{v}</span>'
    ring = f'<i class="sp-focus" style="width:{focus_width}px">{UPDOWN}</i>' if focus_width else ""
    return f'{ring}{pad}{v}<span class="un"> {unit}</span>'


def spec_row(
    g: Grid,
    f: Font,
    shown: dict[str, str],
    top: int,
    match_button: bool,
    locked: bool = False,
    strong: frozenset[str] = frozenset(),
    comparing: bool = True,
    focus: str = "",
) -> str:
    """One row of the specification.

    `shown` holds the row's numbers as `figures` formats them. `locked` is the Match mode, where
    nothing in the rows is editable. The letter is the colour key: A is red and B is blue, and B's
    is secondary ink without a comparison. `focus` names a focused field.
    """
    xs = [24, 64, g.sty, g.size, g.wt, g.ld, g.tr] + ([g.typo] if g.typo else [])
    widths = [b - a for a, b in zip(xs, xs[1:])] + [96]
    chev = "" if locked else CHEV
    # Each cell: (extra classes, extra style, content).
    cells: list[tuple[str, str, str]] = [("sp-key", "", ab(f.key, f.key == "A" or comparing))]
    if f.family is None:
        cells.append(("sp-fam sys", "", f"None{chev}"))
    elif not f.installed:
        cells.append(("sp-fam sys", "", f"{f.family}{chev}"))
        cells.append(("", "", f"{WARN}Not installed"))
    else:
        cells.append(("sp-fam", f"font-family:'{f.family}'", f"{f.family}{chev}"))
        cells.append(("", "", f'{f.style}{"" if locked else UPDOWN}'))

        def ring(key: str, left: int, right: int) -> int:
            return right - left - 10 if key == focus else 0

        cells.append(("", "", number(shown["size"], "pt", not locked, "size" in strong, ring("size", g.size, g.wt))))
        cells.append(("", "", f'<span class="ro">{f.weight}</span>'))
        if f.auto:
            # Computed, so secondary ink; still a field, so underlined.
            v = shown["leading"] if locked else f'<span class="c-num">{shown["leading"]}</span>'
            cells.append(("", "", f'<span class="ro">{v}</span><span class="un"> auto</span>'))
        else:
            cells.append(("", "", number(shown["leading"], "pt", not locked, "leading" in strong, ring("leading", g.ld, g.tr))))
        cells.append(("", "", number(shown["tracking"], "em", not locked, "tracking" in strong)))
        if g.typo:
            cells.append(("", "", f'{f.typo}{"" if locked else RIGHT}'))
    out = [f'<div class="sp-row" style="top:{top}px;width:{g.cw - 48}px"><i class="sp-strut"></i>']
    for (cls, style, inner), w in zip(cells, widths):
        out.append(f'<span class="sp-c {cls}" style="width:{w}px;{style}">{inner}</span>')
    out.append('<span class="sp-fill"></span>')
    if match_button:
        out.append('<span class="c-btn">Match…</span>')
    out.append("</div>")
    return "".join(out)


def spec(
    g: Grid,
    a: Font,
    b: Font,
    linked: bool = True,
    relations: dict[str, str] | None = None,
    matching: bool = False,
    strong: frozenset[str] = frozenset(),
    focus: str = "",
    before: Font | None = None,
) -> str:
    """Label row, row A, row B and, outside Match mode, the closing ink rule at y 157.

    The label row holds Swap, the link and the column heads, nothing else.
    """
    relations = relations or {}
    comparing = b.live
    shown = figures(a, b, before)
    off = "" if comparing and not matching else " dim"

    def lab(x: int, name: str, key: str = "") -> str:
        # The relation is a pull-down (Make B Equal to A, Make A Equal to B), so it carries a chevron.
        rel = f"&ensp;<b>{relations[key]}</b>{DOWN}" if key in relations else ""
        return f'<span class="sp-lab" style="left:{x}px">{name}{rel}</span>'

    out = [
        f'<span class="c-ib sp-swap{off}">{SWAP}</span>',
        # A disabled link keeps its stored state: suspended, not lost.
        f'<span class="sp-link{off}">{chk("Link A and B", linked, small=True)}</span>',
    ]
    out += [lab(g.size, "Size", "size"), lab(g.wt, "Weight", "weight"), lab(g.ld, "Leading", "leading"), lab(g.tr, "Tracking", "tracking")]
    if g.typo:
        out.append(lab(g.typo, "Typography"))
    out.append(spec_row(g, a, shown["A"], 78, False, matching, comparing=comparing))
    out.append(spec_row(g, b, shown.get("B", {}), 114, comparing and not matching, matching, strong, comparing, focus))
    if not matching:
        out.append(rule(24, 157, g.cw - 48, ink=True))
    return "".join(out)


# ---------------------------------------------------------------- match band


MT_RULE = 233  # the header's closing rule in Match mode; the index line starts one below


def match_band(g: Grid, a: Font, b: Font, before: Font, running: str) -> str:
    """Match mode: the band hangs under row B, inside the header, and closes with the ink rule at 233.

    Three baselines: 171 (Match, the Optimize words), 194.5 (status, "was"), 218 (caveat, actions).
    Optimize is an ink word flush on its column; only Stop, Cancel and Apply are bordered.
    `before` is B as it was when the band opened; every number that differs from it says what it was.
    """
    shown = figures(a, b, before)["was"]
    units = {"size": " pt", "leading": "" if before.auto else " pt", "tracking": " em"}
    was = {k: shown[k].strip(FIGURE_SPACE) + units[k] for k in units if getattr(before, k) != getattr(b, k)}
    out = []
    for key, x in (("size", g.size), ("leading", g.ld), ("tracking", g.tr)):
        if key == running:
            out.append(f'<span class="mt-opt row" style="left:{x}px;gap:6px">Optimizing<i class="c-spin sm"></i></span>')
        else:
            out.append(f'<span class="mt-opt dim" style="left:{x}px">Optimize</span>')
        if key in was:
            out.append(f'<span class="mt-was" style="left:{x}px">was {was[key]}</span>')
    if g.typo:
        out.append(f'<span class="mt-opt dim" style="left:{g.typo}px">Optimize{DOWN}</span>')
    out += [
        '<div class="mt-l1 row"><b class="sb">Match</b>'
        '<span class="t11 sec">Optimize one ' + ab("B") + " setting at a time. Each search keeps your other preview settings.</span></div>",
        '<div class="mt-l2 row"><i class="c-spin"></i><span>Comparing settings…</span>'
        '<span class="sec">Distance 0.203 → 0.187 · 412 evaluations</span>'
        '<span class="c-btn sm" style="margin-left:6px">Stop</span></div>',
        '<div class="mt-note">Experimental visual heuristic using the current sample and Latin diagnostics. '
        "Lower distance is closer; this is not a confidence percentage.</div>",
        # A search is running, so Apply is disabled: Stop and Cancel are the only actions.
        f'<div class="mt-act row" style="right:{1440 - g.right}px"><span class="c-btn">Cancel</span>'
        '<span class="c-btn off">Apply</span></div>',
        rule(24, MT_RULE, g.cw - 48, ink=True),
    ]
    return "".join(out)


# ---------------------------------------------------------------- index line

SCORES: dict[str, dict[str, float]] = DATA["scores"]
MAX_SHAPE = max(s["shape"] for s in SCORES.values())

# The first fifteen are the app's own ranking for Shape + Frequency, read from today's screenshots.
APP_RANK = list("“”/j-,dtq\"—'b3p")


@dataclass(frozen=True)
class Item:
    """One ranked character; both values are 0-1 of the bar's length."""

    ch: str
    measured: float
    weighted: float  # the score the line is ranked by


def ranked_shape_frequency(count: int) -> list[Item]:
    computed = DATA["ranked"]["shape_freq"]
    order = (APP_RANK + [c for c in computed if c not in APP_RANK])[:count]
    # Bar lengths: the computed weighted scores, largest first, laid along the app's order.
    values = sorted((SCORES[c]["shape"] * SCORES[c]["weight"] for c in computed[:count]), reverse=True)
    items = []
    for ch, w in zip(order, values):
        measured = min(MAX_SHAPE, w / SCORES[ch]["weight"])
        items.append(Item(ch, measured / MAX_SHAPE, w / MAX_SHAPE))
    return items


def percentiles(key: str) -> dict[str, float]:
    """Percentile rank of each character's score, ties sharing the mean rank, as data.py computes it."""
    order = sorted(SCORES, key=lambda c: SCORES[c][key])
    out: dict[str, float] = {}
    start = 0
    while start < len(order):
        end = start + 1
        while end < len(order) and abs(SCORES[order[start]][key] - SCORES[order[end]][key]) < 1e-9:
            end += 1
        v = (start + end - 1) / 2 / max(1, len(order) - 1) if SCORES[order[start]][key] > 1e-9 else 0.0
        for c in order[start:end]:
            out[c] = v
        start = end
    return out


def ranked_shape_spacing(count: int) -> list[Item]:
    """Shape and Spacing both on: the score is the sum of the two percentile ranks, and the bar is that sum."""
    shape, spacing = percentiles("shape"), percentiles("spacing")
    order = DATA["ranked"]["both"][:count]
    scores = [shape[c] + spacing[c] for c in order]
    assert scores == sorted(scores, reverse=True)
    return [Item(c, v / scores[0], v / scores[0]) for c, v in zip(order, scores)]


def overlay_text(xa: float, xb: float, y: float, size: float, ch: str, clip_id: str) -> str:
    """A in red, B in blue, and B again in ink clipped to A's outline: the shared ink."""
    e = html.escape(ch)

    def t(px: float, fam: str, extra: str) -> str:
        return f'<text x="{px:.2f}" y="{y:g}" font-size="{size:g}" font-family="{fam}" stroke="none"{extra}>{e}</text>'

    return (
        f'<defs><clipPath id="{clip_id}">{t(xa, HN, "")}</clipPath></defs>'
        + t(xa, HN, f' fill="{RED}"')
        + t(xb, AR, f' fill="{BLUE}"')
        + t(xb, AR, f' fill="{INK}" clip-path="url(#{clip_id})"')
    )


def ink_origins(ch: str, size: float, left: float) -> tuple[float, float]:
    """Origins that put both left ink edges at `left`, as Shape does in the app."""
    ga, gb = fd.glyph("a", ch), fd.glyph("b", ch)
    assert ga and gb
    return left - ga["lsb"] * size, left - gb["lsb"] * size


IX_H = 76  # band height: closing hairline at top + 76
IX_PITCH = 48
IX_SIZE = 26  # the family names' size
IX_BAR = 44  # the bar's scale; 4 short of the pitch, so neighbouring bars never touch

# The colour key: three words, each in the ink it names.
KEYS = '<span class="kl-a">Only A</span><span>Shared</span><span class="kl-b">Only B</span>'
# What Frequency adds to a bar, shown after its label: the weighted value in ink over the measured track.
FREQUENCY_MARK = (
    f'<svg class="ic" width="12" height="2" viewBox="0 0 12 2"><rect width="12" height="2" fill="{TRACK}"/>'
    f'<rect width="7" height="2" fill="{INK}"/></svg>'
)


def index_line(g: Grid, top: int, items: list[Item], selected: str | None, shape: bool, spacing: bool, frequency: bool, uid: str) -> str:
    """Ranked characters on one baseline (top + 42), one bar per cell, and the Differences block at the right.

    A cell starts on the measure: the character's left ink edge and its bar both stand at the cell's
    origin. Cell rows: baseline 42, bar 53-55, band hairline 76. The block stands on the last header
    column and ends at the margin: caption and key on one line, the three checkboxes under them.
    """
    left, width = g.block, g.right - g.block
    limit = left - 16
    out = []
    marker = ""
    for i, it in enumerate(items):
        x = 64 + IX_PITCH * i
        if x >= limit:
            break
        xa, xb = ink_origins(it.ch, IX_SIZE, 0)
        cell = [f'<svg class="ix-cell" style="left:{x}px;top:{top}px" width="48" height="{IX_H}" viewBox="0 0 48 {IX_H}">']
        cell.append(overlay_text(xa, xb, 42, IX_SIZE, it.ch, f"{uid}{i}"))
        # Scale, measured value, weighted value: the scale is the largest measured value in the ranking.
        cell.append(f'<rect x="0" y="53.5" width="{IX_BAR}" height="1" fill="{HAIR}"/>')
        if frequency:
            cell.append(f'<rect x="0" y="53" width="{IX_BAR * it.measured:.1f}" height="2" fill="{TRACK}"/>')
        cell.append(f'<rect x="0" y="53" width="{IX_BAR * it.weighted:.1f}" height="2" fill="{INK}"/>')
        cell.append("</svg>")
        out.append("".join(cell))
        if it.ch == selected:
            # The band's closing hairline thickens to 2 pt of ink under the inspected character.
            marker = f'<div class="rule ink ix-sel" style="left:{x}px;top:{top + IX_H - 1}px;width:{IX_PITCH}px"></div>'
    out.append(f'<div class="ix-fade" style="left:{limit - 72}px;top:{top + 1}px;width:72px"></div>')
    out.append(f'<div class="ix-fade" style="left:{limit}px;top:{top + 1}px;width:{g.right - limit}px;background:var(--paper)"></div>')
    out.append(f'<span class="ix-cap" style="left:{left}px;top:{top + 10}px">Differences</span>')
    out.append(f'<span class="ix-keys" style="right:{1440 - g.right}px;top:{top + 10}px">{KEYS}</span>')
    out.append(
        f'<div class="ix-ctl" style="left:{left}px;top:{top + 30}px;width:{width}px">'
        + chk("Shape", shape)
        + chk("Spacing", spacing)
        + chk("Frequency" + FREQUENCY_MARK, frequency)
        + "</div>"
    )
    out.append(rule(24, top + IX_H, g.cw - 48))
    out.append(marker)
    return "".join(out)


def index_message(g: Grid, top: int, text: str) -> str:
    return f'<span class="ix-msg" style="top:{top + 26}px">{text}</span>' + rule(24, top + IX_H, g.cw - 48)


# ---------------------------------------------------------------- text view

PASSAGE = [
    "“Well, this _is_ grand!” said Alice. “I never expected I should be a Queen so soon—and I’ll tell you what it is, your majesty,” she went on in a severe tone (she was always rather fond of scolding herself), “it’ll never do for you to be lolling about on the grass like that! Queens have to be dignified, you know!”",
    "So she got up and walked about—rather stiffly just at first, as she was afraid that the crown might come off: but she comforted herself with the thought that there was nobody to see her, “and if I really am a Queen,” she said as she sat down again, “I shall be able to manage it quite well in time.”",
    "Everything was happening so oddly that she didn’t feel a bit surprised at finding the Red Queen and the White Queen sitting close to her, one on each side: she would have liked very much to ask them how they came there, but she feared it would not be quite civil. However, there would be no harm, she thought, in asking if the game was over. “Please, would you tell me—” she began, looking timidly at the Red Queen.",
    "“Speak when you’re spoken to!” the Queen sharply interrupted her.",
    "“But if everybody obeyed that rule,” said Alice, who was always ready for a little argument, “and if you only spoke when you were spoken to, and the other person always waited for _you_ to begin, you see nobody would ever say anything, so that—”",
    "“Ridiculous!” cried the Queen. “Why, don’t you see, child—” here she broke off with a frown, and, after thinking for a minute, suddenly changed the subject of the conversation.",
]
HIGHLIGHT = set("“”jdtq")


def passage_html(ranked: bool) -> str:
    """Without a ranking there is nothing to highlight, and the text is wholly ink."""
    paras = []
    for para in PASSAGE:
        parts = []
        for n, piece in enumerate(para.split("_")):
            marked = "".join(
                f'<span class="h">{html.escape(c)}</span>' if ranked and c in HIGHLIGHT else html.escape(c) for c in piece
            )
            parts.append(f"<i>{marked}</i>" if n % 2 else marked)
        paras.append(f"<p>{''.join(parts)}</p>")
    return "".join(paras)


def first_line_offset(side: str, size: float, leading: float) -> float:
    """From the top of the first line box to its baseline, with the browser's integer ascent and descent."""
    hhea = fd.FACES[side]["hhea"]
    upm = fd.FACES[side]["head"].unitsPerEm
    ascent, descent = round(hhea.ascent * size / upm), round(-hhea.descent * size / upm)
    return (leading - ascent - descent) / 2 + ascent


def text_view(g: Grid, top: int, lh_a: float, lh_b: float, size_b: float = 22, style_b: str = "", b_message: str = "") -> str:
    """Two columns whose first baselines coincide at top + 49; each is clipped to whole lines.

    `b_message` stands in B's column when B cannot be drawn.
    """
    base = top + 49
    body = passage_html(ranked=not b_message)
    out = [
        ab("A", cls="tx-key", style=f"left:40px;top:{base - 13}px"),
        ab("B", not b_message, "tx-key", f"left:{g.half - 24}px;top:{base - 13}px"),
    ]
    columns = [("tx-a", 64, "a", 22.0, lh_a, ""), ("tx-b", g.half, "b", size_b, lh_b, style_b)]
    if b_message:
        out.append(f'<span class="abs sec" style="left:{g.half}px;top:{base - 15}px;line-height:20px">{b_message}</span>')
        columns.pop()
    for cls, left, side, size, lh, style in columns:
        y = base - first_line_offset(side, size, lh)
        lines = int((900 - y) // lh)
        out.append(
            f'<div class="tx-col {cls}" style="left:{left}px;top:{y:.2f}px;width:{g.col}px;'
            f'height:{lines * lh:.2f}px;--lh:{lh}px;font-size:{size:g}px;{style}">{body}</div>'
        )
    return "".join(out)


# ---------------------------------------------------------------- glyph view

GL_TOP = 235  # canvas origin, window y
GL_BASE = 684  # the baseline, window y
BIG, SMALL = 480.0, 240.0
INK_LEFT = 840.0  # where the overlay's left ink edges meet
SOLO_X = {"a": 196.0, "b": 444.0}
XH = {k: DATA["xheight"][k] / DATA["upm"][k] for k in ("a", "b")}


def u(v: float) -> str:
    """Font units are whole numbers."""
    return str(round(v))


em = computed


def glyph_view(ch: str, name: str, mode: str = "pair", caption: tuple[str, str] = ("A over B", "Shape aligns left ink edges")) -> str:
    """mode: "pair", "a-alone" (B is None) or "a-missing" (A has no glyph for the character)."""
    top, base = GL_TOP, GL_BASE
    ga, gb = fd.glyph("a", ch), fd.glyph("b", ch)

    def y(v: float) -> str:
        return f"{v - top:g}"

    def vline(x: float, y0: float, y1: float, color: str = HAIR) -> str:
        return f'<path d="M{x:g} {y(y0)}V{y(y1)}" stroke="{color}" stroke-width="1"/>'

    def hline(x0: float, x1: float, yy: float, color: str = HAIR) -> str:
        return f'<path d="M{x0:g} {y(yy)}H{x1:g}" stroke="{color}" stroke-width="1"/>'

    s = [f'<svg class="gl-svg" style="top:{top}px" width="1440" height="{900 - top}" viewBox="0 0 1440 {900 - top}" fill="none">']
    h: list[str] = []

    def tag(x: float, text: str, hang_left: bool) -> None:
        if hang_left:
            h.append(f'<span class="gl-tag" style="right:{1440 - x + 4:g}px;top:{top + 11}px">{text}</span>')
        else:
            h.append(f'<span class="gl-tag" style="left:{x + 4:g}px;top:{top + 11}px">{text}</span>')

    # Overlay guides: neutral hairlines, lettered at the top; a pair within a pixel is one line.
    origins: dict[str, float] = {}
    if mode == "pair":
        assert ga and gb
        origins = {"A": INK_LEFT - ga["lsb"] * BIG, "B": INK_LEFT - gb["lsb"] * BIG}
        advances = {"A": origins["A"] + ga["adv"] * BIG, "B": origins["B"] + gb["adv"] * BIG}
    elif mode == "a-alone":
        assert ga
        origins = {"A": INK_LEFT - ga["lsb"] * BIG}
        advances = {"A": origins["A"] + ga["adv"] * BIG}
    else:
        assert gb
        origins = {"B": INK_LEFT - gb["lsb"] * BIG}
        advances = {"B": origins["B"] + gb["adv"] * BIG}
    for group in (origins, advances):
        marks = sorted((round(x), k) for k, x in group.items())
        if len(marks) == 2 and abs(marks[0][0] - marks[1][0]) <= 1:
            marks = [(marks[0][0], "AB")]
        for n, (x, k) in enumerate(marks):
            s.append(vline(x + 0.5, top + 30, 800))
            if mode != "a-alone":
                # A merged guide is lettered "A B", each letter keeping its own colour.
                tag(x, " ".join(ab(letter) for letter in k), hang_left=len(marks) == 2 and n == 0)

    # x-height: one line when the two fonts agree within a pixel.
    sides = {"pair": ("a", "b"), "a-alone": ("a",), "a-missing": ("a", "b")}[mode]
    xhs = sorted({round(base - XH[k] * BIG) for k in sides})
    if len(xhs) == 2 and xhs[1] - xhs[0] <= 1:
        xhs = [round(base - (XH["a"] + XH["b"]) / 2 * BIG)]
    for yy in xhs:
        s.append(hline(752, 1440, yy + 0.5))
    h.append(f'<span class="gl-lab t11" style="left:752px;top:{xhs[0] - 19}px">x-height</span>')
    h.append(f'<span class="gl-lab t11" style="left:752px;top:{base - 19}px">baseline</span>')

    e = html.escape(ch)
    if mode == "pair":
        s.append(overlay_text(origins["A"], origins["B"], base - top, BIG, ch, "ov"))
    elif mode == "a-alone":
        s.append(f'<text x="{origins["A"]:.2f}" y="{y(base)}" font-size="{BIG:g}" font-family="{HN}" fill="{INK}">{e}</text>')
    else:
        s.append(f'<text x="{origins["B"]:.2f}" y="{y(base)}" font-size="{BIG:g}" font-family="{AR}" fill="{BLUE}">{e}</text>')

    # A and B alone at half scale, each over its columns of the table.
    if mode != "a-alone":
        for k, gl in (("a", ga), ("b", gb)):
            x0 = SOLO_X[k]
            if gl is None:
                h.append(f'<span class="abs sec" style="left:{x0:g}px;top:{base - 26}px;line-height:20px">Character unavailable</span>')
                continue
            x1 = round(x0 + gl["adv"] * SMALL)
            s.append(vline(x0 + 0.5, base - 208, base + 56))
            s.append(vline(x1 + 0.5, base - 208, base + 56))
            s.append(hline(x0 - 12, x1 + 12, round(base - XH[k] * SMALL) + 0.5))
            s.append(f'<text x="{x0:g}" y="{y(base)}" font-size="{SMALL:g}" font-family="{FAM[k]}" fill="{INK}">{e}</text>')

    # The one baseline of the sheet, to both window edges.
    s.append(hline(0, 1440, base + 0.5, INK))
    s.append("</svg>")

    def lab(left: int, top_: int, text: str) -> str:
        return f'<span class="gl-lab" style="left:{left}px;top:{top_}px">{text}</span>'

    def num(right_edge: int, top_: int, text: str, unit: str) -> str:
        unit_html = f'<span class="sec"> {unit}</span>' if unit else ""
        return f'<span class="gl-num" style="right:{1440 - right_edge}px;top:{top_}px">{text}{unit_html}</span>'

    code = f"U+{ord(ch):04X}"
    h += [
        f'<span class="abs t11 sec" style="left:64px;top:{top + 11}px">{code}</span>',
        f'<span class="abs gl-name" style="left:64px;top:{top + 29}px">{name}{SEARCH}</span>',
        # On the caption's baseline, so the line of guide letters at the top holds letters only.
        f'<div class="gl-zoom row" style="top:801.5px"><span class="c-ib">{MINUS}</span>'
        f'<span class="pc">100%</span><span class="c-ib">{PLUS}</span></div>',
    ]
    if caption[0]:
        h.append(
            f'<span class="abs t11" style="left:752px;top:806px">'
            f'<b class="sb">{caption[0]}</b><span class="sec">&ensp;{caption[1]}</span></span>'
        )

    # Metrics: one table, A's numbers beside B's, the columns standing under the two figures.
    cols = {"a": (268, 356), "b": (516, 604)}
    shown = ("a",) if mode == "a-alone" else ("a", "b")
    names = {"a": ("A", HN), "b": ("B", AR)}
    for k in shown:
        h.append(
            f'<span class="abs t11" style="left:{SOLO_X[k]:g}px;top:{base + 66}px">'
            f'{ab(names[k][0], style="font-size:13px")}<span class="sec">&ensp;{names[k][1]}</span></span>'
        )
    rows = [("Advance", "adv"), ("LSB", "lsb"), ("RSB", "rsb")]
    for i, (label, key) in enumerate(rows):
        t = base + 88 + 20 * i
        h.append(lab(64, t, label))
        for k, gl in (("a", ga), ("b", gb)):
            if k not in shown:
                continue
            if gl is None:
                h.append(num(cols[k][0], t, '<span class="sec">—</span>', ""))
                continue
            h.append(num(cols[k][0], t, u(gl[key + "_u"]), "u"))
            h.append(num(cols[k][1], t, em(gl[key]), "em"))
    t = base + 88 + 60 + 6
    h.append(rule(64, t - 3, 292 if mode == "a-alone" else 540))
    h.append(lab(64, t, "x-height"))
    h.append(lab(64, t + 20, "Units/em"))
    for k in shown:
        h.append(num(cols[k][0], t, str(DATA["xheight"][k]), "u"))
        h.append(num(cols[k][1], t, em(XH[k]), "em"))
        h.append(num(cols[k][0], t + 20, f'{DATA["upm"][k]}<span style="visibility:hidden"> u</span>', ""))
    return "".join(s) + "".join(h)


# ---------------------------------------------------------------- languages view

CATEGORIES = [("base", "Base"), ("auxiliary", "Auxiliary"), ("numerals", "Numerals"), ("punctuation", "Punctuation"), ("currency", "Currency")]
CELL, CELLS_PER_ROW = 22, 28


def speakers(n: int) -> str:
    """Whole millions; under one million, whole thousands; under one thousand, the count."""
    if n >= 999_500:
        return f"{max(1, math.floor(n / 1e6 + 0.5))}M"
    if n >= 1000:
        return f"{math.floor(n / 1e3 + 0.5)}k"
    return str(n)


def language_facts(code: str, title: str, autonym: str, rest: str) -> str:
    """The detail's facts line. The autonym is left out when it only repeats the title above it."""
    return " · ".join([code] + ([autonym] if autonym != title else []) + [rest])


def languages_view(g: Grid, top: int) -> str:
    """`top` is the band's top (158): the filter line takes the index line's slot."""
    # Filter line.
    track_left, track_w = 196, 408
    ticks = [("All", 0.0), ("100", 1.0), ("1k", 2.0), ("10k", 3.0), ("100k", 4.0), ("1M", 5.0), ("10M", 6.0), ("100M", 7.0), ("920M", 7.9638)]
    pos = 5.9191 / 7.9638  # 8.3M on the logarithmic scale
    f = [
        f'<span class="abs sec" style="left:64px;top:{top + 22}px;line-height:20px">Minimum speakers</span>',
        slider(pos, f"position:absolute;left:{track_left}px;top:{top + 24}px;width:{track_w}px"),
    ]
    for label, p in ticks:
        f.append(f'<span class="lg-tick" style="left:{track_left + 7 + (track_w - 14) * p / 7.9638:.1f}px;top:{top + 45}px">{label}</span>')
    f += [
        f'<span class="abs" style="left:624px;top:{top + 22}px;line-height:20px"><span class="c-num">8.3M</span></span>',
        f'<span class="abs sec" style="left:{g.half}px;top:{top + 22}px;line-height:20px">Coverage</span>',
        f'<span class="abs c-pop" style="left:{g.half + 64}px;top:{top + 20}px">All{UPDOWN}</span>',
        f'<span class="abs" style="left:{g.half + 128}px;top:{top + 20}px">{chk("Show historical", False)}</span>',
        f'<span class="abs sec" style="right:{1440 - g.right + 118}px;top:{top + 22}px;line-height:20px">{DATA["languages"]["count"]} languages</span>',
        f'<span class="abs c-btn" style="right:{1440 - g.right}px;top:{top + 20}px">Clear Filters</span>',
        rule(24, top + IX_H, g.cw - 48),
    ]

    def dot(full: bool) -> str:
        return f'<i class="lg-dot{" full" if full else ""}"></i>'

    # Table: a note above the A and B columns names the two marks. The head shares the detail's
    # lines: the note on the name's baseline, the labels on the facts' baseline, one closing rule.
    t0 = top + IX_H + 10  # 244
    t = [
        f'<div class="lg-key row" style="right:{1440 - 688}px;top:{t0 + 9}px">{dot(True)}Complete'
        f'<span style="width:9px"></span>{dot(False)}Incomplete</div>',
        f'<div class="lg-head" style="top:{t0 + 28.5}px"><span></span><span>Language</span>'
        f'<span class="lg-r" style="color:var(--ink)">Speakers&ensp;{DOWN}</span><span></span>'
        f'<span class="lg-c" style="font-size:13px">{ab("A")}</span>'
        f'<span class="lg-c" style="font-size:13px">{ab("B")}</span><span></span></div>',
        rule(64, t0 + 60, 624),
    ]
    for i, row in enumerate(DATA["languages"]["rows"][:22]):
        # Selection is ink: a tick hanging where A and B hang, and the name in semibold.
        sel = row["id"] == "eng"
        name = f'<b class="sb">{row["name"]}</b>' if sel else row["name"]
        tick = '<i class="sel-tick"></i>' if sel else ""
        t.append(
            f'<div class="lg-row" style="top:{t0 + 63 + 28 * i}px"><span>{tick}</span>'
            f"<span>{name}</span>"
            f'<span class="lg-r">{speakers(row["speakers"])}</span><span></span>'
            f'<span class="lg-c">{dot(row["a"])}</span><span class="lg-c">{dot(row["b"])}</span><span></span></div>'
        )

    # Detail: one band per category; its heading is the checkbox, the name and the two counts.
    x = g.half
    d = [
        f'<span class="abs t20" style="left:{x}px;top:{t0}px">English</span>',
        f'<span class="abs c-btn" style="right:{1440 - 1376}px;top:{t0 + 2}px">Use Checked as Specimen</span>',
        f'<span class="abs sec" style="left:{x}px;top:{t0 + 30}px;line-height:20px">'
        f'{language_facts("eng", "English", "English", "400,000,000 speakers (2006) · preliminary data")}</span>',
        f'<span class="abs" style="right:{1440 - 1376}px;top:{t0 + 30}px;line-height:20px">{DATA["languages"]["english"]["script"]}</span>',
    ]
    yy = t0 + 60  # 304
    english = DATA["languages"]["english"]["categories"]
    missing = any(english[key]["missing_a"] or english[key]["missing_b"] for key, _ in CATEGORIES)
    for key, title in CATEGORIES:
        cat = english[key]
        tokens: list[str] = cat["tokens"]
        # Today's app counts U+2010 as covered by Arial (Core Text's character set), so nothing is missing.
        total = cat["a"][1]
        d.append(rule(x, yy, 624))
        d.append(f'<div class="lg-bh row" style="top:{yy + 7}px">{cb(key == "base")}<b class="sb">{title}</b></div>')
        d.append(f'<span class="lg-cnt" style="left:{x + 160}px;top:{yy + 7}px">{ab("A")}{total}/{total}</span>')
        d.append(f'<span class="lg-cnt" style="left:{x + 248}px;top:{yy + 7}px">{ab("B")}{total}/{total}</span>')
        cy = yy + 31
        for start in range(0, len(tokens), CELLS_PER_ROW):
            chunk = tokens[start : start + CELLS_PER_ROW]
            cells = "".join(f"<span>{html.escape(c)}</span>" for c in chunk)
            for letter, cls in (("A", "lg-fa"), ("B", "lg-fb")):
                d.append(ab(letter, cls="tx-key", style=f"left:{x - 24}px;top:{cy + 4}px"))
                d.append(f'<div class="lg-cells {cls}" style="top:{cy}px">{cells}</div>')
                cy += CELL
            cy += 6
        yy = cy - 6 + 9
    d += [
        rule(x, yy, 624),
        f'<span class="abs t11 sec" style="left:{x}px;top:{yy + 10}px">Character coverage does not assess joining, mark placement, or visual quality.</span>',
        f'<span class="abs c-pop" style="left:{x}px;top:{yy + 30}px;gap:7px"><span style="color:var(--ink2);display:flex">{RIGHT}</span>Sources and notes</span>',
    ]
    if missing:
        # The dotted cell is keyed only when one is drawn.
        d.append(
            f'<span class="abs t11 sec row" style="right:{1440 - 1376}px;top:{yy + 10}px;height:16px;gap:6px"><i class="lg-miss"></i>Missing</span>'
        )
    return "".join(f) + "".join(t) + "".join(d)


# ---------------------------------------------------------------- inspector and picker (detail state)


def log_position(value: float, low: float, high: float) -> float:
    return math.log(value / low) / math.log(high / low)


def inspector(a: Font, b: Font) -> str:
    """Pane coordinates: the pane starts under the toolbar, at window y 52. Content runs x 1144-1416."""
    shown = figures(a, b)

    def row(top_: int, cls: str, inner: str, extra: str = "") -> str:
        return f'<div class="in-row {cls}" style="top:{top_}px;{extra}">{inner}</div>'

    def fact(top_: int, name: str, va: str, vb: str) -> str:
        return row(top_, "in-fact", f'<span class="sec">{name}</span><span>{va}</span><span>{vb}</span>')

    def label(top_: int, name: str, relation: str = "", reset: bool = False) -> str:
        # The relation is the same pull-down as on the header's label.
        rel = f'<span class="rel">{relation}{DOWN}</span>' if relation else ""
        rs = f'<span class="c-ib rs">{RESET}</span>' if reset else ""
        return row(top_, "in-lab", f'<span class="sec">{name}</span>{rel}{rs}')

    def setting(top_: int, f: Font, name: str, p: float, unit: str, auto: bool | None = None) -> str:
        value = shown[f.key][name].strip(FIGURE_SPACE)  # the field is right-aligned
        field = f'<span class="f"><span class="c-num{" sec" if auto else ""}">{value}</span></span>'
        tail = "<span></span>" if auto is None else chk("Auto", auto, small=True)
        return row(top_, "in-set", f'{ab(f.key, cls="k")}{slider(p, auto=bool(auto))}{field}<span class="u">{unit}</span>{tail}')

    def feat(top_: int, name: str, tag: str, a: str, b: str, reset: bool = False, selected: bool = False) -> str:
        rs = f'<span class="c-ib" style="color:var(--ink2)">{RESET}</span>' if reset else "<span></span>"
        label_ = f'<span><i class="sel-tick"></i><b class="sb">{name}</b></span>' if selected else f"<span>{name}</span>"
        return row(top_, "in-feat", f'{label_}<span class="tg">{tag}</span><span class="c">{a}</span><span class="c">{b}</span>{rs}')

    def group(top_: int, name: str, open_: bool) -> str:
        return row(top_, "in-grp", f"{DOWN if open_ else RIGHT}{name}")

    def half(letter: str, fam: str, before: str, after: str, text: str) -> str:
        return (
            f'<span class="half">{ab(letter, cls="k")}<span style="font-family:{fam};{before}">{text}</span>'
            f'<span class="arr">→</span><span style="font-family:{fam};{after}">{text}</span></span>'
        )

    none = "–"
    hn, ar = f"'{HN}'", AR
    o = ['<div class="in-pane">']
    # What the fonts are, A beside B. x-height is in em, so the pair can be compared.
    o.append(fact(14, "", ab("A"), ab("B")))
    o.append(fact(34, "Units/em", "1000", "2048"))
    o.append(fact(54, "x-height", f'{em(XH["a"])} em', f'{em(XH["b"])} em'))
    o.append(fact(74, "Weight", "400", "400"))
    o.append(rule(23, 105, 272))
    # Appearance: per setting a label line, then A's row and B's row.
    o.append(
        row(
            117,
            "in-head",
            '<span class="row" style="gap:10px"><b class="sb">Appearance</b><span class="c-btn sm">Reset</span></span>'
            + chk("Link A and B", True),
        )
    )
    # Size (10-144) and Leading (1-288) are logarithmic, as the speakers slider is.
    o.append(label(151, "Size", "×0.977", reset=True))
    o.append(setting(171, a, "size", log_position(a.size, 10, 144), "pt"))
    o.append(setting(195, b, "size", log_position(b.size, 10, 144), "pt"))
    o.append(label(227, "Leading"))
    o.append(setting(247, a, "leading", log_position(a.leading, 1, 288), "pt", auto=a.auto))
    o.append(setting(271, b, "leading", log_position(b.leading, 1, 288), "pt", auto=b.auto))
    o.append(label(303, "Tracking", "+0.004 em", reset=True))
    o.append(setting(323, a, "tracking", (0.12 + a.tracking) / 0.27, "em"))
    o.append(setting(347, b, "tracking", (0.12 + b.tracking) / 0.27, "em"))
    o.append(rule(23, 383, 272))
    # Typography: one row per feature across both fonts, a column for A and one for B.
    o.append(
        row(
            395,
            "in-feat",
            '<span class="row" style="gap:10px"><b class="sb">Typography</b><span class="c-btn sm">Reset</span></span><span></span>'
            f'<span class="c">{ab("A")}</span><span class="c">{ab("B")}</span><span></span>',
            "height:24px",
        )
    )
    o.append(group(423, "Common", True))
    o.append(feat(445, "Kerning", "kern", cb(True), cb(False), reset=True))
    o.append(row(467, "in-pv", half("A", hn, "font-kerning:none", "", "AV") + half("B", ar, "font-kerning:none", "", "AV")))
    o.append(feat(489, "Common Ligatures", "", cb(True), none))
    o.append(feat(511, "Standard ligatures", "liga", none, cb(True)))
    o.append(feat(533, "Discretionary ligatures", "dlig", none, cb(True), reset=True, selected=True))
    o.append(
        row(
            555,
            "in-pv",
            "<span></span>" + half("B", ar, "font-feature-settings:'dlig' 0;unicode-bidi:isolate", "font-feature-settings:'dlig' 1;unicode-bidi:isolate", "אל"),
        )
    )
    o.append(group(581, "Character variants", True))
    o.append(feat(603, "Character Alternatives", "", "", none))
    o.append(row(625, "in-val", f'{ab("A", cls="k")}<span class="c-pop">No Change{UPDOWN}</span>'))
    o.append(group(651, "Numbers", True))
    o.append(feat(673, "Number Spacing", "", "", none, reset=True))
    o.append(row(695, "in-val", f'{ab("A", cls="k")}<span class="c-pop">Monospaced Numbers{UPDOWN}</span>'))
    o.append(
        row(717, "in-pv", half("A", hn, "font-variant-numeric:proportional-nums", "font-variant-numeric:tabular-nums", "1,117.40") + "<span></span>")
    )
    o.append(group(743, "Automatic shaping", False))
    o.append("</div>")
    return "".join(o)


# Family names are fonts that ship with macOS; the distances are invented.
SIMILAR: list[tuple[str, str]] = [
    ("Helvetica Neue", "0.000"), ("Helvetica", "0.118"), ("Arial", "0.203"), ("Arial Unicode MS", "0.204"),
    ("Microsoft Sans Serif", "0.231"), ("Geneva", "0.342"), ("Tahoma", "0.361"), ("Lucida Grande", "0.377"),
    ("Verdana", "0.405"), ("Avenir Next", "0.428"), ("Trebuchet MS", "0.447"), ("Gill Sans", "0.493"),
]  # fmt: skip


def picker() -> str:
    rows = ['<div class="pk-row" style="top:138px"><span></span><span>None</span><span></span></div>']
    for i, (name, dist) in enumerate(SIMILAR):
        current = name == AR
        rows.append(
            f'<div class="pk-row{" cur" if current else ""}" style="top:{166 + 28 * i}px">'
            f'<span class="ck">{CHECK if current else ""}</span>'
            f"<span class=\"n\" style=\"font-family:'{name}',var(--ui)\">{name}</span>"
            f'<span class="d">{dist}</span></div>'
        )
    return (
        '<i class="pk-arrow"></i><div class="pk-pop">'
        f'<div class="pk-search">{SEARCH}<i class="pk-caret"></i>Search installed fonts</div>'
        '<div class="pk-seg c-seg"><span>Name</span><span class="on">Similarity</span></div>'
        '<div class="pk-cap" style="top:86px">Similarity to Helvetica Neue · default settings</div>'
        # The figures are distances, so the column says so; its help tag is "Lower is closer".
        '<span class="pk-head">Distance</span>'
        f'<div class="pk-bar"><i style="width:{312 * 40 / 240:g}px"></i></div>'
        '<div class="pk-cap" style="top:114px">Compared 40 of 240</div>'
        + "".join(rows)
        + "</div>"
    )


# ---------------------------------------------------------------- pages


def build(out: Path) -> None:
    """Write the pages into `out`."""

    def write(name: str, title: str, body: str) -> None:
        (out / name).write_text(page(title, body), encoding="utf-8")

    g = WIDE
    top = 158  # index band; the canvas starts at top + 77
    text_items = ranked_shape_frequency(24)

    head = toolbar("Text", "Find Character") + spec(g, A_DEFAULT, B_DEFAULT)
    body = index_line(g, top, text_items, None, True, False, True, "t") + text_view(g, top + 77, 26.616, 25.72)
    write("text.html", "Text", head + body)

    # Shape and Spacing on, Frequency off: the line is ranked by both, and U+0040 is first.
    head = toolbar("Glyph", "Find Character") + spec(g, A_DEFAULT, B_DEFAULT)
    body = index_line(g, top, ranked_shape_spacing(24), "@", True, True, False, "g") + glyph_view("@", "COMMERCIAL AT")
    write("glyph.html", "Glyph", head + body)

    head = toolbar("Languages", "Search Languages") + spec(g, A_DEFAULT, B_DEFAULT)
    write("languages.html", "Languages", head + languages_view(g, top))

    # Inspector open; B was set to 21.5 pt and +0.004 em while unlinked, then linked again.
    n = NARROW
    a = replace(A_DEFAULT, typo="1 change")
    b = replace(B_DEFAULT, size=21.5, leading=25.135, tracking=0.004, typo="2 changes")
    head = toolbar("Text", "Find Character", inspector=True) + spec(n, a, b, relations={"size": "×0.977", "tracking": "+0.004 em"})
    body = (
        index_line(n, top, text_items, None, True, False, True, "d")
        + text_view(n, top + 77, 26.616, 25.135, 21.5, "letter-spacing:.004em")
        + inspector(a, b)
        + picker()
    )
    write("detail.html", "Inspector and font picker", head + body)

    # Match, mid-search: Size has been optimized, Tracking is being searched.
    b = replace(B_DEFAULT, size=21.46, leading=25.089)
    head = (
        toolbar("Text", "Find Character", matching=True)
        + spec(g, A_DEFAULT, b, matching=True, strong=frozenset({"size"}), before=B_DEFAULT)
        + match_band(g, A_DEFAULT, b, B_DEFAULT, "tracking")
    )
    mtop = MT_RULE + 1
    body = index_line(g, mtop, text_items, None, True, False, True, "m") + text_view(g, mtop + 77, 26.616, 25.089, 21.46)
    write("match.html", "Match", head + body)

    # B is None: one font inspected.
    head = toolbar("Glyph", "Find Character") + spec(g, A_DEFAULT, Font("B", None))
    body = index_message(g, top, "Choose a second font to compare.") + glyph_view("@", "COMMERCIAL AT", "a-alone", ("", ""))
    write("none.html", "B is None", head + body)

    # A character Helvetica Neue lacks; the fonts are unlinked, B's leading is explicit and its field has the focus.
    assert not fd.has("a", "Ƙ") and fd.has("b", "Ƙ")
    b = replace(B_DEFAULT, leading=28, auto=False)
    head = toolbar("Glyph", "Find Character") + spec(g, A_DEFAULT, b, linked=False, focus="leading")
    body = index_line(g, top, text_items, None, True, False, True, "x") + glyph_view(
        "Ƙ", "LATIN CAPITAL LETTER K WITH HOOK", "a-missing", ("Character unavailable in A", "B’s ink alone, in B’s colour")
    )
    write("missing.html", "Missing glyph", head + body)

    # Extra, not one of the seven: a font that is not installed, named by its PostScript name.
    b = Font("B", "Univers-Roman", installed=False)
    head = toolbar("Text", "Find Character") + spec(g, A_DEFAULT, b)
    body = index_message(g, top, "B is not installed. Choose an installed font to compare.") + text_view(
        g, top + 77, 26.616, 25.72, b_message="This font is not installed. Choose an installed font above."
    )
    write("missing-font.html", "Font not installed", head + body)


def main() -> None:
    build(OUT)


if __name__ == "__main__":
    main()
