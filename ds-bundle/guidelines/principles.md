# Principles

Two decisions from the icon govern the entire interface.

## No gray is neutral

Every black, gray and white in this interface carries a green undertone. It is
almost imperceptible in isolation, and it is what makes the screen look made by
someone rather than assembled from the framework's default gray.

**If a tone reads as neutral, it is wrong.** Never reach for `#000`, `#fff`,
`#888`, `gray-500`, or any stock neutral. Use `--surface-0..3`,
`--border`, `--border-subtle`, and `--text-primary/secondary/tertiary`.

## The before/after divide

The icon is a field cut in two. The interface may echo that, but sparingly — at
the seam between panels, never as decoration. `.ds-divide` is the one place it
belongs.

## There is no separate accent color

The temptation is to invent a blue or purple accent for selection and focus.
Don't. That would be five hues on a screen that already has two carrying strong
semantic meaning, and the brief is explicit: if everything has color, nothing
does.

| Need | What to use |
| --- | --- |
| Selection | `.ds-selected` — `--surface-3` plus a 2px `--diff-add` rule on the left edge |
| Keyboard focus | `.ds-focus-ring` — 2px ring of `--diff-add` at 40% |
| Link / action | `.ds-link` — `--text-primary` with an underline, not a color |

`--diff-add` works as the action color because in a diff tool green already
means "present, added". That is the same semantic, not a second one.

## Green and coral appear once

`--diff-add` and `--diff-del` in dark mode are exactly the icon's colors. That
repetition is deliberate — it ties the brand to the screen.

Line backgrounds are those same colors at very low alpha
(`--diff-add-bg`, `--diff-del-word`, …), never hues of their own. Do not
introduce a second green or a second red anywhere.
