# Layout, density and elevation

## The spacing scale is closed

4px base. Use `4 8 12 16 24 32 48` and nothing else — `--space-4` through
`--space-48`. If a gap seems to need a value outside this list, the layout is
wrong, not the scale.

## Density

High but breathable. Reading 3000 lines comfortably matters more than
impressing on the first screen.

| Measure | Token | Value |
| --- | --- | --- |
| List row height | `--row-height` | 28px |
| Panel inner padding | `--panel-padding` | 12px |
| Diff gutter width | `--diff-gutter-width` | 44px |

Helper classes: `.ds-row`, `.ds-panel`, `.ds-gutter`.

## Radius

Soft corners on everything, echoing the rounded ends of the icon. No sharp
corners anywhere.

| Token | Value | Use |
| --- | --- | --- |
| `--radius-sm` | 6px | badges, chips, counters |
| `--radius-md` | 10px | hunk blocks, clue cards |
| `--radius-lg` | 14px | popovers, floating panels |

## Elevation by surface, not by shadow

Lift something by moving it up the surface scale (`--surface-1` →
`--surface-2` → `--surface-3`), not by adding a shadow. The single shadow in
this interface belongs to popovers: `.ds-popover` / `--shadow-popover`.

## It is a native macOS app, not a web app

This changes concrete decisions:

- Translucent sidebar on the left, unified toolbar at the top holding the
  branch controls.
- No browser navigation bar, no site breadcrumb, no footer.
- Light and dark both genuinely working — not an inverted filter.

## The destination constrains the design

This design gets reimplemented in SwiftUI. Prefer structures that map directly
onto `NavigationSplitView`, `List`, `ScrollView` and `HSplitView`.

Avoid anything that only exists in CSS — complex grid areas, stacked
`backdrop-filter`, nested sticky positioning. **If a visual detail would be
hard to reproduce natively, choose the simpler version.**
