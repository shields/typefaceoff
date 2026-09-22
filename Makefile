export CLANG_MODULE_CACHE_PATH := $(CURDIR)/.build/ModuleCache
SWIFT_FLAGS = --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security
APP = .build/xcode/Build/Products/Debug/TypefaceOff.app
XCODE_FLAGS = -quiet -project TypefaceOff.xcodeproj -scheme TypefaceOff -configuration Debug -derivedDataPath .build/xcode -destination 'platform=macOS' CODE_SIGN_IDENTITY=-

.PHONY: build project run test test-app coverage lint fmt setup review benchmark

project:
	xcodegen generate --spec project.yml

build: project
	xcodebuild $(XCODE_FLAGS) build

run: build
	open "$(APP)"

test:
	# Font discovery shares macOS's font registry; serialize the package tests.
	swift test $(SWIFT_FLAGS) --enable-code-coverage --no-parallel
	$(MAKE) test-app

test-app: project
	./scripts/test-app.sh $(XCODE_FLAGS)

coverage: test
	./scripts/coverage.sh $(SWIFT_FLAGS)

review: project
	xcodebuild $(XCODE_FLAGS) CODE_SIGN_ENTITLEMENTS= TYPEFACEOFF_REVIEW_DIR="$(CURDIR)/.build/review" -only-testing:TypefaceOffTests/ReviewScreens test

benchmark:
	TYPEFACEOFF_BENCHMARK_DIR="$(CURDIR)/.build/similarity-benchmark" swift test $(SWIFT_FLAGS) -c release --filter SimilarityBenchmark

lint:
	swift format lint --strict --recursive Sources Tests Package.swift
	bunx --no-install prettier --check .
	shellcheck scripts/*.sh
	shfmt -i 4 -d scripts
	zizmor --persona pedantic .github/workflows

fmt:
	swift format format --in-place --recursive Sources Tests Package.swift
	bunx --no-install prettier --write .
	shfmt -i 4 -w scripts

setup:
	bun install --frozen-lockfile
	lefthook install
