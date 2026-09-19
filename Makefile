export CLANG_MODULE_CACHE_PATH := $(CURDIR)/.build/ModuleCache
export UV_CACHE_DIR := $(CURDIR)/.build/uv-cache
export UV_TOOL_DIR := $(CURDIR)/.build/uv-tools
export RUFF_CACHE_DIR := $(CURDIR)/.build/ruff-cache
SWIFT_FLAGS = --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security
RUFF_FLAGS = --isolated --target-version py314
APP = .build/xcode/Build/Products/Debug/TypefaceOff.app

.PHONY: build project run test coverage lint fmt setup mockup review

project:
	xcodegen generate --spec project.yml

build: project
	xcodebuild -quiet -project TypefaceOff.xcodeproj -scheme TypefaceOff -configuration Debug -derivedDataPath .build/xcode -destination 'platform=macOS' CODE_SIGN_IDENTITY=- build

run: build
	open "$(APP)"

test:
	swift test $(SWIFT_FLAGS) --enable-code-coverage
	node --test mockups/tests/differences.test.js

coverage: test
	./scripts/coverage.sh

review:
	TYPEFACEOFF_REVIEW_DIR="$(CURDIR)/.build/review" swift test $(SWIFT_FLAGS) --enable-code-coverage --filter ReviewScreens

lint:
	swift format lint --strict --recursive Sources Tests Package.swift
	bunx --no-install prettier --check .
	uvx ruff check $(RUFF_FLAGS) mockups/server.py
	uvx ruff format $(RUFF_FLAGS) --check mockups/server.py
	node --check mockups/app.js
	node --check mockups/differences.js
	node --check mockups/tests/differences.test.js
	zizmor --persona pedantic .github/workflows

fmt:
	swift format format --in-place --recursive Sources Tests Package.swift
	bunx --no-install prettier --write .
	uvx ruff format $(RUFF_FLAGS) mockups/server.py

setup:
	bun install --frozen-lockfile
	lefthook install

mockup:
	uv run --python 3.14 mockups/server.py
