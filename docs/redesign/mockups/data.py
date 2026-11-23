# Copyright © 2026 Michael Shields
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Compute the real numbers the mockups show, from the installed font files and the app's data.

Run with `uv run --no-project --with fonttools --with pillow python3 data.py`; writes data.json.
The difference scores follow the formulas in the app's Differences.swift and
CharacterFrequency.swift, with FreeType standing in for Core Text as the rasteriser.
"""

from __future__ import annotations

import json
import math
import re
import unicodedata
from pathlib import Path

from fontTools.pens.boundsPen import BoundsPen
from fontTools.ttLib import TTCollection, TTFont
from PIL import Image, ImageDraw, ImageFont

OUT = Path(__file__).parent
APP = Path(__file__).resolve().parents[3] / "Sources" / "TypefaceCore"
HN_PATH, HN_INDEX = "/System/Library/Fonts/HelveticaNeue.ttc", 0
AR_PATH, AR_INDEX = "/System/Library/Fonts/Supplemental/Arial.ttf", 0

FONTS = {
    "a": TTCollection(HN_PATH).fonts[HN_INDEX],
    "b": TTFont(AR_PATH),
}
PIL_SRC = {"a": (HN_PATH, HN_INDEX), "b": (AR_PATH, AR_INDEX)}
CMAP = {k: f.getBestCmap() for k, f in FONTS.items()}
UPM = {k: f["head"].unitsPerEm for k, f in FONTS.items()}
GLYPHS = {k: f.getGlyphSet() for k, f in FONTS.items()}


def native(side: str, ch: str) -> dict[str, float] | None:
    """Advance and side bearings in font units, as the app's metrics table shows them."""
    name = CMAP[side].get(ord(ch))
    if name is None:
        return None
    pen = BoundsPen(GLYPHS[side])
    GLYPHS[side][name].draw(pen)
    adv = FONTS[side]["hmtx"][name][0]
    if pen.bounds is None:
        return {"advance": adv, "lsb": 0, "rsb": adv, "xmin": 0, "ymin": 0, "xmax": 0, "ymax": 0}
    x0, y0, x1, y1 = pen.bounds
    return {"advance": adv, "lsb": x0, "rsb": adv - x1, "xmin": x0, "ymin": y0, "xmax": x1, "ymax": y1}


def frequencies() -> dict[int, float]:
    table: dict[int, float] = {}
    for line in (APP / "Resources/character-frequencies.tsv").read_text(encoding="utf-8").splitlines():
        if line.startswith("#") or not line.strip():
            continue
        code, share = line.split("\t")
        table[int(code, 16)] = float(share)
    return table


FREQ = frequencies()


def weight(ch: str) -> tuple[float | None, float]:
    p = FREQ.get(ord(unicodedata.normalize("NFC", ch)))
    clamped = min(max(p or 0.0, 1e-5), 1e-3)
    return p, math.sqrt(clamped / 1e-3)


def compare(ch: str) -> dict[str, float] | None:
    ma, mb = native("a", ch), native("b", ch)
    if ma is None or mb is None:
        return None
    size = 192.0
    sa, sb = size / UPM["a"], size / UPM["b"]
    spacing = (
        abs(ma["advance"] * sa - mb["advance"] * sb)
        + abs(ma["lsb"] * sa - mb["lsb"] * sb)
        + abs(ma["rsb"] * sa - mb["rsb"] * sb)
    ) / (3 * size)
    ascent = max(0.0, ma["ymax"] * sa, mb["ymax"] * sb)
    descent = max(0.0, -min(ma["ymin"] * sa, mb["ymin"] * sb))
    width = max(1.0, (ma["xmax"] - ma["xmin"]) * sa, (mb["xmax"] - mb["xmin"]) * sb)
    height = max(1.0, ascent + descent)
    scale = min(1.0, 504 / max(width, height))
    w, h = math.ceil(width * scale) + 8, math.ceil(height * scale) + 8
    masks = []
    for side, m, s in (("a", ma, sa), ("b", mb, sb)):
        path, index = PIL_SRC[side]
        font = ImageFont.truetype(path, size=size * scale, index=index)
        img = Image.new("L", (w, h), 0)
        ImageDraw.Draw(img).text((4 - m["xmin"] * s * scale, 4 + ascent * scale), ch, font=font, fill=255, anchor="ls")
        masks.append(img.tobytes())
    inter = sum(min(x, y) for x, y in zip(*masks))
    union = sum(max(x, y) for x, y in zip(*masks))
    shape = 0.0 if union == 0 else 1 - inter / union
    p, wt = weight(ch)
    return {"shape": shape, "spacing": spacing, "frequency": p, "weight": wt}


def queen_alice() -> str:
    src = (APP / "QueenAlice.swift").read_text(encoding="utf-8")
    body = src.split('markdown: """', 1)[1].split('"""', 1)[0]
    return "\n".join(line.strip() for line in body.splitlines())


def candidates(sample: str) -> list[str]:
    seen: list[str] = []
    for ch in "".join(chr(c) for c in range(33, 127)) + sample:
        if ch.strip() and ch not in seen:
            seen.append(ch)
    return sorted(seen)


def percentiles(scores: dict[str, dict[str, float]], key: str) -> dict[str, float]:
    order = sorted(scores, key=lambda c: scores[c][key])
    out: dict[str, float] = {}
    start = 0
    while start < len(order):
        end = start + 1
        while end < len(order) and abs(scores[order[start]][key] - scores[order[end]][key]) < 1e-9:
            end += 1
        v = (start + end - 1) / 2 / max(1, len(order) - 1) if scores[order[start]][key] > 1e-9 else 0.0
        for c in order[start:end]:
            out[c] = v
        start = end
    return out


def ranked(scores: dict[str, dict[str, float]], shape: bool, spacing: bool, frequency: bool) -> list[str]:
    def w(c: str, v: float) -> float:
        return v * scores[c]["weight"] if frequency else v

    if shape != spacing:
        key = "shape" if shape else "spacing"
        return sorted(scores, key=lambda c: (-w(c, scores[c][key]), c))
    ps, pp = percentiles(scores, "shape"), percentiles(scores, "spacing")
    return sorted(scores, key=lambda c: (-w(c, ps[c] + pp[c]), c))


def languages() -> dict[str, object]:
    data = json.loads((APP / "Resources/languages.json").read_text(encoding="utf-8"))

    def has(side: str, token: str) -> bool:
        return all(ord(ch) in CMAP[side] for ch in token)

    def coverage(side: str, ortho: dict) -> dict[str, tuple[int, int]]:
        out = {}
        for cat, inv in ortho["categories"].items():
            req = inv["requirements"].split() + inv["sequences"].split()
            out[cat] = (sum(has(side, t) for t in req), len(req))
        return out

    def complete(side: str, lang: dict) -> bool:
        hist = lang["status"] == "historical"
        eligible = [o for o in lang["orthographies"] if hist or o["status"] != "historical"]
        done = {o["id"]: (lambda c: c[0] == c[1])(coverage(side, o)["base"]) for o in eligible}
        grouped = [o for o in eligible if o["grouped"]]
        group_ok = bool(grouped) and all(done[o["id"]] for o in grouped)
        return any(group_ok if o["grouped"] else done[o["id"]] for o in eligible)

    living = [l for l in data["languages"] if l["status"] != "historical" and (l.get("speakers") or 0) >= 8_300_000]
    living.sort(key=lambda l: (-l["speakers"], l["name"]))
    rows = [
        {"id": l["id"], "name": l["name"], "speakers": l["speakers"], "a": complete("a", l), "b": complete("b", l)}
        for l in living
    ]
    eng = next(l for l in data["languages"] if l["id"] == "eng")
    ortho = eng["orthographies"][0]
    cats = {}
    for cat, inv in ortho["categories"].items():
        tokens: list[str] = []
        for t in inv["characters"].split():
            tokens.extend([t] if len(t) == 1 or t in inv["requirements"].split() else list(t))
        cats[cat] = {
            "tokens": tokens,
            "a": coverage("a", ortho)[cat],
            "b": coverage("b", ortho)[cat],
            "missing_a": [t for t in tokens if not has("a", t)],
            "missing_b": [t for t in tokens if not has("b", t)],
        }
    hau = next(l for l in data["languages"] if l["id"] == "hau")
    return {
        "count": len(living),
        "rows": rows,
        "english": {"script": f'{ortho["script"]} ({ortho["scriptCode"]})', "categories": cats},
        "hausa": {"a": complete("a", hau), "b": complete("b", hau), "base": hau["orthographies"][0]["categories"]["base"]["characters"]},
        "version": data["version"],
    }


def main() -> None:
    sample = queen_alice()
    scores = {c: s for c in candidates(sample) if (s := compare(c)) is not None}
    out = {
        "upm": UPM,
        "xheight": {k: FONTS[k]["OS/2"].sxHeight for k in FONTS},
        "capheight": {k: FONTS[k]["OS/2"].sCapHeight for k in FONTS},
        "hhea": {k: [FONTS[k]["hhea"].ascent, FONTS[k]["hhea"].descent, FONTS[k]["hhea"].lineGap] for k in FONTS},
        "glyphs": {ch: {"a": native("a", ch), "b": native("b", ch)} for ch in "@Ƙƙ฿"},
        "scores": scores,
        "ranked": {
            "shape_freq": ranked(scores, True, False, True),
            "shape": ranked(scores, True, False, False),
            "both_freq": ranked(scores, True, True, True),
            "both": ranked(scores, True, True, False),
        },
        "languages": languages(),
        "sample": sample,
    }
    (OUT / "data.json").write_text(json.dumps(out, ensure_ascii=False, indent=1), encoding="utf-8")
    for key, order in out["ranked"].items():
        print(key, " ".join(order[:40]), "| @ at", order.index("@") + 1, "of", len(order))
    print({k: v for k, v in out["glyphs"].items()})
    print(out["xheight"], out["hhea"])
    lg = out["languages"]
    print(lg["count"], [(r["name"], r["speakers"], r["a"], r["b"]) for r in lg["rows"][:24]])
    print({c: (v["a"], v["b"], len(v["tokens"])) for c, v in lg["english"]["categories"].items()})
    print(lg["hausa"])


if __name__ == "__main__":
    main()
