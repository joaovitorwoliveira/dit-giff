# Dit Giff

A native macOS app that turns the diff between a branch and its base into a review
the author can defend. Local, read-only, driving Claude Code headless with the
subscription the machine already has.

The bottleneck it attacks is not writing code — it is reading what the agent wrote
with enough confidence to open the MR. So **the product does not review for you**;
it makes you read and understand faster. Presenting a finding as a verdict rather
than a clue breaks the product's premise.

Stack: Swift / SwiftUI, native macOS.

## Index

| Where | What |
| --- | --- |
| [`docs/product/PRODUCT.md`](docs/product/PRODUCT.md) | Product: problem, value pillars, what is decided, anti-goals. Read before proposing scope. |
| [`docs/product/DESIGN-SYSTEM.md`](docs/product/DESIGN-SYSTEM.md) | **Canonical source** for every color, spacing, type and motion value. |
| [`docs/product/SWIFT-SETUP.md`](docs/product/SWIFT-SETUP.md) | Setup and the technical primitives, written for someone coming from JS. |
| [`docs/design-handoff/`](docs/design-handoff/) | `.dc.html` prototypes and screen spec from Claude Design. Layout reference, not code. |
| [`ds-bundle/`](ds-bundle/) | Tokens as CSS. **Generated** by design-sync. |
| `DitGiff/` | The app. Open `DitGiff.xcodeproj` from here. |
| `assets/icon/` | Icon drawn in code (`render-icon.swift`). |

## Rules that do not bend

**From the design system** — hard rules, not preferences to weigh against others.
Full list in `ds-bundle/guidelines/forbidden.md`:

1. **No neutral gray.** Every tone carries a green undertone. `#fff`, `#000` and
   framework grays are wrong. Use the tokens.
2. **No separate accent hue.** Selection, focus and links all borrow `--diff-add`.
   No blue, no purple. No saturated color beyond the diff green and coral.
3. **Spacing is a closed scale:** 4, 8, 12, 16, 24, 32, 48, nothing between. If a gap
   seems to need another value, the layout is wrong, not the scale.
   (`ds-bundle/guidelines/layout.md`)
4. **No AI cliché.** No purple gradient, no spark icon, no little stars, no pulsing
   glow on anything a model produced.
5. **No heavy shadow** — elevation comes from the surface scale, popovers excepted.
   **No sharp corners. No emoji in the interface.**

Dark is the default mode; light is a full parallel palette. Follow the OS appearance
unless the user pins a mode.

**From the product:**

- **Read-only.** The AI never writes to the user's repository.
- **App Sandbox stays off.** The app runs `git` and `claude` through `Process`, which
  the sandbox blocks. It is a build setting (`ENABLE_APP_SANDBOX = NO`), not an
  `.entitlements` file.
- **Clues, never verdicts.** The interface never says "BUG FOUND". It states what an
  attentive reviewer would notice, as an observation or a question. The human decides.

## Testing

**Every feature ships with tests. No exceptions, and no "I'll add them later".**
A change without tests is not done.

- **Unit tests** (`DitGiffTests/`) use **Swift Testing** — `@Test`, `#expect`,
  `import Testing`. Not XCTest.
- **UI tests** (`DitGiffUITests/`) use **XCTest**, because XCUITest has no Swift
  Testing equivalent yet.
- Favor integration tests over mock-heavy unit tests. What matters is that a real
  diff produces the right result, not that a mock was called.

The one thing that makes this app testable: **everything that shells out — `git` and
`claude` — must sit behind a protocol, never a direct `Process` call from a view or
model.** Tests inject a fake that returns canned output; only a small, deliberately
thin adapter actually spawns a process. Get this seam wrong and the whole app becomes
untestable, because every test would need a real repository and a real Claude call.

Keep a few real `git` fixtures for the integration layer, so the parsing is proven
against actual `git diff` output rather than a hand-written string.

## Traps in this repository

- **`ds-bundle/` is generated.** `.design-sync/config.json` points `outDir` there; the
  next sync overwrites it. To change a token, edit `docs/product/DESIGN-SYSTEM.md` and
  run the sync. Never hand-edit `ds-bundle/`, never move the folder.
- **`docs/design-handoff/support.js` is prototype runtime, not app code.** The
  `.dc.html` files are not for copying either — read them for exact values and
  interaction intent. The `DESIGN-SYSTEM-tokens/` folder inside is a frozen copy of
  `ds-bundle/`; for development use `ds-bundle/`.
- **The PNGs in `assets/icon/` are build artifacts.** Edit the constants at the top of
  `render-icon.swift` and run `./build.sh`. After regenerating, copy the
  `AppIcon.appiconset` into the app's asset catalog.
- **The project uses file system synchronized groups** (`objectVersion = 77`). A folder
  created on disk under `DitGiff/DitGiff/` shows up in Xcode on its own — do not edit
  the `.xcodeproj` to register files.

## Commands

```sh
xcodebuild -project DitGiff/DitGiff.xcodeproj -scheme DitGiff -configuration Debug build
xcodebuild -project DitGiff/DitGiff.xcodeproj -scheme DitGiff test
```

Day to day, `Cmd+R` in Xcode.
