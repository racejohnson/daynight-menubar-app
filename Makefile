SWIFT := /usr/bin/swift
APP_NAME := DayNight
BUILD_APP := .build/DayNight.app
INSTALL_APP := /Applications/DayNight.app

.PHONY: all test app install clean

all: test app

test:
	$(SWIFT) test

app:
	$(SWIFT) build -c release --product $(APP_NAME)
	/bin/rm -rf "$(BUILD_APP)"
	/bin/mkdir -p "$(BUILD_APP)/Contents/MacOS" "$(BUILD_APP)/Contents/Resources"
	/bin/cp "$$($(SWIFT) build -c release --show-bin-path)/$(APP_NAME)" \
		"$(BUILD_APP)/Contents/MacOS/$(APP_NAME)"
	/bin/cp AppResources/Info.plist "$(BUILD_APP)/Contents/Info.plist"
	/bin/cp THIRD_PARTY_NOTICES.md \
		"$(BUILD_APP)/Contents/Resources/THIRD_PARTY_NOTICES.md"
	/usr/bin/codesign --force --sign - --timestamp=none "$(BUILD_APP)"
	/usr/bin/codesign --verify --deep --strict --verbose=2 "$(BUILD_APP)"

install: app
	/bin/rm -rf "$(INSTALL_APP)"
	/usr/bin/ditto "$(BUILD_APP)" "$(INSTALL_APP)"
	/usr/bin/codesign --verify --deep --strict --verbose=2 "$(INSTALL_APP)"
	/usr/bin/touch "$(INSTALL_APP)"

clean:
	$(SWIFT) package clean
