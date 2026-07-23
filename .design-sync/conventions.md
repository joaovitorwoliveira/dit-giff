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
