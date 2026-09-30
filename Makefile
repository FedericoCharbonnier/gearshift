APP := build/GearShift.app
ZIP := build/GearShift.zip
INSTALLED_APP := $(HOME)/Applications/GearShift.app
SKILL_DIR := skills/gearshift
PLUGIN_JSON := .claude-plugin/plugin.json
VERSION = $(shell plutil -extract CFBundleShortVersionString raw -o - Resources/Info.plist)
# A stable local identity keeps the Accessibility grant across rebuilds; ad-hoc otherwise.
# Override with `make app SIGN_IDENTITY=-` (as `make release` does).
ifeq ($(origin SIGN_IDENTITY), undefined)
SIGN_IDENTITY := $(shell security find-identity -p codesigning 2>/dev/null | grep -q '"GearShift Local"' && echo 'GearShift Local' || echo '-')
endif

.PHONY: test test-skill install-skill install app run release version clean

test: test-skill
	swift run GearShiftCoreTests

test-skill:
	bash Tests/skill/test_register.sh

# For development: a personal copy of the skill, without APP_VERSION, so it never downloads the app
# (`make install` installs the local build instead). An installed gearshift plugin shadows it.
install-skill:
	mkdir -p ~/.claude/skills/gearshift
	cp $(SKILL_DIR)/SKILL.md $(SKILL_DIR)/register.sh ~/.claude/skills/gearshift/
	chmod +x ~/.claude/skills/gearshift/register.sh

app:
	swift build --configuration release --product GearShift
	rm -rf $(APP) build/GearShift.iconset
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp .build/release/GearShift $(APP)/Contents/MacOS/GearShift
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	swift scripts/make-icon.swift build/GearShift.iconset
	iconutil --convert icns --output $(APP)/Contents/Resources/GearShift.icns build/GearShift.iconset
	codesign --force --sign "$(SIGN_IDENTITY)" $(APP)

install: app install-skill
	osascript -e 'quit app "GearShift"' >/dev/null 2>&1 || true
	mkdir -p $(HOME)/Applications
	rm -rf "$(INSTALLED_APP)"
	cp -R $(APP) "$(INSTALLED_APP)"
	@echo "Installed $(INSTALLED_APP) (signed with: $(SIGN_IDENTITY))"

run: install
	open "$(INSTALLED_APP)"

# Builds the ad-hoc signed release zip (other Macs don't have the "GearShift Local" identity) and
# pins the plugin's skill to it: APP_VERSION and APP_SHA256 tell register.sh what to download.
release:
	@plugin_version="$$(plutil -extract version raw -o - $(PLUGIN_JSON))"; \
	if [ "$$plugin_version" != "$(VERSION)" ]; then \
		echo "$(PLUGIN_JSON) is at $$plugin_version but Info.plist at $(VERSION): run make version V=<x.y.z>" >&2; exit 1; \
	fi
	$(MAKE) app SIGN_IDENTITY=-
	codesign --verify --strict $(APP)
	rm -f $(ZIP)
	ditto -c -k --keepParent $(APP) $(ZIP)
	shasum -a 256 $(ZIP) | awk '{print $$1}' > $(SKILL_DIR)/APP_SHA256
	echo "$(VERSION)" > $(SKILL_DIR)/APP_VERSION
	@echo
	@echo "Built $(ZIP) for GearShift $(VERSION) ($$(du -h $(ZIP) | cut -f1 | tr -d ' '), sha256 $$(cat $(SKILL_DIR)/APP_SHA256))."
	@echo "Next:"
	@echo "  1. git add -A && git commit -m 'GearShift $(VERSION)'"
	@echo "  2. git tag v$(VERSION) && git push && git push origin v$(VERSION)"
	@echo "  3. gh release create v$(VERSION) $(ZIP) --title 'GearShift $(VERSION)'"
	@echo "Upload this exact zip: the skill only installs a file with this SHA-256."

# `make version` prints the version; `make version V=2.2.0` sets it in Info.plist and plugin.json
# (plugin updates are keyed on plugin.json's version). Then `make release`.
version:
ifdef V
	@echo "$(V)" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$$' || { echo "V must look like 2.2.0" >&2; exit 1; }
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(V)" Resources/Info.plist
	sed -i '' -E 's/("version"[[:space:]]*:[[:space:]]*")[^"]*"/\1$(V)"/' $(PLUGIN_JSON)
	@echo "Version set to $(V). Run make release next."
else
	@echo "$(VERSION)"
endif

clean:
	rm -rf .build build
