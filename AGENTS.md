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
| [`docs/product/SWIFT-SETUP.md`](docs/product/SWIFT-SETUP.md) | Setup and the technical primitives, written for someone coming from JS. |
| `DitGiff/DitGiff/DesignSystem/` | The design system in Swift. Every color, spacing, type and motion value lives here. |
| `DitGiff/` | The app. Open `DitGiff.xcodeproj` from here. |
| `assets/icon/` | Icon drawn in code (`render-icon.swift`). |

Design rules are deliberately not in this file. Take them from the design system in
`DesignSystem/`, which is where the values are enforced; a `DESIGN.md` will hold the
written rules.

## Rules that do not bend

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
- **There is no UI test target.** XCUITest drives the app through the accessibility
  APIs, which takes over the whole screen while it runs. If one is ever added, it uses
  XCTest, and `xcodebuild test` gets `-only-testing:DitGiffTests` by default.
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

- **`ds-bundle/` is generated** by design-sync, which overwrites it wholesale. Never
  hand-edit it, never move the folder.
- **`docs/design-handoff/` holds prototypes, not code.** `support.js` is the prototype's
  own runtime and the `.dc.html` files are references to read, never to copy.
- **The PNGs in `assets/icon/` are build artifacts.** Edit the constants at the top of
  `render-icon.swift` and run `./build.sh`. After regenerating, copy the
  `AppIcon.appiconset` into the app's asset catalog.
- **The project uses file system synchronized groups** (`objectVersion = 77`). Swift files
  and asset catalogs created on disk under `DitGiff/DitGiff/` join the target on their
  own, so they never need a project edit. **Other resources do not** — a `.ttf` or a
  `.json` dropped in a folder is simply ignored, and building succeeds while the file is
  missing from the bundle at runtime. Those need a real entry in the `.xcodeproj`; see the
  `Fonts` group for the shape of one.

## Commands

```sh
xcodebuild -project DitGiff/DitGiff.xcodeproj -scheme DitGiff -configuration Debug build
xcodebuild -project DitGiff/DitGiff.xcodeproj -scheme DitGiff test
```

Day to day, `Cmd+R` in Xcode.
