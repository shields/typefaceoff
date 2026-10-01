BUILD_DIR ?= $(CURDIR)/.build
APP = $(BUILD_DIR)/TabPickerRepro.app
EXECUTABLE = $(APP)/Contents/MacOS/TabPickerRepro
CLIENT = $(BUILD_DIR)/reproduce
SWIFT_FLAGS = -swift-version 6 -warnings-as-errors -O -module-cache-path "$(BUILD_DIR)/ModuleCache"

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
