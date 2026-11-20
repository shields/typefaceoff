#!/bin/sh
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
