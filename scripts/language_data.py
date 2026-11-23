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

import argparse
import json
import unicodedata
from collections import Counter
from importlib.metadata import distribution, version
from pathlib import Path
from typing import cast

from hyperglot import Languages, Orthography

ATTRIBUTES = ("base", "auxiliary", "numerals", "punctuation", "currency")
STATUSES = {"primary", "historical"}
VALIDITIES = {"preliminary", "verified"}
type Record = dict[str, object]


def string(value: object) -> str:
    if value is None:
        return ""
    if not isinstance(value, str):
        raise TypeError(value)
    return value


def strings(value: object) -> list[str]:
    if value is None:
        return []
    if not isinstance(value, list):
        raise TypeError(value)
    return [string(item) for item in value]


def unique(values: list[str]) -> list[str]:
    return list(dict.fromkeys(values))


def notes(value: object) -> list[str]:
    if not value:
        return []
    if isinstance(value, str):
        return [value]
    if not isinstance(value, list):
        raise TypeError(value)
    return [
        string(item.get("note")) if isinstance(item, dict) else string(item)
        for item in value
    ]


def category(orthography: Orthography, attribute: str) -> Record:
    characters = unique(string(orthography.get(attribute)).split())
    if attribute == "base":
        requirements = list(orthography.get_chars("base"))
    elif attribute == "auxiliary":
        requirements = list(orthography.get_chars("aux"))
    else:
        requirements = list(getattr(orthography, attribute))
    sequences = [
        item
        for item in characters
        if len(item) > 1
        and not item.startswith("◌")
        and any(unicodedata.category(char).startswith("M") for char in item)
    ]
    return {
        "characters": " ".join(characters),
        "requirements": " ".join(
            sorted(set(requirements), key=lambda item: tuple(map(ord, item)))
        ),
        "sequences": " ".join(sequences),
    }


def orthography_record(iso: str, index: int, raw: Record) -> Record:
    orthography = Orthography(raw)
    script = orthography.script
    status = orthography.status
    categories = {attr: category(orthography, attr) for attr in ATTRIBUTES}
    if not categories["base"]["characters"]:
        raise ValueError(raw)
    return {
        "id": f"{iso}/{index}/{orthography['script_iso']}/{status}",
        "script": script,
        "scriptCode": orthography["script_iso"],
        "status": status,
        "autonym": string(orthography.get("autonym")),
        "grouped": bool(orthography.get("preferred_as_group")),
        "categories": categories,
        "notes": unique(
            notes(orthography.get("note"))
            + notes(orthography.get("design_requirements"))
        ),
    }


def database(records: Record | None = None) -> Record:
    languages = Languages(validity="todo") if records is None else records
    exported: list[Record] = []
    excluded: Counter[str] = Counter()
    for iso in sorted(languages):
        language = cast("Record", languages[iso])
        if language.get("validity") not in VALIDITIES:
            excluded["data confidence"] += 1
            continue
        orthographies = [
            orthography_record(iso, index, raw)
            for index, raw in enumerate(
                cast("list[Record]", language.get("orthographies", []))
            )
            if raw.get("status", "primary") in STATUSES
        ]
        if not orthographies:
            excluded["no primary or historical orthography"] += 1
            continue
        speakers = language.get("speakers")
        if speakers == "unknown":
            speakers = None
        if speakers is not None and (not isinstance(speakers, int) or speakers < 0):
            raise ValueError(speakers)
        date = language.get("speakers_date")
        exported.append(
            {
                "id": iso,
                "name": string(language.get("preferred_name") or language.get("name")),
                "isoName": string(language.get("name")),
                "status": string(language.get("status", "living")),
                "validity": string(language.get("validity")),
                "speakers": speakers,
                "speakersDate": str(date) if date is not None else None,
                "autonyms": unique(
                    [string(language.get("autonym"))]
                    + [string(orthography["autonym"]) for orthography in orthographies]
                ),
                "orthographies": orthographies,
                "notes": notes(language.get("note"))
                + notes(language.get("design_requirements")),
                "sources": strings(language.get("sources")),
                "contributors": strings(language.get("contributors")),
                "reviewers": strings(language.get("reviewers")),
            }
        )
    return {
        "schema": 1,
        "version": version("hyperglot"),
        "source": "https://github.com/rosettatype/hyperglot",
        "excluded": dict(sorted(excluded.items())),
        "languages": exported,
    }


def license_text() -> str:
    package = distribution("hyperglot")
    files = [
        path for path in package.files or [] if str(path).endswith("/licenses/LICENSE")
    ]
    if len(files) != 1:
        raise ValueError(files)
    return package.locate_file(files[0]).read_text(encoding="utf-8")


def write(output: Path, *, check: bool) -> None:
    data = database()
    license_file = output.parent / "Hyperglot-LICENSE"
    upstream_license = license_text()
    if check:
        if json.loads(output.read_text(encoding="utf-8")) != data:
            message = (
                "Bundled language data differs; regenerate it with make languages."
            )
            raise ValueError(message)
        if license_file.read_text(encoding="utf-8") != upstream_license:
            message = "Bundled Hyperglot license differs from the upstream license."
            raise ValueError(message)
    else:
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(
            json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        license_file.write_text(upstream_license, encoding="utf-8")
    languages = cast("list[Record]", data["languages"])
    orthographies = sum(
        len(cast("list[Record]", lang["orthographies"])) for lang in languages
    )
    print(
        f"Hyperglot {data['version']}: {len(languages)} languages, "
        f"{orthographies} orthographies"
    )
    print(f"Excluded records: {data['excluded']}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    write(args.output, check=args.check)


if __name__ == "__main__":
    main()
