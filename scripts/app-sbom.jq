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

include "app-provenance";

def package($id; $name; $url; $version; $license):
  {
    SPDXID: ("SPDXRef-" + $id), name: $name, downloadLocation: $url,
    filesAnalyzed: false, copyrightText: "NOASSERTION",
    licenseConcluded: "NOASSERTION", licenseDeclared: $license
  } + (if $version == null then {} else {versionInfo: $version} end);

def relationship($from; $type; $to):
  {spdxElementId: $from, relationshipType: $type, relatedSpdxElement: $to};

def file_id($path):
  [.files[] | select(.fileName == $path) | .SPDXID] |
  if length == 1 then first else error("Expected one archived file at " + $path) end;

def static_packages:
  split("\n") | map(select(length > 0)) | group_by(split("(")[0]) | to_entries | map(
    (.value[0] | split("(")[0]) as $archive |
    (if $archive == "libclang_rt.osx.a" then
      package("Static-" + (.key | tostring); "LLVM compiler-rt (" + $archive + ")";
        "https://compiler-rt.llvm.org/"; null; "Apache-2.0 WITH LLVM-exception")
    else
      package("Unreviewed-Static-" + (.key | tostring); $archive; "NOASSERTION"; null; "NOASSERTION")
    end) + {sourceInfo: ("Xcode " + $xcode + " link map: " + (.value | join(", ")))}
  );

. as $scan |
file_id("Contents/MacOS/TypefaceOff") as $executable |
"Contents/Resources/TypefaceOff_TypefaceCore.bundle/Contents/Resources/" as $resources |
file_id($resources + "languages.json") as $languages |
file_id($resources + "character-frequencies.tsv") as $weights |
provenance($catalog[0]; $frequencies) as $data |
($static | static_packages) as $archives |
($dynamic | split("\n") | map(select(length > 0))) as $libraries |
($libraries | map(select(test("^(/System/Library/|/usr/lib/)") | not)) | to_entries | map(
  package("Unreviewed-Dynamic-" + (.key | tostring); .value; "NOASSERTION"; null; "NOASSERTION")
)) as $external |
.creationInfo.creators += ["Tool: TypefaceOff app-sbom.sh"] |
.comment = "Syft inventories the archived app. Xcode link maps identify static libraries. The generated resources, reading sample, and icon are traced to their source materials." |
.packages += ($archives + $external + [
  (package("TypefaceCore"; "TypefaceCore"; "NOASSERTION"; null; "NOASSERTION") +
    {sourceInfo: "Built from Sources/TypefaceCore in the Typeface/Off source tree."}),
  (package("macOS"; "macOS system frameworks and libraries"; "NOASSERTION"; null; "NOASSERTION") +
    {sourceInfo: ($libraries | map(select(test("^(/System/Library/|/usr/lib/)"))) | join("\n"))}),
  (package("Hyperglot"; "Hyperglot language database"; $data.source; $data.hyperglot; "Apache-2.0") +
    {originator: "Organization: Rosetta Type/Research"}),
  (package("FineFreq"; "FineFreq"; "https://github.com/Bin-2/FineFreq"; $data.finefreq; "CC-BY-4.0") +
    {originator: "Person: Binbin Xu"}),
  package("FineWeb"; "FineWeb"; "https://huggingface.co/datasets/HuggingFaceFW/fineweb"; null; "ODC-By-1.0"),
  package("FineWeb2"; "FineWeb2"; "https://huggingface.co/datasets/HuggingFaceFW/fineweb-2"; null; "ODC-By-1.0"),
  package("CommonCrawl"; "Common Crawl"; "https://commoncrawl.org"; null; "NOASSERTION"),
  (package("Leipzig"; "Leipzig Corpora Collection"; "https://wortschatz-leipzig.de/en/download/"; null; "CC-BY-4.0") +
    {originator: "Organization: Universität Leipzig", licenseComments: "Terms for the downloadable text corpora: https://wortschatz-leipzig.de/en/usage"}),
  package("Wikipedia"; "List of languages by total number of speakers"; ("https://en.wikipedia.org/w/index.php?oldid=" + $data.wikipedia); $data.wikipedia; "NOASSERTION"),
  package("Wikidata"; "Wikidata speaker counts"; "https://www.wikidata.org"; null; "CC0-1.0"),
  package("Ethnologue29"; "Ethnologue"; "https://www.ethnologue.com"; "29th edition (2026)"; "NOASSERTION"),
  package("Ethnologue22"; "Ethnologue"; "https://www.ethnologue.com"; "22nd edition (2019)"; "NOASSERTION"),
  (package("QueenAlice"; "Through the Looking-Glass, chapter IX"; "https://www.gutenberg.org/ebooks/12"; "eBook 12"; "NOASSERTION") +
    {originator: "Person: Lewis Carroll", licenseComments: "The text is in the public domain in the United States."}),
  package("HelveticaNeue"; "Helvetica Neue Regular"; "NOASSERTION"; null; "NOASSERTION"),
  package("Arial"; "Arial Regular"; "NOASSERTION"; null; "NOASSERTION")
]) |
.relationships += [
  relationship($executable; "STATIC_LINK"; "SPDXRef-TypefaceCore"),
  ($archives[] | relationship($executable; "STATIC_LINK"; .SPDXID)),
  ($external[] | relationship($executable; "DYNAMIC_LINK"; .SPDXID)),
  relationship($executable; "DYNAMIC_LINK"; "SPDXRef-macOS"),
  relationship("SPDXRef-TypefaceCore"; "CONTAINS"; "SPDXRef-QueenAlice"),
  relationship($languages; "GENERATED_FROM"; "SPDXRef-Hyperglot"),
  (("FineFreq", "Leipzig", "Wikipedia", "Wikidata") |
    relationship($weights; "GENERATED_FROM"; "SPDXRef-" + .)),
  relationship("SPDXRef-Wikipedia"; "GENERATED_FROM"; "SPDXRef-Ethnologue29"),
  relationship("SPDXRef-Wikidata"; "GENERATED_FROM"; "SPDXRef-Ethnologue22"),
  (("SPDXRef-FineWeb", "SPDXRef-FineWeb2") as $corpus |
    relationship("SPDXRef-FineFreq"; "GENERATED_FROM"; $corpus),
    relationship($corpus; "GENERATED_FROM"; "SPDXRef-CommonCrawl")),
  (("Contents/Resources/AppIcon.icns", "Contents/Resources/Assets.car") as $icon |
    ($scan | file_id($icon)) as $file |
    ("SPDXRef-HelveticaNeue", "SPDXRef-Arial") | relationship($file; "GENERATED_FROM"; .))
]
