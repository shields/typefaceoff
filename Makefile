export CLANG_MODULE_CACHE_PATH := $(CURDIR)/.build/ModuleCache
SWIFT_FLAGS = --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security
APP = .build/xcode/Build/Products/Debug/TypefaceOff.app
XCODE_FLAGS = -quiet -project TypefaceOff.xcodeproj -scheme TypefaceOff -configuration Debug -derivedDataPath .build/xcode -destination 'platform=macOS' CODE_SIGN_IDENTITY=-
RAW_FUZZ_TOOL = .build/fuzz-tool/debug/ui-fuzz
FUZZ_DRIVER_APP = .build/fuzz-driver/UIFuzzDriver.app
FUZZ_COVERAGE_APP = .build/fuzz-coverage/Build/Products/FuzzCoverage/TypefaceOff.app
FUZZ_BENCHMARK_APP = .build/fuzz-benchmark/FuzzBenchmark/TypefaceOff.app
FUZZ_SWIFT_FLAGS = $(SWIFT_FLAGS) --scratch-path .build/fuzz-tool
FUZZ_ARTIFACTS ?= $(CURDIR)/.build/ui-fuzz
FREQUENCIES_BIN = .build/character-frequencies/character-frequencies

.PHONY: build project run test test-app coverage lint fmt setup review fuzz fuzz-build fuzz-replay fuzz-minimize fuzz-benchmark frequencies benchmark

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

# Needs network access on first run; downloads are cached in .build.
frequencies:
	mkdir -p .build/character-frequencies
	swiftc -swift-version 6 -O scripts/character-frequencies.swift -o $(FREQUENCIES_BIN)
	$(FREQUENCIES_BIN)

review: project
	xcodebuild $(XCODE_FLAGS) CODE_SIGN_ENTITLEMENTS= TYPEFACEOFF_REVIEW_DIR="$(CURDIR)/.build/review" -only-testing:TypefaceOffTests/ReviewScreens test

fuzz-build: project
	swift build $(FUZZ_SWIFT_FLAGS) --product ui-fuzz
	./scripts/build-fuzz-driver.sh "$(RAW_FUZZ_TOOL)" "$(FUZZ_DRIVER_APP)"
	xcodebuild -quiet -project TypefaceOff.xcodeproj -scheme TypefaceOff -configuration FuzzCoverage -derivedDataPath .build/fuzz-coverage -destination 'platform=macOS' CODE_SIGN_IDENTITY=- CODE_SIGN_ENTITLEMENTS= ARCHS=$(shell uname -m) build
	xcodebuild -quiet -project TypefaceOff.xcodeproj -target TypefaceOff -configuration FuzzBenchmark SYMROOT="$(CURDIR)/.build/fuzz-benchmark" OBJROOT="$(CURDIR)/.build/fuzz-benchmark/obj" CODE_SIGN_IDENTITY=- CODE_SIGN_ENTITLEMENTS= ARCHS=$(shell uname -m) build

# Campaigns run until SIGINT or SIGTERM unless FUZZ_ARGS includes --duration.
fuzz: fuzz-build
	./scripts/run-fuzz-driver.sh "$(FUZZ_DRIVER_APP)" run --app "$(CURDIR)/$(FUZZ_COVERAGE_APP)" --artifacts "$(abspath $(FUZZ_ARTIFACTS))" $(FUZZ_ARGS)

fuzz-replay: fuzz-build
	test -n "$(CASE)"
	./scripts/run-fuzz-driver.sh "$(FUZZ_DRIVER_APP)" replay --app "$(CURDIR)/$(FUZZ_COVERAGE_APP)" --case "$(abspath $(CASE))" --artifacts "$(abspath $(FUZZ_ARTIFACTS))" $(FUZZ_ARGS)

fuzz-minimize: fuzz-build
	test -n "$(CASE)"
	./scripts/run-fuzz-driver.sh "$(FUZZ_DRIVER_APP)" minimize --app "$(CURDIR)/$(FUZZ_COVERAGE_APP)" --case "$(abspath $(CASE))" --artifacts "$(abspath $(FUZZ_ARTIFACTS))" $(FUZZ_ARGS)

fuzz-benchmark: fuzz-build
	./scripts/run-fuzz-driver.sh "$(FUZZ_DRIVER_APP)" benchmark --app "$(CURDIR)/$(FUZZ_BENCHMARK_APP)" --corpus "$(abspath $(or $(CORPUS),$(FUZZ_ARTIFACTS)/corpus))" --artifacts "$(abspath $(FUZZ_ARTIFACTS))" $(FUZZ_ARGS)

benchmark:
	TYPEFACEOFF_BENCHMARK_DIR="$(CURDIR)/.build/similarity-benchmark" swift test $(SWIFT_FLAGS) -c release --filter SimilarityBenchmark

lint:
	swift format lint --strict --recursive Sources Tests Package.swift scripts
	bunx --no-install prettier --check .
	shellcheck scripts/*.sh
	shfmt -i 4 -d scripts
	zizmor --persona pedantic .github/workflows

fmt:
	swift format format --in-place --recursive Sources Tests Package.swift scripts
	bunx --no-install prettier --write .
	shfmt -i 4 -w scripts

setup:
	bun install --frozen-lockfile
	lefthook install
