#!/bin/sh
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

set -eu

resources=$1
scripts=$(dirname "$0")
jq -njer -L "$scripts" --rawfile notice "$scripts/../NOTICE" \
    --slurpfile catalog "$resources/languages.json" --rawfile frequencies "$resources/character-frequencies.tsv" '
    include "app-provenance";
    provenance($catalog[0]; $frequencies) |
    $notice + "\n---\n\nBundled data sources\n\n" +
    "    Hyperglot \(.hyperglot) contributors — \(.source)/blob/\(.hyperglot)/CONTRIBUTORS.txt\n" +
    "    FineFreq — https://github.com/Bin-2/FineFreq/tree/\(.finefreq)\n" +
    "    Wikipedia revision \(.wikipedia) — https://en.wikipedia.org/w/index.php?oldid=\(.wikipedia)\n"
'
