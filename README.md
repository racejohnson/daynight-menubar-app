# DayNight

DayNight is a native, Dockless macOS menu-bar utility for synchronizing the
normal brightness of Apple displays and a MacBook keyboard.

- Left-click the menu-bar icon to toggle Day/Night immediately.
- Right-click for editable presets, launch-at-login status, explicit Apply
  actions, and Quit.
- Day defaults to 100% screens/100% keyboard.
- Night defaults to 20% screens/10% keyboard.

The app uses private macOS DisplayServices and CoreBrightness APIs. It is
intended for local use on the tested Apple Silicon Mac and is not suitable for
App Store distribution. See `THIRD_PARTY_NOTICES.md`.

## Build

```sh
make test
make app
make install
```

`make install` produces an ad-hoc locally signed app at
`/Applications/DayNight.app`.
