.PHONY: build install uninstall clean generate format test

SCHEME = MDViewer
CONFIG = Release
BUILD_DIR = $(shell xcodebuild -project MDViewer.xcodeproj -scheme $(SCHEME) -configuration $(CONFIG) -showBuildSettings 2>/dev/null | grep " BUILT_PRODUCTS_DIR" | awk '{print $$3}')
APP_NAME = MDViewer.app
INSTALL_DIR = /Applications

# Generate Xcode project from project.yml (requires xcodegen)
generate:
	@command -v xcodegen >/dev/null || { echo "Error: xcodegen not found. Install via: brew install xcodegen"; exit 1; }
	@xcodegen generate

# Build the app
build: generate
	@echo "Building $(SCHEME)..."
	@xcodebuild -project MDViewer.xcodeproj -scheme $(SCHEME) -configuration $(CONFIG) build 2>&1 | tail -1

# Build, copy to /Applications, and enable Quick Look extension
install: build
	@echo "Installing to $(INSTALL_DIR)/$(APP_NAME)..."
	@rm -rf "$(INSTALL_DIR)/$(APP_NAME)"
	@cp -R "$(BUILD_DIR)/$(APP_NAME)" "$(INSTALL_DIR)/"
	@qlmanage -r >/dev/null 2>&1
	@/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f "$(INSTALL_DIR)/$(APP_NAME)"
	@echo ""
	@echo "Done! MDViewer installed to $(INSTALL_DIR)/$(APP_NAME)"
	@echo ""
	@echo "  Open a file:   open -a MDViewer yourfile.md"
	@echo "  Quick Look:    select a .md file in Finder → press Space"
	@echo ""
	@echo "Note: on first launch, you may need to allow MDViewer in"
	@echo "  System Settings → Privacy & Security → Open Anyway"

# Remove from /Applications
uninstall:
	@rm -rf "$(INSTALL_DIR)/$(APP_NAME)"
	@qlmanage -r >/dev/null 2>&1
	@echo "MDViewer uninstalled."

# Run tests with coverage
RESULT_BUNDLE = /tmp/mdviewer-test.xcresult
test: generate
	@rm -rf $(RESULT_BUNDLE)
	@xcodebuild -project MDViewer.xcodeproj -scheme $(SCHEME) -configuration Debug \
		-enableCodeCoverage YES -resultBundlePath $(RESULT_BUNDLE) \
		test 2>&1 | grep -E "Test run|passed|failed|✔|✘" | tail -5
	@echo ""
	@echo "Coverage:"
	@xcrun xccov view --report $(RESULT_BUNDLE) 2>/dev/null | grep "MDViewer.app" | awk '{for(i=1;i<=NF;i++) if($$i ~ /%/) print "  " $$i}' || echo "  (coverage data unavailable)"

# Format Swift code
format:
	@command -v swiftformat >/dev/null || { echo "Error: swiftformat not found. Install via: brew install swiftformat"; exit 1; }
	@swiftformat MDViewer Shared MDViewerQuickLook Tests --swiftversion 6
	@echo "Formatted."

# Clean build artifacts
clean:
	@xcodebuild -project MDViewer.xcodeproj -scheme $(SCHEME) clean 2>/dev/null || true
	@echo "Clean."
