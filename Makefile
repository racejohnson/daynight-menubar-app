SWIFT := /usr/bin/swift
APP := .build/DayNight.app
INSTALLED := /Applications/DayNight.app

.PHONY: all test app install run hardware-check clean

all: test app

test:
	$(SWIFT) test

app:
	$(SWIFT) build -c release --product DayNight
	/bin/rm -rf "$(APP)"
	/bin/mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	/bin/cp "$$($(SWIFT) build -c release --show-bin-path)/DayNight" "$(APP)/Contents/MacOS/DayNight"
	/bin/cp AppResources/Info.plist "$(APP)/Contents/Info.plist"
	if [ -f AppResources/AppIcon.icns ]; then \
		/bin/cp AppResources/AppIcon.icns "$(APP)/Contents/Resources/AppIcon.icns"; \
	fi
	if [ -f AppResources/Assets.car ]; then \
		/bin/cp AppResources/Assets.car "$(APP)/Contents/Resources/Assets.car"; \
	fi
	/bin/cp THIRD_PARTY_NOTICES.md "$(APP)/Contents/Resources/THIRD_PARTY_NOTICES.md"
	/usr/bin/codesign --force --sign - --timestamp=none "$(APP)"
	/usr/bin/codesign --verify --deep --strict --verbose=2 "$(APP)"

# Quits the running copy through the normal path, so it restores keyboard
# auto-brightness, and waits (up to 5 s) for it to exit before replacing the bundle.
install: app
	-/usr/bin/osascript -e 'if application id "com.racejohnson.DayNight" is running then tell application id "com.racejohnson.DayNight" to quit'
	-@for i in $$(seq 1 50); do /usr/bin/pgrep -xq DayNight || break; /bin/sleep 0.1; done
	/bin/rm -rf "$(INSTALLED)"
	/usr/bin/ditto "$(APP)" "$(INSTALLED)"
	/usr/bin/codesign --verify --deep --strict --verbose=2 "$(INSTALLED)"
	/usr/bin/open "$(INSTALLED)"

run: app
	/usr/bin/open "$(APP)"

hardware-check:
	@echo "This changes the real display and keyboard brightness, then restores it."
	$(SWIFT) run -c release daynight-hardware-check

clean:
	$(SWIFT) package clean
	/bin/rm -rf "$(APP)"
