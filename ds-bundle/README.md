# Dit Giff — CSS tokens (legacy)

CSS token bundle from an earlier design iteration. **Not the source of truth for the
app** — canonical values live in `DitGiff/DitGiff/DesignSystem/`.

Kept as a reference for HTML/CSS experiments. Do not edit expecting the SwiftUI app
to pick up changes.

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

Guidelines live in `guidelines/`. Token CSS lives in `tokens/`.
