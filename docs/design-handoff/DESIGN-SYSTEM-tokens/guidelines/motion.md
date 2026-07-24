# Motion

Only what confirms an action moves. There are exactly three animations in this
product.

| Action | Motion | Tokens | Class |
| --- | --- | --- | --- |
| Expand / collapse a group | 160ms, ease-out | `--motion-collapse-duration`, `--motion-collapse-easing` | `.ds-collapse` |
| Mark a hunk as read | 200ms fade to the recessed state | `--motion-read-duration`, `--opacity-read` | `.ds-read` |
| Jump to a hunk | 240ms smooth scroll, then a 600ms highlight flash | `--motion-jump-duration`, `--motion-flash-duration` | `.ds-flash` |

**Nothing else animates.** No parallax. No staggered entrance. No pulsing
skeleton. No hover transitions on things that are not being confirmed.

A read hunk recedes — lower opacity, or collapsed to a one-line summary. It
never disappears.

All motion tokens collapse to `0ms` under `prefers-reduced-motion: reduce`.
