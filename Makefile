# ──────────────────────────────────────────────
# CodeTool – SwiftPM → signed .app bundle
# ──────────────────────────────────────────────

APP_NAME       := CodeTool
BUNDLE_ID      := com.codetool.app
VERSION        := 1.0.0
BUILD_NUMBER   := 1

# Ad-hoc sign by default; override with e.g.
#   make build SIGNING_IDENTITY="Apple Development: you@example.com"
SIGNING_IDENTITY ?= -

CONFIGURATION  ?= release
SWIFT_FLAGS    := -c $(CONFIGURATION)

BUILD_DIR      := .build/$(CONFIGURATION)
EXECUTABLE     := $(BUILD_DIR)/$(APP_NAME)
APP_BUNDLE     := $(BUILD_DIR)/$(APP_NAME).app
CONTENTS_DIR   := $(APP_BUNDLE)/Contents
MACOS_DIR      := $(CONTENTS_DIR)/MacOS
RESOURCES_DIR  := $(CONTENTS_DIR)/Resources
TEST_BUILD_DIR := .build/make-test
INSTALL_DIR    ?= /Applications
XCODE_DEV_DIR  := /Applications/Xcode.app/Contents/Developer

ifeq ($(wildcard $(XCODE_DEV_DIR)),)
TEST_SWIFT     := swift
else
TEST_SWIFT     := DEVELOPER_DIR=$(XCODE_DEV_DIR) swift
endif

.PHONY: build test run install clean

# ── Build ─────────────────────────────────────
build:
	@echo "▸ Building $(APP_NAME) ($(CONFIGURATION))…"
	swift build $(SWIFT_FLAGS)
	@echo "▸ Assembling $(APP_NAME).app bundle…"
	@mkdir -p "$(MACOS_DIR)" "$(RESOURCES_DIR)"
	@cp "$(EXECUTABLE)" "$(MACOS_DIR)/$(APP_NAME)"
	@/usr/libexec/PlistBuddy -c "Clear dict" "$(CONTENTS_DIR)/Info.plist" 2>/dev/null || true
	@/usr/libexec/PlistBuddy \
		-c "Add :CFBundleName              string $(APP_NAME)" \
		-c "Add :CFBundleDisplayName       string $(APP_NAME)" \
		-c "Add :CFBundleIdentifier        string $(BUNDLE_ID)" \
		-c "Add :CFBundleVersion           string $(BUILD_NUMBER)" \
		-c "Add :CFBundleShortVersionString string $(VERSION)" \
		-c "Add :CFBundleExecutable        string $(APP_NAME)" \
		-c "Add :CFBundlePackageType       string APPL" \
		-c "Add :CFBundleInfoDictionaryVersion string 6.0" \
		-c "Add :LSMinimumSystemVersion    string 13.0" \
		-c "Add :NSHighResolutionCapable   bool true" \
		-c "Add :NSSupportsAutomaticTermination bool true" \
		"$(CONTENTS_DIR)/Info.plist"
	@echo "▸ Signing with identity: $(SIGNING_IDENTITY)"
	@codesign --force --sign "$(SIGNING_IDENTITY)" --deep "$(APP_BUNDLE)"
	@echo "✔ $(APP_BUNDLE) is ready."

# ── Test ──────────────────────────────────────
test:
	@echo "▸ Running tests…"
	$(TEST_SWIFT) test --scratch-path "$(TEST_BUILD_DIR)"

# ── Run ───────────────────────────────────────
run: build
	@echo "▸ Launching $(APP_NAME)…"
	@open "$(APP_BUNDLE)"

# ── Install ───────────────────────────────────
install: build
	@echo "▸ Installing to $(INSTALL_DIR)/$(APP_NAME).app …"
	@rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	@cp -R "$(APP_BUNDLE)" "$(INSTALL_DIR)/$(APP_NAME).app"
	@echo "✔ Installed."

# ── Clean ─────────────────────────────────────
clean:
	@echo "▸ Cleaning…"
	swift package clean
	@rm -rf "$(TEST_BUILD_DIR)"
	@rm -rf "$(BUILD_DIR)/$(APP_NAME).app"
	@echo "✔ Clean."
