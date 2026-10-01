BUILD_DIR ?= $(CURDIR)/.build
APP = $(BUILD_DIR)/AXPressRepro.app
EXECUTABLE = $(APP)/Contents/MacOS/AXPressRepro
CLIENT = $(BUILD_DIR)/press
SWIFT_FLAGS = -parse-as-library -swift-version 6 -warnings-as-errors -O -module-cache-path "$(BUILD_DIR)/ModuleCache"

.PHONY: build reproduce lint fmt

build: $(EXECUTABLE) $(CLIENT)

$(EXECUTABLE): App.swift Info.plist
	mkdir -p "$(APP)/Contents/MacOS"
	plutil -lint Info.plist
	cp Info.plist "$(APP)/Contents/Info.plist"
	xcrun swiftc $(SWIFT_FLAGS) App.swift -o "$@"
	codesign --force --sign - "$(APP)"

$(CLIENT): Press.swift
	mkdir -p "$(BUILD_DIR)"
	xcrun swiftc $(SWIFT_FLAGS) Press.swift -o "$@"

reproduce: build
	"$(CLIENT)" "$(EXECUTABLE)" label
	"$(CLIENT)" "$(EXECUTABLE)" identifier
	"$(CLIENT)" "$(EXECUTABLE)" none

lint:
	xcrun swift format lint --strict App.swift Press.swift
	plutil -lint Info.plist

fmt:
	xcrun swift format format --in-place App.swift Press.swift
