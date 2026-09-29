export CLANG_MODULE_CACHE_PATH := $(CURDIR)/.build/ModuleCache
SWIFT_FLAGS = --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security
APP = .build/xcode/Build/Products/Debug/TypefaceOff.app
XCODE_COMMON_FLAGS = -quiet -project TypefaceOff.xcodeproj -configuration Debug -destination 'platform=macOS' CODE_SIGN_IDENTITY=-
XCODE_FLAGS = $(XCODE_COMMON_FLAGS) -scheme TypefaceOff -derivedDataPath .build/xcode
PORTABLE_FLAGS = $(XCODE_COMMON_FLAGS) -scheme PortableTests -derivedDataPath .build/portable
PORTABLE_TESTS = .build/portable-tests.tar
RAW_FUZZ_TOOL = .build/fuzz-tool/debug/ui-fuzz
FUZZ_DRIVER_APP = .build/fuzz-driver/UIFuzzDriver.app
FUZZ_COVERAGE_APP = .build/fuzz-coverage/Build/Products/FuzzCoverage/TypefaceOff.app
FUZZ_BENCHMARK_APP = .build/fuzz-benchmark/FuzzBenchmark/TypefaceOff.app
FUZZ_SWIFT_FLAGS = $(SWIFT_FLAGS) --scratch-path .build/fuzz-tool
FUZZ_ARTIFACTS ?= $(CURDIR)/.build/ui-fuzz
FUZZ_VM = typefaceoff-fuzz
FUZZ_VM_IMAGE = ghcr.io/cirruslabs/macos-golden-gate-vanilla:latest
FUZZ_VM_ARTIFACTS ?= $(CURDIR)/.build/ui-fuzz-vm
FUZZ_VM_FLAGS = $(FUZZ_VM) $(FUZZ_VM_IMAGE) "$(abspath $(FUZZ_VM_ARTIFACTS))" "$(FUZZ_DRIVER_APP)" "$(FUZZ_COVERAGE_APP)"
FREQUENCIES_BIN = .build/character-frequencies/character-frequencies
STARTUP_APP = .build/startup/Build/Products/StartupBenchmark/TypefaceOff.app
STARTUP_RUNS ?= 7
STARTUP_OUTPUT ?= $(CURDIR)/.build/startup-benchmark.json
STARTUP_PROFILE ?= $(CURDIR)/.build/startup-profile.txt

.PHONY: build project run test test-app build-for-testing test-without-building coverage lint fmt setup review fuzz fuzz-build fuzz-vm-setup fuzz-vm fuzz-replay fuzz-minimize fuzz-benchmark frequencies benchmark startup-build benchmark-startup profile-startup

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
	rm -rf .build/xcode/Build/ProfileData
	./scripts/test-app.sh $(XCODE_FLAGS) test

# CI builds these once and runs them on other macOS versions, some too old for this Xcode.
build-for-testing: project
	rm -rf .build/portable/Build/Products
	xcodebuild $(PORTABLE_FLAGS) build-for-testing
	# Test processes search the products directory first, so an older Xcode
	# runs these bundles with the Swift Testing runtime, overlays, and XCTest
	# support library they were built against. Like xcodebuild,
	# `xcode-select -p` reports DEVELOPER_DIR when it's set.
	ditto "$$(xcode-select -p)/../SharedFrameworks/Testing.framework" .build/portable/Build/Products/Debug/Testing.framework
	ditto "$$(xcode-select -p)/../SharedFrameworks/lib_TestingInterop.dylib" .build/portable/Build/Products/Debug/lib_TestingInterop.dylib
	ditto "$$(xcode-select -p)/Platforms/MacOSX.platform/Developer/usr/lib/libXCTestSwiftSupport.dylib" .build/portable/Build/Products/Debug/libXCTestSwiftSupport.dylib
	for overlay in "$$(xcode-select -p)"/../SharedFrameworks/_Testing_*.framework; do \
		ditto "$$overlay" ".build/portable/Build/Products/Debug/$$(basename "$$overlay")"; \
	done
	tar -cf $(PORTABLE_TESTS) -C .build/portable/Build Products

test-without-building:
	rm -rf .build/portable-run
	mkdir -p .build/portable-run
	tar -xf $(PORTABLE_TESTS) -C .build/portable-run
	./scripts/test-app.sh -quiet -destination 'platform=macOS' -parallel-testing-enabled NO -xctestrun .build/portable-run/Products/*.xctestrun test-without-building

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

fuzz-vm-setup: fuzz-build
	./scripts/fuzz-vm.sh setup $(FUZZ_VM_FLAGS)

fuzz-vm: fuzz-build
	./scripts/fuzz-vm.sh run $(FUZZ_VM_FLAGS) $(FUZZ_ARGS)

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

startup-build: project
	xcodebuild -quiet -project TypefaceOff.xcodeproj -scheme TypefaceOff -configuration StartupBenchmark -derivedDataPath .build/startup -destination 'platform=macOS' CODE_SIGN_IDENTITY=- build

benchmark-startup: startup-build
	swiftc -swift-version 6 -warnings-as-errors -O scripts/startup-benchmark.swift -o .build/startup/benchmark
	STARTUP_APP="$(abspath $(STARTUP_APP))" STARTUP_RUNS="$(STARTUP_RUNS)" STARTUP_OUTPUT="$(STARTUP_OUTPUT)" STARTUP_REVISION="$$(git rev-parse HEAD)" .build/startup/benchmark

profile-startup: startup-build
	./scripts/profile-startup.sh "$(abspath $(STARTUP_APP))" "$(abspath $(STARTUP_PROFILE))"

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
