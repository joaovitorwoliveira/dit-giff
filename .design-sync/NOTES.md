# design-sync notes

## This repo has no component library

As of 2026-07-23 dit-giff contains only product docs and icon assets — no
`package.json`, no build, no `dist/`, no Storybook. The `/design-sync`
converter, which bundles a repo's compiled components, does not apply.

`"shape": "tokens-only"` records that. It is not one of the converter's two
shapes (`storybook` / `package`) and no converter script runs. `ds-bundle/` is
hand-authored from `docs/product/DESIGN-SYSTEM.md`, which stays the source of
truth.

There is deliberately no `pkg` key in config.json. A future `/design-sync` will
therefore treat the repo as a first-time sync — correct, because once real
components exist they need a real first import, not an incremental diff against
a tokens-only project.

## No `_ds_sync.json` is uploaded

The sync anchor's hashes describe component render output, of which there is
none. Omitting it is the honest choice: the next sync re-verifies everything
rather than trusting an anchor that vouches for nothing.

## What to redo when components land

1. Build the component library so it emits a `dist/`.
2. Re-run `/design-sync`. It will detect `package` (or `storybook`) shape and
   run the real converter.
3. Keep `.design-sync/conventions.md` — it is human-authored and still true.
   Re-validate its class and token names against the new build rather than
   rewriting it.
4. The converter will produce `components/**`, `_ds_bundle.js` and previews,
   replacing this tokens-only upload.

## Derived values worth knowing

The alpha diff fills in `tokens/color.css` are computed from the spec's
percentages, not eyeballed:

- dark `--diff-add-bg` = `#8FBF8A` at 9% = `rgba(143, 191, 138, 0.09)`
- dark `--diff-del-bg` = `#F07A64` at 9% = `rgba(240, 122, 100, 0.09)`
- light `--diff-add-bg` = `#3F7238` at 8%, light `--diff-del-bg` = `#B8412A` at 8%
- word-level fills are 22% (dark) and 18% (light)

`--shadow-popover` and `--opacity-read` are the two values NOT in the source
doc. The doc states popovers carry the interface's only shadow and that read
hunks recede, but gives no numbers; these were chosen to fit and should be
confirmed against the SwiftUI implementation.
