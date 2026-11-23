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

BUILD_DIR ?= $(CURDIR)/.build
APP = $(BUILD_DIR)/TabPickerRepro.app
EXECUTABLE = $(APP)/Contents/MacOS/TabPickerRepro
CLIENT = $(BUILD_DIR)/reproduce
SWIFT_FLAGS = -swift-version 6 -warnings-as-errors -O -target "$(shell uname -m)-apple-macos15.0" -module-cache-path "$(BUILD_DIR)/ModuleCache"

.PHONY: build reproduce lint fmt

build: $(EXECUTABLE) $(CLIENT)

$(EXECUTABLE): App.swift Info.plist
	mkdir -p "$(APP)/Contents/MacOS"
	cp Info.plist "$(APP)/Contents/Info.plist"
	xcrun swiftc $(SWIFT_FLAGS) -parse-as-library App.swift -o "$@"
	codesign --force --sign - "$(APP)"

$(CLIENT): Reproduce.swift
	mkdir -p "$(BUILD_DIR)"
	xcrun swiftc $(SWIFT_FLAGS) -parse-as-library Reproduce.swift -o "$@"

reproduce: build
	"$(CLIENT)" "$(EXECUTABLE)"

lint:
	xcrun swift format lint --strict App.swift Reproduce.swift
	plutil -lint Info.plist

fmt:
	xcrun swift format format --in-place App.swift Reproduce.swift
