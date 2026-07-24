# Forbidden

Hard rules. These are not preferences to weigh against others.

## No AI cliché

- No purple gradient.
- No spark or sparkle icon.
- No little stars.
- No pulsing glow on anything a model produced.

Model output in this product looks like text a careful colleague wrote, not
like a feature demo.

## No color outside the system

- No saturated color beyond the diff green and coral.
- No separate accent hue for selection, focus, or links — see
  [principles.md](./principles.md).
- No neutral gray. Every tone carries the green undertone.

## No heavy shadow

Elevation comes from the surface scale. The one exception is popovers.

## No sharp corners

Everything is rounded. `--radius-sm` / `--radius-md` / `--radius-lg`.

## No emoji in the interface

## Clues, never verdicts

This applies to any surface showing model output. The interface never says
"BUG FOUND" or "this is wrong". It says what an attentive reviewer would
notice, as an observation or a question. The human decides.

Write "`resolvePlan()` used to return nil when it could not find the plan; it
now throws. Three callers in this diff handle the return value, none catch the
exception." — not "Bug: unhandled exception."
