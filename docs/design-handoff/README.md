# Handoff: Dit Giff — native macOS diff reader

## Overview
Dit Giff is a **native macOS app** for reading the full diff between a branch and
its base *before* opening the merge request. It is a long-reading tool: comfort
over spectacle. The user picks a repo + branch pair, then reads the change file
by file, marking files as viewed, and can ask an AI to explain any file or any
selected span of lines in a per-diff chat.

This bundle contains the **design prototype** built in HTML plus this spec.

## About the design files
The `.html` files in this bundle are **design references created in HTML** —
prototypes showing the intended look and behavior. They are **not production
code to copy**. The task is to **recreate these designs in the target codebase**
— this is a native macOS app, so the natural target is **SwiftUI** (AppKit where
SwiftUI can't reach, e.g. the code text view). Follow the existing codebase's
patterns; use the HTML only to read exact layout, color, type, spacing, and
interaction intent.

The prototype is a Design Component (`.dc.html`) and won't run as a plain page —
open it in the design tool, or just read the markup/logic. `support.js` is the
prototype runtime, **not** app code — ignore it for implementation.

## Fidelity
**High-fidelity.** Final colors, typography, spacing, and interactions are all
intended as shown. Recreate pixel-accurately using SwiftUI, pulling values from
the design tokens (below). The one thing that is *illustrative* rather than final
is the diff **content** (BillingGuard.swift etc.) and the AI reply text — those
are sample data.

## Design system — source of truth
This design is built on the **Dit Giff design system**, which is spec-derived
from `docs/product/DESIGN-SYSTEM.md` in the `dit-giff` repo. **That file is the
canonical source for every color, spacing, type, and motion value** — reference
it directly rather than hardcoding. The token values are reproduced in the
"Design tokens" section below for convenience.

Three non-negotiable rules from the system:
1. **No neutral gray.** Every surface/text tone carries a green undertone.
   `#fff`, `#000`, and framework grays are wrong — use the tokens.
2. **No separate accent hue.** Selection, focus, and links all borrow
   `--diff-add` (green). No blue, no purple.
3. **Spacing is a closed scale**: 4, 8, 12, 16, 24, 32, 48. Nothing between.

Dark is the default mode; light mode is a full parallel palette. Follow the OS
appearance unless the user pins a mode.

---

## Screens / views

### 1. Welcome (repo + branch picker)
**Purpose:** choose which repository and which branch-vs-base to read, optionally
give a one-line goal or attach a `.md` spec, then open the diff.

**Layout:** centered card, 460px wide, on `--surface-0`. Card is `--surface-1`
with `--border` and `--radius-lg`, `--shadow-popover`. macOS traffic-light dots
(non-functional decoration) top-left. Vertical stack, `--space-16` gaps, padded
`--space-16 --space-24 --space-24`.

**Two states inside the card:**
- **No repo picked:** title "Dit Giff" + subtitle "Read the change before you
  open the MR."; a "Recent repositories" list (`--surface-2` rows, folder glyph,
  name + path + current branch), an "Open repository…" button, and "or drop a
  folder here" (the card is a drag-drop target).
- **Repo picked:** selected repo row with a "Change" link; a **Branches** row —
  compare `<select>` (flex:1) → arrow → base `<select>` (120px fixed); an
  optional change-count line; a goal `<textarea>` (2 rows, auto-grow, max 180px)
  with an "Attach a .md spec" affordance that becomes a removable file chip; a
  helper line + primary **Open diff** button (disabled until a compare branch is
  chosen — shown at `opacity` when disabled).

### 2. Diff view (main screen)
The working screen. Three regions under a top bar.

**Top bar** — `--surface-1`, height 52px, bottom border `--border-subtle`,
horizontal padding `--space-16`, items gap `--space-16`:
- macOS traffic-light dots (decoration).
- Sidebar toggle button (panel icon).
- Dit Giff logo (small, `currentColor`, the 3-rect "d" mark) — flex:0.
- **Center:** the **branch pill doubling as a Back button** — `--surface-3`,
  `--radius-sm`, `--border`, code font. Contains a **back-arrow icon** on the
  left (divider to its right), then `feature/annual-billing → main`. Clicking it
  returns to the Welcome screen to switch branch/repo. Hover tints the border to
  `--diff-add`. (It reads as "go back", NOT a dropdown — this was deliberate.)
- **Right:** `NN files` label, the `+3242 −347` stat (the **+ is
  `--diff-add`, the − is `--diff-del`**; rest of bar is neutral tone), and the
  **theme toggle** (sun in light / moon in dark).

**Left sidebar (file tree)** — `--surface-1`, resizable, toggle-collapsible:
- A filter text input at top.
- The file tree: each file row shows a **document-glyph icon with a status
  symbol inside it** colored by status — `+` add (`--diff-add`), `−` delete
  (`--diff-del`), `±` modified, `→` rename — the file name, and a truncated path.
- Files can be grouped/expanded. Rows show a **viewed** state (dimmed via
  `--opacity-read` / `.ds-read`).

**Center (diff viewer)** — scrolls; `centerRef` is the scroll container:
- Per file: a **sticky header** (`--surface-1`, `--border-subtle`, `--radius-md`,
  height 48px, padding `0 --space-12 0 --space-8`) with the file name/path on the
  left and, on the right: an **"explain this file" button** (document-with-person
  glyph, ~19px, opens the chat with the file explained) and a **Viewed button**
  (checkbox that fills when viewed + the word "Viewed", ~13px). There is **only
  one** explain affordance per file — an earlier duplicate list-icon and a
  separate eye icon were both removed.
- The code itself: two-column grid `var(--diff-gutter-width) 1fr` — line number
  (`.ds-line-number`) then code (`.ds-code`, `--font-code`). Added lines get
  `.ds-diff-add-line` + `.ds-diff-add`, deleted `.ds-diff-del-line` +
  `.ds-diff-del`; intra-line word changes wrap in `.ds-diff-add-word` /
  `.ds-diff-del-word`. Syntax highlighting: GitHub-style in light, Cursor
  "Midnight"-style in dark (token classes `sx-*`).
- Marking a file viewed also collapses it.

**Selection popover** — select code lines and a popover anchors above the
selection (`position:fixed`, `--surface-2`, `--border`, `--radius-md`,
`--shadow-popover`, 280px). Layout, top → bottom:
1. **"Explain selection"** button — single line, list icon + label.
2. divider.
3. a **text input** ("Ask something specific…") + a **send arrow** button.
4. the **file:line reference** (e.g. `BillingGuard.swift:202–204` / "3 lines")
   on its own line at the bottom, tertiary text.
Pressing the quick button or the send arrow opens the chat with the selection
chip attached to the user message.

**Right panel (AI chat)** — a single **per-diff chat** (one context-wide thread,
NOT a persistent sidebar), opened on demand by the explain actions; Esc closes
it. Bubbles indicate sender by side: **assistant** left-aligned on `--surface-2`,
**user** right-aligned on `--surface-3` with a little tail. A user message that
came from a file/selection shows a **rounded location chip above the bubble**
(e.g. `BillingGuard.swift:202–204`). While generating, a **thinking indicator**
cycles a braille spinner + words ("Thinking", "Reading the hunk", "Tracing call
sites", "Weighing the trade-off"). Footer has two `<select>`s: **model**
(Fable / Opus 5 / Sonnet / Haiku) and **reasoning effort** (Low / Medium /
High / Max), plus the input.

---

## Interactions & behavior
- **Open diff:** Welcome → Diff view. Button disabled until a compare branch is
  chosen.
- **Back / switch branch:** the center branch pill → back to Welcome, resetting
  read/viewed/chat state.
- **Sidebar toggle:** show/hide the file tree.
- **Filter:** live-filters the file tree by name/path.
- **Mark viewed:** per-file Viewed button toggles viewed + collapses the file;
  viewed files dim (`--opacity-read`). Sidebar row reflects the same state.
- **Explain file:** header explain button → opens chat, seeds an explanation of
  that file.
- **Select + explain:** mouse-up over code with a non-empty selection shows the
  popover; "Explain selection" or typing a question + send opens the chat with
  the `file:lineRange` chip attached. Selection clears on outside mousedown.
- **Chat:** pick model + reasoning effort, type, send. Thinking indicator, then
  an assistant bubble. Thread scrolls to bottom on new messages.
- **Theme toggle:** switches `data-theme` between dark/light (sun/moon icon).
- **Escape:** closes the chat panel.

### Animations (the only three in the system — see `guidelines/motion.md`)
- **Collapse** (`.ds-collapse`) — file collapse/expand.
- **Read fade** (`.ds-read`) — file dims to `--opacity-read` when viewed.
- **Flash** (`.ds-flash`) — brief highlight (e.g. jumping to a referenced line).
All use the `--motion-*` durations and must respect reduced-motion.

## State management
Per the prototype's logic class, the app needs at minimum:
- `screen`: welcome | diff (plus the sample scenarios all-read / no-notes).
- `theme`: dark | light | follow-OS.
- `repo`, `compareBranch`, `baseBranch`, optional `goal` text, optional `spec`
  file — welcome inputs.
- `viewed`: per-file bool; `collapsed`: per-file bool (viewed implies collapsed).
- `filter`: sidebar filter string; `sidebarOpen`: bool.
- `selection`: `{ file, startLine, endLine }` or null → drives the popover.
- `chat`: `{ open, messages:[{role, text, loc?}], thinking, model, effort }`.
- `read`: per-file read tracking for the dim state.

Data fetching (real app): enumerate branches for the repo; compute the diff
(compare…base) → files with hunks, line-level and word-level change spans;
stream AI replies for explain/ask, sending the selected model + effort and the
file/selection context.

## Design tokens
From `docs/product/DESIGN-SYSTEM.md` (canonical). Dark is default.

### Color
| Token | Dark | Light |
| --- | --- | --- |
| `--surface-0` | `#0B120F` | `#F2F5F3` |
| `--surface-1` | `#0F1714` | `#FAFCFB` |
| `--surface-2` | `#141D19` | `#FFFFFF` |
| `--surface-3` | `#1A2420` | `#EDF2EF` |
| `--border-subtle` | `#1E2A25` | `#E2E9E5` |
| `--border` | `#2A3832` | `#D3DDD8` |
| `--text-primary` | `#E4EDE8` | `#101815` |
| `--text-secondary` | `#9CAEA5` | `#4F5F58` |
| `--text-tertiary` | `#66776F` | `#7C8B84` |
| `--diff-add` | `#8FBF8A` | `#3F7238` |
| `--diff-del` | `#F07A64` | `#B8412A` |

- **Line fills** `--diff-add-bg` / `--diff-del-bg`: the add/del colors at ~9%
  (dark) / ~8% (light).
- **Word fills** `--diff-add-word` / `--diff-del-word`: ~22% (dark) / ~18%
  (light). Never separate hues.
- **Focus / selection / links** all use `--diff-add`.
- macOS traffic-light dots (welcome + top bar decoration): `#FF5F57` `#FEBC2E`
  `#28C840` — these are literal macOS chrome, exempt from the no-gray/no-accent
  rule.

Note: the prototype nudged the *diff* green/red slightly more vivid than the
raw token table for on-screen punch; treat the token values above as the base
and the vivid diff as an acceptable in-context variation. Confirm against
`DESIGN-SYSTEM.md` when implementing.

### Type
- `--font-ui`: system UI stack (SwiftUI default / San Francisco).
- `--font-code`: monospace (prototype uses JetBrains Mono; SF Mono is the
  natural native substitute).
- Roles: `.ds-panel-title`, `.ds-body`, `.ds-label`, `.ds-code`,
  `.ds-line-number`.

### Spacing / shape / density
- Spacing scale (closed): `--space-4 8 12 16 24 32 48`.
- Radius: `--radius-sm | md | lg`.
- Density: `--row-height`, `--panel-padding`, `--diff-gutter-width`.
- Read: `--opacity-read`. Motion: the `--motion-*` set.

## Assets
- **Dit Giff logo** — the 3-rectangle "d" mark, drawn inline as SVG with
  `fill:currentColor` (see the top bar in the HTML). No external file.
- **Icons** — all inline SVG stroke icons (folder, panel, explain
  document-person, checkbox, back arrow, send arrow, spec/link, sun/moon,
  status +/−/±/→). No icon font, no image files. Recreate with SF Symbols where
  a close match exists, or ship the SVG paths.
- No raster images.

## Files
- `Dit Giff v2.dc.html` — the current, canonical prototype (welcome + diff view,
  chat, selection popover, both themes). **Implement from this one.**
- `Dit Giff.dc.html` — earlier version, kept for history only.
- `support.js` — prototype runtime helper; **not** application code.
- `DESIGN-SYSTEM-tokens/` — the token CSS + guideline docs copied from the bound
  design system, so token values and the principles/forbidden rules travel with
  this bundle.
