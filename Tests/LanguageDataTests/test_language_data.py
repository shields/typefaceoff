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

import json
from copy import deepcopy
from typing import cast
lazy from pathlib import Path

import pytest
from language_data import Record, database, license_text, notes, string, strings, write


@pytest.fixture
def language() -> Record:
    return {
        "name": "Example",
        "status": "living",
        "validity": "verified",
        "speakers": 8_300_000,
        "orthographies": [
            {
                "script": "Latin",
                "status": "primary",
                "base": "A a e\u0301 ch",
                "marks": "◌́",
            },
        ],
    }


def test_release_counts_and_default_scope() -> None:
    data = database()
    languages = cast("list[Record]", data["languages"])
    assert data["version"] == "0.8.1"
    assert len(languages) == 705
    assert (
        sum(len(cast("list[Record]", lang["orthographies"])) for lang in languages)
        == 757
    )
    visible = [
        lang
        for lang in languages
        if lang["status"] != "historical" and cast("int", lang["speakers"]) >= 8_300_000
    ]
    assert len(visible) == 108
    assert (
        sum(
            ort["status"] == "primary"
            for lang in visible
            for ort in cast("list[Record]", lang["orthographies"])
        )
        == 119
    )
    assert sum(lang["status"] == "historical" for lang in languages) == 22


def test_inventory_preserves_source_sequences(language: Record) -> None:
    data = database({"tst": language})
    languages = cast("list[Record]", data["languages"])
    ort = cast("list[Record]", languages[0]["orthographies"])[0]
    base = cast("dict[str, Record]", ort["categories"])["base"]
    assert base["characters"] == "A a e\u0301 ch"
    assert base["sequences"] == "e\u0301"
    assert set(string(base["requirements"]).split()) == {"A", "a", "c", "e", "h"}


def test_inheritance_and_grouped_orthographies(language: Record) -> None:
    ort = cast("list[Record]", language["orthographies"])[0]
    ort["base"] = "<eng>"
    ort["preferred_as_group"] = True
    ort["punctuation"] = "<default>"
    data = database({"tst": language})
    exported = cast(
        "list[Record]", cast("list[Record]", data["languages"])[0]["orthographies"]
    )[0]
    assert exported["grouped"] is True
    categories = cast("dict[str, Record]", exported["categories"])
    assert "z" in string(categories["base"]["requirements"]).split()
    assert "." in string(categories["punctuation"]["requirements"]).split()


def test_exclusions_and_unknown_speakers(language: Record) -> None:
    draft = deepcopy(language)
    draft["validity"] = "draft"
    secondary = deepcopy(language)
    cast("list[Record]", secondary["orthographies"])[0]["status"] = "secondary"
    language["speakers"] = "unknown"
    language["speakers_date"] = "2010–2020"
    data = database({"tst": language, "drf": draft, "sec": secondary})
    exported = cast("list[Record]", data["languages"])
    assert len(exported) == 1
    assert exported[0]["speakers"] is None
    assert exported[0]["speakersDate"] == "2010–2020"
    assert data["excluded"] == {
        "data confidence": 1,
        "no primary or historical orthography": 1,
    }


@pytest.mark.parametrize("speakers", [-1, "many"])
def test_invalid_speaker_count_fails(language: Record, speakers: object) -> None:
    language["speakers"] = speakers
    with pytest.raises(ValueError, match=str(speakers)):
        database({"tst": language})


def test_empty_retained_orthography_fails(language: Record) -> None:
    cast("list[Record]", language["orthographies"])[0]["base"] = ""
    with pytest.raises(ValueError, match="base"):
        database({"tst": language})


def test_regeneration_and_license_verification(tmp_path: Path) -> None:
    output = tmp_path / "languages.json"
    write(output, check=False)
    initial = output.read_bytes()
    write(output, check=False)
    assert output.read_bytes() == initial
    assert "Apache License" in license_text()
    write(output, check=True)
    output.write_text("{}", encoding="utf-8")
    with pytest.raises(ValueError, match="regenerate"):
        write(output, check=True)
    output.write_bytes(initial)
    (tmp_path / "Hyperglot-LICENSE").write_text("wrong", encoding="utf-8")
    with pytest.raises(ValueError, match="license differs"):
        write(output, check=True)
    assert len(json.loads(initial)["languages"]) == 705


def test_text_metadata_rejects_invalid_shapes() -> None:
    assert string(None) == ""
    assert strings(None) == []
    assert strings(["a", "b"]) == ["a", "b"]
    assert notes(None) == []
    assert notes("note") == ["note"]
    assert notes(["note", {"note": "design"}]) == ["note", "design"]
    for function in [string, strings, notes]:
        with pytest.raises(TypeError):
            function(7)
