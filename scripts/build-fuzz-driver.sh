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

source_executable=$1
driver_app=$2
contents="$driver_app/Contents"
executable="$contents/MacOS/ui-fuzz"

mkdir -p "$contents/MacOS"
install -m 755 "$source_executable" "$executable"
install -m 644 Config/UIFuzzDriver-Info.plist "$contents/Info.plist"
codesign --force --sign - --identifier com.typefaceoff.ui-fuzz \
    --requirements '=designated => identifier "com.typefaceoff.ui-fuzz"' \
    "$driver_app"
