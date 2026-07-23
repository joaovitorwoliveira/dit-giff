# Dit Giff — how to build with this system

Dit Giff is a **native macOS app** for reading the diff between a branch and its
base. Long-reading tool: comfort over spectacle.

**This system ships tokens and a class vocabulary, not components.** There is no
compiled component library — build structure yourself out of the classes below.
Never invent a class name; if a need is not covered here, compose it from the CSS
variables.

## Setup

Link `styles.css` — everything else arrives through its `@import` closure. No
provider, no JS, no font loading (system fonts only).

Dark is the default mode. Set `data-theme` on the root element to pin a mode;
leave it off to follow the OS.

```html
<html data-theme="light">   <!-- or "dark", or omit -->
```

## Styling idiom

Utility classes on `ds-` prefix, reading CSS variables. Both are public — use
classes for the common case, `var(--*)` directly for layout glue.

| Family | Classes |
| --- | --- |
| Surface | `.ds-surface-0` `.ds-surface-1` `.ds-surface-2` `.ds-surface-3` |
| Edges | `.ds-border` `.ds-border-subtle` `.ds-divide` |
| Text color | `.ds-text-primary` `.ds-text-secondary` `.ds-text-tertiary` |
| Type role | `.ds-panel-title` `.ds-body` `.ds-label` `.ds-code` `.ds-line-number` |
| Diff | `.ds-diff-add` `.ds-diff-del` `.ds-diff-add-line` `.ds-diff-del-line` `.ds-diff-add-word` `.ds-diff-del-word` |
| Shape | `.ds-radius-sm` `.ds-radius-md` `.ds-radius-lg` |
| Density | `.ds-row` `.ds-panel` `.ds-gutter` |
| Interaction | `.ds-selected` `.ds-focus-ring` `.ds-link` |
| Elevation | `.ds-popover` |
| Motion | `.ds-collapse` `.ds-read` `.ds-flash` |

Variables: `--surface-0..3`, `--border`, `--border-subtle`,
`--text-primary/secondary/tertiary`, `--diff-add`, `--diff-del`,
`--diff-add-bg`, `--diff-del-bg`, `--diff-add-word`, `--diff-del-word`,
`--focus-ring`, `--shadow-popover`, `--font-ui`, `--font-code`,
`--space-4|8|12|16|24|32|48`, `--radius-sm|md|lg`, `--row-height`,
`--panel-padding`, `--diff-gutter-width`, `--opacity-read`, and the
`--motion-*` set.

## Three rules that are easy to break

1. **No neutral gray.** Every tone carries a green undertone. `#fff`, `#000`,
   `gray-500` and framework defaults are all wrong — use the surface and text
   tokens.
2. **No separate accent hue.** Selection, focus and links all borrow
   `--diff-add`. Do not add blue or purple.
3. **Spacing is a closed scale** — `4 8 12 16 24 32 48`, nothing between.

## Where the truth lives

- `styles.css` and `tokens/*.css` — every value, with its intent in comments.
- `guidelines/principles.md` — why no gray is neutral, why there is no accent.
- `guidelines/layout.md` — density, elevation, and the SwiftUI constraint.
- `guidelines/motion.md` — the only three animations that exist.
- `guidelines/forbidden.md` — hard rules. Read before adding any flourish.

## Idiomatic snippet

```html
<section class="ds-surface-2 ds-border-subtle ds-radius-md"
         style="overflow:hidden">
  <header class="ds-row ds-label" style="padding:0 var(--space-12)">
    BillingGuard.swift
  </header>

  <div class="ds-code" style="display:grid;grid-template-columns:var(--diff-gutter-width) 1fr">
    <span class="ds-line-number" style="padding-right:var(--space-8)">142</span>
    <span class="ds-diff-del-line ds-diff-del">- guard used >= limit else {</span>

    <span class="ds-line-number" style="padding-right:var(--space-8)">142</span>
    <span class="ds-diff-add-line ds-diff-add">+ guard used <span class="ds-diff-add-word">></span> limit else {</span>
  </div>
</section>
```

Layout glue is inline `var(--*)`; everything carrying design meaning is a class.

---

# What is in this project

Generated from `docs/product/DESIGN-SYSTEM.md` in the dit-giff repo, which
remains the source of truth. This project is a **spec-derived** design system:
tokens and conventions, no compiled components.

## Files

| Path | Holds |
| --- | --- |
| `styles.css` | Entry point. Imports every token file, then defines the class vocabulary. |
| `tokens/color.css` | Surfaces, text, diff, focus, shadow — dark and light. |
| `tokens/typography.css` | Two font stacks, five type roles. |
| `tokens/space.css` | 4px scale, radius, density measures. |
| `tokens/motion.css` | Durations for the three animations, plus reduced-motion. |
| `guidelines/principles.md` | The green undertone, the before/after divide, why there is no accent hue. |
| `guidelines/layout.md` | Spacing scale, density, elevation, the SwiftUI constraint. |
| `guidelines/motion.md` | The only three animations in the product. |
| `guidelines/forbidden.md` | Hard rules — read before adding any flourish. |

## Color reference

Dark is the default mode.

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

Line fills (`--diff-add-bg`, `--diff-del-bg`) are those same colors at 9% in
dark and 8% in light. Word-level fills (`--diff-add-word`, `--diff-del-word`)
are 22% and 18%. They are never separate hues.

## No components yet

There is no component library in the dit-giff repo — no `package.json`, no
build. When one exists, re-running `/design-sync` will replace this
tokens-only project with the real compiled components.
