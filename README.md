# DayNight

A menu-bar utility that fades every Apple display and the MacBook keyboard
backlight between two presets: Day and Night.

- **Click** the icon to switch between Day and Night with a short fade. If the
  brightness was changed by hand, a click goes to the preset farther away.
- **Right-click** (or Control-click) to open the panel: click a preset's name
  to apply it, drag its sliders to adjust it (the active preset updates live),
  and turn Open at Login on or off.

The icon shows a sun for Day, a moon for Night, and a half-filled circle when
the brightness matches neither. A display that connects while Day or Night is
active joins that preset. Keyboard auto-brightness is paused while DayNight
runs and restored when it quits, even after a crash.

Day defaults to 100 % screens and keyboard; Night to 20 % screens and 10 %
keyboard.

## Build

Requires macOS 26 and Xcode 26 or later.

```sh
make test      # unit tests
make app       # .build/DayNight.app, ad-hoc signed
make install   # quit the running copy, install to /Applications, open it
```

`make hardware-check` drives the real displays and keyboard through Day, Night
and recovery, then restores everything.

## Caveat

DayNight uses the private DisplayServices and CoreBrightness frameworks. It is
meant for personal use on Apple Silicon Macs with Apple displays, may break with
a macOS update, and cannot ship on the App Store. See `THIRD_PARTY_NOTICES.md`.
