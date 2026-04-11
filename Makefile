.PHONY: help build install uninstall clean generate format test
.DEFAULT_GOAL := help

# ─── Configuration ────────────────────────────────────────────────
SCHEME       := MDViewer
CONFIG       := Release
PROJECT      := MDViewer.xcodeproj
APP_NAME     := MDViewer.app
INSTALL_DIR  := /Applications
# Use an explicit derivedDataPath instead of parsing xcodebuild -showBuildSettings.
# Robust against Apple changing output format, and avoids running xcodebuild during parse.
DERIVED_DATA := build
BUILD_DIR    := $(DERIVED_DATA)/Build/Products/$(CONFIG)

# Shared xcodebuild args
XCBUILD := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -derivedDataPath $(DERIVED_DATA)

# ─── Targets ──────────────────────────────────────────────────────

## help: Show this help
help:
	@echo "MDViewer Makefile targets:"
	@echo ""
	@sed -n 's/^## //p' $(MAKEFILE_LIST) | awk -F: '{printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

## generate: Regenerate Xcode project from project.yml
generate:
	@command -v xcodegen >/dev/null || { echo "Error: xcodegen not found. Install via: brew install xcodegen"; exit 1; }
	@xcodegen generate

## build: Build the app (Release configuration)
build: generate
	@echo "Building $(SCHEME)..."
	@set -o pipefail; $(XCBUILD) -configuration $(CONFIG) build 2>&1 \
		| { grep -E "error:|warning:.*error|BUILD (FAILED|SUCCEEDED)" || true; } \
		|| { echo "❌ BUILD FAILED — see errors above"; exit 1; }

## install: Build and install to /Applications
install: build
	@echo "Installing to $(INSTALL_DIR)/$(APP_NAME)..."
	@pgrep -x MDViewer >/dev/null && { echo "⚠️  MDViewer is running. Quit it first with ⌘Q or: killall MDViewer"; exit 1; } || true
	@rm -rf "$(INSTALL_DIR)/$(APP_NAME)"
	@cp -R "$(BUILD_DIR)/$(APP_NAME)" "$(INSTALL_DIR)/"
	@qlmanage -r >/dev/null 2>&1
	@/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f "$(INSTALL_DIR)/$(APP_NAME)"
	@echo ""
	@echo "✅ MDViewer installed to $(INSTALL_DIR)/$(APP_NAME)"
	@echo ""
	@echo "  Open a file:   open -a MDViewer yourfile.md"
	@echo "  Quick Look:    select a .md file in Finder → press Space"
	@echo ""
	@echo "Note: on first launch, you may need to allow MDViewer in"
	@echo "  System Settings → Privacy & Security → Open Anyway"

## uninstall: Remove MDViewer from /Applications
uninstall:
	@rm -rf "$(INSTALL_DIR)/$(APP_NAME)"
	@qlmanage -r >/dev/null 2>&1
	@echo "MDViewer uninstalled."

## test: Run tests with coverage report
RESULT_BUNDLE := /tmp/mdviewer-test.xcresult
test: generate
	@rm -rf $(RESULT_BUNDLE)
	@set -o pipefail; $(XCBUILD) -configuration Debug \
		-enableCodeCoverage YES -resultBundlePath $(RESULT_BUNDLE) test 2>&1 \
		| { grep -E "Test run|passed|failed|✔|✘" || true; } \
		| tail -5 \
		|| { echo "❌ TESTS FAILED — see errors above"; exit 1; }
	@echo ""
	@echo "Coverage:"
	@xcrun xccov view --report $(RESULT_BUNDLE) 2>/dev/null \
		| grep "MDViewer.app" \
		| awk '{for(i=1;i<=NF;i++) if($$i ~ /%/) print "  " $$i}' \
		|| echo "  (coverage data unavailable)"

## format: Run SwiftFormat on all sources
format:
	@command -v swiftformat >/dev/null || { echo "Error: swiftformat not found. Install via: brew install swiftformat"; exit 1; }
	@swiftformat MDViewer Shared MDViewerQuickLook Tests --swiftversion 6
	@echo "Formatted."

## clean: Remove build artifacts
clean:
	@rm -rf $(DERIVED_DATA)
	@echo "Clean."
