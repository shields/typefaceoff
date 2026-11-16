"""Static checks on the generated pages: balanced tags, unique ids, no external resources,
every class used is defined in mock.css, and every absolutely placed box lies inside the window."""

from __future__ import annotations

import re
import sys
from html.parser import HTMLParser
from pathlib import Path

HERE = Path(__file__).parent
VOID = {"meta", "br", "img", "input", "link", "path", "rect", "circle"}
CSS = (HERE / "mock.css").read_text(encoding="utf-8")
DEFINED = set(re.findall(r"\.([a-z][a-z0-9-]*)", re.sub(r"\{[^}]*\}", "{}", CSS)))


class Check(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.stack: list[str] = []
        self.ids: list[str] = []
        self.classes: set[str] = set()
        self.problems: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        d = dict(attrs)
        if "id" in d:
            self.ids.append(d["id"] or "")
        self.classes.update((d.get("class") or "").split())
        for key in ("src", "href"):
            if key in d:
                self.problems.append(f"external reference: {tag} {key}={d[key]}")
        style = d.get("style") or ""
        for prop in ("left", "top", "width", "height", "right"):
            m = re.search(rf"(?:^|;)\s*{prop}:(-?[\d.]+)px", style)
            if m and not (-1 <= float(m.group(1)) <= 1440):
                self.problems.append(f"{tag}.{d.get('class')} {prop}={m.group(1)}")
        if tag not in VOID:
            self.stack.append(tag)

    def handle_startendtag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        self.handle_starttag(tag, attrs)
        if tag not in VOID:
            self.stack.pop()

    def handle_endtag(self, tag: str) -> None:
        if not self.stack or self.stack[-1] != tag:
            self.problems.append(f"unbalanced </{tag}>, open: {self.stack[-3:]}")
        else:
            self.stack.pop()


MAIN = ("text", "glyph", "languages", "detail", "match", "none", "missing", "missing-font")
failed = False
for name in MAIN:
    c = Check()
    c.feed((HERE / f"{name}.html").read_text(encoding="utf-8"))
    dup = {i for i in c.ids if c.ids.count(i) > 1}
    undefined = sorted(c.classes - DEFINED)
    for problem in c.problems + ([f"open at end: {c.stack}"] if c.stack else []) + ([f"duplicate ids: {dup}"] if dup else []) + (
        [f"classes without a rule: {undefined}"] if undefined else []
    ):
        failed = True
        print(f"{name}: {problem}")
print("failed" if failed else "ok")
sys.exit(failed)
