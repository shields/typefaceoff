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

def provenance($catalog; $frequencies):
  {
    hyperglot: ($catalog.version | select(type == "string" and length > 0) // error("Missing Hyperglot version")),
    source: ($catalog.source | select(. == "https://github.com/rosettatype/hyperglot") // error("Review the Hyperglot source and NOTICE")),
    finefreq: ($frequencies | capture("(?m)^# FineFreq .*pinned commit (?<sha>[a-f0-9]{40});").sha // error("Missing FineFreq commit")),
    wikipedia: ($frequencies | capture("(?m)^# Ethnologue: .*revision (?<id>[0-9]+)\\)").id // error("Missing Wikipedia revision"))
  };
