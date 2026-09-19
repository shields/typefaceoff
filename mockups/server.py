#!/usr/bin/env python3
"""Serve the UX prototype and a small allowlist of locally installed fonts.

No dependencies, downloads, or font copies. Font metadata is read from the actual
sfnt tables. TTC faces are repacked in memory for browsers that need single faces.
"""
import argparse
import json
import mimetypes
import unicodedata
from functools import lru_cache
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from struct import pack, unpack_from
from urllib.parse import parse_qs, unquote, urlsplit

ROOT = Path(__file__).resolve().parent
HOME_FONTS = Path.home() / "Library/Fonts"
SYSTEM = Path("/System/Library/Fonts")
FONTS = {
    "helvetica": {"name": "Helvetica Neue", "short": "Helvetica Neue", "faces": {
        "regular": (SYSTEM / "HelveticaNeue.ttc", 0, "Regular", 400),
        "thin": (SYSTEM / "HelveticaNeue.ttc", 12, "Thin", 100),
        "light": (SYSTEM / "HelveticaNeue.ttc", 7, "Light", 300),
        "medium": (SYSTEM / "HelveticaNeue.ttc", 10, "Medium", 500),
        "bold": (SYSTEM / "HelveticaNeue.ttc", 1, "Bold", 700),
        "italic": (SYSTEM / "HelveticaNeue.ttc", 2, "Italic", 400),
    }},
    "arial": {"name": "Arial", "short": "Arial", "faces": {
        "regular": (SYSTEM / "Supplemental/Arial.ttf", 0, "Regular", 400),
        "bold": (SYSTEM / "Supplemental/Arial Bold.ttf", 0, "Bold", 700),
        "italic": (SYSTEM / "Supplemental/Arial Italic.ttf", 0, "Italic", 400),
        "bolditalic": (SYSTEM / "Supplemental/Arial Bold Italic.ttf", 0, "Bold Italic", 700),
    }},
    "inter": {"name": "Inter", "short": "Inter", "faces": {
        "regular": (HOME_FONTS / "InterVariable.ttf", 0, "Variable", 400),
    }},
    "atkinson": {"name": "Atkinson Hyperlegible Next", "short": "Atkinson Next", "faces": {
        "regular": (HOME_FONTS / "AtkinsonHyperlegibleNext[wght].ttf", 0, "Variable", 400),
    }},
}


def read(fmt, data, offset=0):
    return unpack_from(">" + fmt, data, offset)


@lru_cache(maxsize=32)
def font_tables(path, index):
    data = path.read_bytes()
    offset = read("I", data, 12 + index * 4)[0] if data[:4] == b"ttcf" else 0
    tables = {}
    for i in range(read("H", data, offset + 4)[0]):
        pos = offset + 12 + i * 16
        tag = data[pos:pos + 4].decode("latin1")
        start, size = read("II", data, pos + 8)
        tables[tag] = data[start:start + size]
    return data[offset:offset + 4], tables


def names_from(tables):
    data = tables["name"]
    result, priority = {}, {}
    for i in range(read("H", data, 2)[0]):
        platform, encoding, lang, key, size, off = read("6H", data, 6 + i * 12)
        if platform not in (0, 1, 3):
            continue
        start = read("H", data, 4)[0] + off
        value = data[start:start + size].decode("utf-16-be" if platform in (0, 3) else "mac_roman", errors="replace")
        score = (10 if lang in (0, 1033) else 0) + (2 if platform in (0, 3) else 0)
        if score > priority.get(key, -1):
            result[key], priority[key] = value, score
    return result


def cmap_from(tables):
    data = tables["cmap"]
    mapping = {}
    offsets = set()
    for i in range(read("H", data, 2)[0]):
        platform, encoding, off = read("HHI", data, 4 + i * 8)
        if platform == 0 or (platform == 3 and encoding in (1, 10)):
            offsets.add(off)
    for off in sorted(offsets, key=lambda p: read("H", data, p)[0]):
        form = read("H", data, off)[0]
        if form == 12:
            for i in range(read("I", data, off + 12)[0]):
                start, end, first = read("III", data, off + 16 + i * 12)
                for cp in range(start, end + 1):
                    if first + cp - start:
                        mapping[cp] = first + cp - start
        elif form == 4:
            count = read("H", data, off + 6)[0] // 2
            for i in range(count):
                end = read("H", data, off + 14 + i * 2)[0]
                start = read("H", data, off + 16 + count * 2 + i * 2)[0]
                delta = read("h", data, off + 16 + count * 4 + i * 2)[0]
                loc = off + 16 + count * 6 + i * 2
                displacement = read("H", data, loc)[0]
                for cp in range(start, min(end, 65534) + 1):
                    gid = read("H", data, loc + displacement + 2 * (cp - start))[0] if displacement else cp
                    if not displacement or gid:
                        gid = (gid + delta) & 0xffff
                    if gid:
                        mapping[cp] = gid
    return mapping


def coverage_ranges(mapping):
    result = []
    for cp in sorted(mapping):
        if result and cp == result[-1][1] + 1:
            result[-1][1] = cp
        else:
            result.append([cp, cp])
    return result


def glyph_height(tables, mapping, char):
    gid = mapping.get(ord(char), 0)
    if "glyf" not in tables:
        return 0
    long_loca = read("h", tables["head"], 50)[0]
    off = read("I" if long_loca else "H", tables["loca"], gid * (4 if long_loca else 2))[0]
    if not long_loca:
        off *= 2
    return read("h", tables["glyf"], off + 8)[0]


def features_from(tables, names):
    features = {}
    for table in ("GSUB", "GPOS"):
        if table not in tables:
            continue
        data = tables[table]
        off = read("H", data, 6)[0]
        for i in range(read("H", data, off)[0]):
            pos = off + 2 + i * 6
            tag = data[pos:pos + 4].decode("ascii")
            entry = features.setdefault(tag, {"tag": tag, "source": "OpenType"})
            feature = off + read("H", data, pos + 4)[0]
            params = read("H", data, feature)[0]
            if params and tag.startswith(("cv", "ss")):
                param = feature + params
                entry["label"] = names.get(read("H", data, param + 2)[0], tag)
                if tag.startswith("cv"):
                    count, first = read("HH", data, param + 8)
                    entry["options"] = [names.get(first + j, "Alternate " + str(j + 1)) for j in range(count)]
                    char_count = read("H", data, param + 12)[0]
                    entry["sample"] = "".join(chr(int.from_bytes(data[param + 14 + j * 3:param + 17 + j * 3], "big")) for j in range(min(char_count, 8)))
    # These AAT selectors have direct CSS/OpenType tag equivalents in shaping engines.
    if "feat" in tables:
        data = tables["feat"]
        for i in range(read("H", data, 4)[0]):
            kind, count, settings, flags, name = read("HHIHH", data, 12 + i * 12)
            values = [read("HH", data, settings + j * 4)[0] for j in range(count)]
            for type_id, selector, tag, label in [(1, 2, "liga", "Common ligatures"), (6, 1, "pnum", "Proportional numerals"), (17, 1, "aalt", "Alternate punctuation")]:
                if kind == type_id and selector in values:
                    features[tag] = {"tag": tag, "label": label, "source": "Apple typography"}
    if "kern" in tables:
        features.setdefault("kern", {"tag": "kern", "source": "Apple typography"})
    return sorted(features.values(), key=lambda item: item["tag"])


@lru_cache(maxsize=1)
def manifest():
    result = {}
    for key, font in FONTS.items():
        faces = {}
        for style, (path, index, label, weight) in font["faces"].items():
            if not path.is_file():
                continue
            _, tables = font_tables(path, index)
            names = names_from(tables)
            mapping = cmap_from(tables)
            axes = []
            if "fvar" in tables:
                data = tables["fvar"]
                offset = read("H", data, 4)[0]
                count, size = read("HH", data, 8)
                for i in range(count):
                    pos = offset + size * i
                    tag = data[pos:pos + 4].decode("ascii")
                    low, default, high = [n / 65536 for n in read("iii", data, pos + 4)]
                    axes.append({"tag": tag, "min": low, "default": default, "max": high, "label": names.get(read("H", data, pos + 18)[0], tag)})
            faces[style] = {"label": label, "weight": weight, "axes": axes,
                "features": features_from(tables, names), "coverage": coverage_ranges(mapping),
                "upem": read("H", tables["head"], 18)[0],
                "xHeight": glyph_height(tables, mapping, "x"), "capHeight": glyph_height(tables, mapping, "H"),
                "family": "tfo-" + key + "-" + style, "url": "/font/" + key + "/" + style + ".ttf"}
        result[key] = {"name": font["name"], "short": font["short"], "faces": faces, "available": bool(faces)}
    return result


def checksum(data):
    data += b"\0" * (-len(data) % 4)
    return sum(read(str(len(data) // 4) + "I", data)) & 0xffffffff


@lru_cache(maxsize=32)
def standalone_font(key, style):
    path, index, _, _ = FONTS[key]["faces"][style]
    version, tables = font_tables(path, index)
    tables = dict(tables)
    head = bytearray(tables["head"])
    head[8:12] = b"\0" * 4
    tables["head"] = bytes(head)
    tables.pop("DSIG", None)
    count = len(tables)
    power = 2 ** (count.bit_length() - 1)
    header = version + pack(">HHHH", count, power * 16, power.bit_length() - 1, count * 16 - power * 16)
    records, body = b"", b""
    head_offset = 0
    for tag, data in sorted(tables.items()):
        off = 12 + count * 16 + len(body)
        if tag == "head":
            head_offset = off
        records += tag.encode("latin1") + pack(">III", checksum(data), off, len(data))
        body += data + b"\0" * (-len(data) % 4)
    output = bytearray(header + records + body)
    output[head_offset + 8:head_offset + 12] = pack(">I", (0xb1b0afba - checksum(bytes(output))) & 0xffffffff)
    return bytes(output)


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        path = unquote(urlsplit(self.path).path)
        try:
            if path == "/font-data.js":
                data = ("window.FONT_DATA = " + json.dumps(manifest()) + ";").encode()
                content_type = "text/javascript; charset=utf-8"
            elif path == "/character-names":
                text = parse_qs(urlsplit(self.path).query).get("text", [""])[0][:128]
                names = [{"codepoint": f"U+{ord(char):04X}",
                          "name": unicodedata.name(char, "UNNAMED CHARACTER")}
                         for char in text]
                data = json.dumps(names).encode()
                content_type = "application/json; charset=utf-8"
            elif path.startswith("/font/"):
                parts = path.strip("/").split("/")
                if len(parts) != 3 or not parts[2].endswith(".ttf"):
                    raise KeyError(path)
                data = standalone_font(parts[1], parts[2][:-4])
                content_type = "font/ttf"
            else:
                file = (ROOT / (path.lstrip("/") or "index.html")).resolve()
                if not file.is_relative_to(ROOT) or not file.is_file():
                    raise FileNotFoundError(path)
                data = file.read_bytes()
                content_type = mimetypes.guess_type(file)[0] or "application/octet-stream"
            self.send_response(200)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "no-cache")
            self.end_headers()
            self.wfile.write(data)
        except (KeyError, FileNotFoundError, ValueError):
            self.send_error(404)

    def log_message(self, fmt, *args):
        if len(args) < 2 or str(args[1]) != "200":
            super().log_message(fmt, *args)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    print(f"Typeface/Off mockup: http://127.0.0.1:{args.port}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        server.server_close()
