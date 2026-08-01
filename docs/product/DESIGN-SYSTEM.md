# Dit Giff — design system

Written rules for the interface. **Canonical token values live in**
`DitGiff/DitGiff/DesignSystem/` (`DSColor.swift`, `DSType.swift`, `DSSpace.swift`,
`DSMotion.swift`). When this document and the Swift disagree, trust the Swift.

## What runs through everything

**Long-reading tool.** Comfort and regularity beat spectacle. Code line height is
fixed at 18px; do not tighten it to save vertical space.

**Diff colors carry meaning.** Green and coral mark add/remove. They are not reused
as a generic accent. Selection uses `surfaceSelected` plus a 2px `diffAdd` rule on
the left; keyboard focus uses a 2px ring in muted `textSecondary`, not diff green.

**Syntax is the exception.** Highlighting may use extra hues; nowhere else in the
chrome does.

**Elevation by surface, not shadow.** The only shadow is on popovers.

## Color

Dark mode is the default. Light mode follows a Solarized Light base (cream surfaces,
muted text). Dark mode uses neutral charcoal surfaces with bright diff green
(`#3DDC5E`) and coral (`#FF5744`).

`textError` is dusty rose / wine — red enough to notice, but not the coral of
`diffDel`. Error and deletion must stay distinguishable on the same screen.

Diff line fills are the diff colors at low alpha, never separate hex values. Word-
level fills use higher alpha on the same hues.

Row hover (`surfaceHover`) and keyboard reading cursor (`surfaceSelected`) are
stronger steps than `surface3` so they read at a glance on list rows.

See `DSColor.swift` for the full palette tables.

## Typography

| Role | Face | Size / leading | Weight |
| --- | --- | --- | --- |
| Panel title | SF Pro Text | 13 / 18 | Semibold |
| Body | SF Pro Text | 13 / 18 | Regular |
| Label | SF Pro Text | 11 / 15 | Medium |
| Code | JetBrains Mono (fallback: SF Mono) | 12 / 18 | Regular |
| Line number | JetBrains Mono (fallback: SF Mono) | 11 / 18 | Regular |

Five roles, no more. Diff metrics use fixed sizes — Dynamic Type would break gutter
alignment.

## Spacing, radius, density

Base unit: 4px. Closed scale: `4 8 12 16 24 32 48` (`DSSpace`).

| Radius | Value | Use |
| --- | --- | --- |
| `sm` | 6px | Badges, chips |
| `md` | 10px | Hunk blocks, cards |
| `lg` | 14px | Popovers, floating panels |

Density: list row height 28px, panel padding 12px, diff gutter 44px wide
(`DSDensity`).

## Motion

Only four motions exist (`DSMotion`). Nothing else animates.

| Motion | Duration | Easing | Use |
| --- | --- | --- | --- |
| Collapse | 160ms | ease-out | Expand/collapse groups |
| Read | 200ms | ease-in-out | Mark hunk as read (fade to receded) |
| Jump | 240ms | ease-in-out | Scroll to hunk |
| Flash | 600ms | ease-in-out | Highlight flash after jump |

Respects Reduce Motion (`animation(reduceMotion:)` returns `nil`).

## Forbidden

No AI clichés: purple gradients, sparkle icons, pulsing glow on model output. No
heavy shadows. No emoji in the interface. No saturated accent outside diff semantics
and syntax — except `textError`, which is rose on purpose.
