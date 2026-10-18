<p align="center"><img src="docs/icon.png" width="128" alt=""></p>

# Mittelklick

Middle click on the trackpad for macOS, inspired by Middle. A menu bar app without windows, network access or accounts. The name is German for "middle click".

## Features

- **Tap with three or four fingers** on the trackpad (built-in or Magic Trackpad) to middle click at the pointer location. Four fingers by default.
- **Fn + left click** as a middle click, dragging included (optional, off by default).
- Menu bar: number of fingers, Fn + click, launch at login, hide icon. A hidden icon comes back when you launch Mittelklick again from the Finder.
- English and German.

Three fingers clash with "Look up & data detectors: Tap with three fingers" and "Three finger drag" in the macOS trackpad settings. Four fingers are free.

## How it works

1. The private `MultitouchSupport.framework` of macOS delivers the raw trackpad contacts frame by frame (`MTDeviceCreateList`, `MTRegisterContactFrameCallbackWithRefcon`, `MTDeviceStart`). Mittelklick loads it at runtime via `dlopen` (see `Sources/MTBridge`).
2. `TapRecognizer` treats it as a tap when exactly the configured number of fingers touch down, barely move (at most 4 % of the surface) and lift off within 0.4 s.
3. If there was a left click (pressing with four fingers instead of tapping) or a key press (palms while typing) within the last half second, nothing happens. Only the time is queried, never which key.
4. `Clicks.middleClick()` creates `otherMouseDown` and `otherMouseUp` with the center button as a `CGEvent` and posts them.
5. For Fn + left click, a `CGEventTap` rewrites left clicks with Fn held into middle clicks.

When a Magic Trackpad connects or disconnects, or the Mac wakes from sleep, Mittelklick rebuilds its device list.

## Permission

Mittelklick needs **Accessibility** access (System Settings › Privacy & Security › Accessibility) to post clicks and rewrite Fn clicks. macOS asks on first launch, otherwise use "Allow Accessibility …" in the menu.

## Privacy

Mittelklick contains no networking code:

```sh
otool -L /Applications/Mittelklick.app/Contents/MacOS/Mittelklick        # no CFNetwork, no Network.framework
nm -u /Applications/Mittelklick.app/Contents/MacOS/Mittelklick | grep -i urlsession   # empty
```

From the trackpad it reads only position and state of the contacts and discards them right away. The `CGEventTap` for Fn + click sees mouse events only, never the keyboard.

## Installation

```sh
brew install --cask wiredframe/tap/mittelklick
```

Or download `Mittelklick-<version>.zip` from [Releases](../../releases), unzip it and drag `Mittelklick.app` to `/Applications`. The app is signed but not notarized. If macOS blocks the first launch, click "Open Anyway" under Privacy & Security or run:

```sh
xattr -dr com.apple.quarantine /Applications/Mittelklick.app
```

If Middle or a similar app with the same gesture is still running, every middle click arrives twice. Quit the other app and turn off its launch at login.

## Troubleshooting

To log every gesture (fingers, duration, result):

```sh
defaults write de.wiredframe.mittelklick debug -bool true   # then relaunch Mittelklick
log stream --predicate 'subsystem == "de.wiredframe.mittelklick"'
defaults delete de.wiredframe.mittelklick debug             # turn it off again
```

## Building

```sh
./build.sh            # builds build/Mittelklick.app (universal)
./build.sh --install  # also copies it to ~/Applications and launches it
./build.sh --zip      # also creates build/Mittelklick-<version>.zip
```

If a "Developer ID Application" certificate is in the keychain, `build.sh` signs with it, otherwise ad hoc. With a stable signature the Accessibility permission survives rebuilds, with an ad hoc signature it has to be granted again after every build.

Requirements: Xcode or Swift 5.10+, macOS 14+.

## License

MIT
