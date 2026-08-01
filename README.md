# Dit Giff

A native macOS app for reading the diff between a branch and its base — locally,
read-only, with optional AI help from the Claude Code subscription already on
your machine.

The bottleneck in agent-driven work is no longer writing code; it is reading what
the agent wrote with enough confidence to open the merge request. Dit Giff does
not review for you. It organizes the change, keeps navigation fast, and surfaces
clues (not verdicts) when you ask.

## Requirements

- macOS with Xcode (Mac App Store). No package manager, no API key.
- First launch of Xcode may ask for the license and extra components. Only the
  macOS platform is needed.

## Run

Open `DitGiff/DitGiff.xcodeproj` in Xcode and press `Cmd+R`.

```sh
# build
xcodebuild -project DitGiff/DitGiff.xcodeproj -scheme DitGiff -configuration Debug build

# test
xcodebuild -project DitGiff/DitGiff.xcodeproj -scheme DitGiff test
```

## Layout

```
DitGiff/                  The app. Open DitGiff.xcodeproj from here.
DitGiff/DitGiff/DesignSystem/   Colors, type, spacing, motion (source of truth).
docs/product/             Product notes and design principles.
assets/icon/              App icon, drawn in code.
```

## Regenerate the app icon

The PNGs are build artifacts. Edit the constants at the top of `render-icon.swift`,
then rebuild and copy the icon set into the app's asset catalog:

```sh
./assets/icon/build.sh
cp assets/icon/AppIcon.appiconset/* DitGiff/DitGiff/Assets.xcassets/AppIcon.appiconset/
```

## Where to read next

- [`AGENTS.md`](AGENTS.md) — conventions, testing rules, and repo traps.
- [`docs/product/PRODUCT.md`](docs/product/PRODUCT.md) — what the product is and why.
- [`docs/shortcuts.md`](docs/shortcuts.md) — keyboard shortcuts by surface and focus.
