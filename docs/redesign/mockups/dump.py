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

"""Print each positioned element of a page with its place and first words, for reading a layout as numbers."""

from __future__ import annotations

import re
import sys
from html.parser import HTMLParser
from pathlib import Path


class Dump(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.rows: list[list[str]] = []
        self.depth: list[int | None] = []
        self.in_style = False

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        d = dict(attrs)
        self.in_style = tag == "style"
        style = d.get("style") or ""
        place = " ".join(m.group(0).strip(";") for m in re.finditer(r"(?:^|;)\s*(left|right|top|width|height):[^;]+", style))
        if tag in ("path", "rect", "circle", "meta"):
            return
        if place and tag != "text":
            self.rows.append([f"{tag}.{(d.get('class') or '').replace(' ', '.')}", place, ""])
            self.depth.append(len(self.rows) - 1)
        else:
            self.depth.append(None)

    def handle_endtag(self, tag: str) -> None:
        if tag in ("path", "rect", "circle", "meta"):
            return
        if tag == "style":
            self.in_style = False
        if self.depth:
            self.depth.pop()

    def handle_data(self, data: str) -> None:
        if self.in_style:
            return
        for i in reversed(self.depth):
            if i is not None:
                if len(self.rows[i][2]) < 60:
                    self.rows[i][2] += data.strip()[:60] + " "
                break


d = Dump()
d.feed(Path(sys.argv[1]).read_text(encoding="utf-8"))
for name, place, text in d.rows:
    print(f"{name[:34]:34} {place[:62]:62} {text[:70]}")
