# Keyboard shortcuts

What the app handles from the keyboard, derived from the code. When a key does
nothing, the useful question is almost always: **which surface has focus?**

---

## Focus: the rule that explains almost everything

Single-letter shortcuts (`n`, `v`), tree navigation (left / right arrows), folder
navigation (`⇧` + arrows), and reader paging (`Space`, up / down, `Page Up` /
`Page Down`) only fire when the reader's `ScrollView` is first responder. That
lives in `DiffViewer` via `.focusable()` + `.focused(isFocused)` + `.onKeyPress`
(`DitGiff/DitGiff/Features/Diff/Views/Reader/DiffViewer.swift`).

Reader `FocusState` lives in the shell (`DiffView`), not inside the viewer
(`DitGiff/DitGiff/Features/Diff/Views/DiffView.swift`). The sidebar filter and
chat composer have their own `FocusState`. Typing in them never reaches the reader
handler.

### What gives focus to the reader

| Action | Where |
| --- | --- |
| Click a file in the sidebar tree | `onFileRevealed` → `isReaderFocused = true` (`DiffView.swift`; click in `DiffSidebarFileRow.swift`) |
| Tap the reader column | `isFocused.wrappedValue = true` (`DiffViewer.swift`) |
| Dismiss reading-progress error banner | `isReaderFocused = true` (`DiffView.swift`) |

### What steals focus from the reader

- Click the sidebar **filter**: the `TextField` takes focus (`DiffSidebar.swift`).
  Letters go into the filter.
- Click the chat **composer**: the `TextEditor` takes focus (`DiffChatPanel.swift`).
  Letters go into the draft.
- Click **Ask something specific…** in the selection popover: the `TextField` takes
  focus (`DiffSelectionPopover.swift`).
- Controls with `dsFocusable` (top bar buttons, Welcome buttons) can become first
  responder via Tab; while one of them has focus, the reader does not get keys.

The reader error-banner dismiss button refuses focus on purpose (`.focusable(false)`
in `DiffView.swift`) so clicking it does not steal first responder from the
`ScrollView`.

### What the code does not do automatically

`isReaderFocused` starts `false`. There is no `onAppear` / `defaultFocus` that
puts focus on the reader when the diff opens. Without one of the gestures above,
`→` / `←` / `⇧↓` / `n` / `v` / `Space` have no active handler — that is not a
keyboard bug. With the reader focused and no line under the cursor, `→` and `⇧↓`
treat the cursor as "before the start" and go to the first visible line / first
folder (the reader does not focus anything on its own when the diff opens).

---

## Diff reader

Surface: center column (`DiffViewer`), with the `ScrollView` focused.

### Cursor model: one tree line

The keyboard cursor is **not** "a file". It is **one line of the tree** — file
**or** folder — in sidebar draw order, top to bottom (`DiffTreeVisibleLines`).

**Visible** is the keyword: descendants of a **collapsed** folder are not in the
sequence. Closing a folder means "done with this"; `→` / `←` / `⇧↑` / `⇧↓`
**respect** that and skip hidden items. Those keys **never** reopen a folder
automatically.

- Cursor on a **file**: the reader scrolls to it.
- Cursor on a **folder**: the reader **does not** move. Reach folder content by
  continuing through the tree.

`focusedFilePath` holds the line path (file, or folder with trailing `/`). The
sidebar highlights that line with `surfaceSelected` — file or folder.

### Lateral navigation (arrows, no modifier)

Holding `→` / `←` **repeats** (walks lines). Each repeat changes target; when the
target is a file, snap scrolls without animation
(`DiffReaderFileScrollStyle.rapid`) so scrolls do not stack. `n` and `v` do **not**
repeat.

| Key | Action | When | Not when | Code |
| --- | --- | --- | --- | --- |
| `→` | Next **visible** tree line (folder or file; no wrap at end); key-repeat; **does not** open folders | Reader focused; no other modifiers | Filter, composer, or other first responder; `⌘` / `⌥` / `⌃` + arrow | `DiffViewer` → `DiffReaderKeyPressPipeline` → `goToNextFile`; `DiffTreeVisibleLines`; `DiffKeyboardNavigationResolver.nextLine`; `DiffModel+Keyboard` |
| `←` | Previous visible line (no wrap at start); same | Same | Same | Same with `goToPreviousFile` / `previousLine` |
| `n` | Next **unread file** (reader order), with wrap; **may** open collapsed folders to reveal target; stays put if all read | Reader focused; **no** key-repeat | Same; `.repeat` phase ignored | `goToNextUnreadFile` + `ensureAncestorDirectoriesOpen` |
| `v` | File: toggle "viewed". Folder: toggle **all** descendants and **close** / reopen folder (viewed → close; unmark → open) | Reader focused; **no** key-repeat | Same; no cursor: model no-op, key still `.handled` | `toggleViewedOnFocusedFile` |

### Folders (Shift + arrows)

Key repeat does **not** fire on these shortcuts. Bare `⇧` is allowed in the
pipeline.

| Key | Action | When | Not when | Code |
| --- | --- | --- | --- | --- |
| `⇧↓` | Next **folder** in visible order; cursor on folder line; reader does not scroll; does not open folder | Reader focused; Shift only | No next folder (no-op) | `goToNextFolder` |
| `⇧↑` | Previous folder; cursor on folder line | Same | No previous folder | `goToPreviousFolder` |
| `⇧→` | Open folder under cursor; if cursor is on a file, open parent folder | Reader focused; Shift only; folder under/above cursor | Root; folder already open (no-op) | `openFocusedFolder` |
| `⇧←` | Close folder under cursor (or parent of file); if cursor would be hidden, move cursor to folder line | Same | Root; folder already closed (no-op) | `closeFocusedFolder` |

`j` and `k` do nothing in the reader. Modified letters (e.g. `⇧n`, `⌘v`) fall
through as `.ignored`.

Unmodified lateral arrows do **not** go through `DiffReaderScrollKeyMapping` — they
are tree-line navigation. With Shift, all four arrows are folder chords, never
scroll.

### Scrolling within a file

Not native system scroll. `.focusable()` installs a `KeyViewProxy` as first
responder, so AppKit does **not** page the `ScrollView` on its own; the app applies
a discrete jump via `scrollPosition.scrollTo(y:)` (`DiffViewer.swift`).

Page step is `0.9 ×` viewport height. Up/down arrows:

- single press: `5 × DiffViewerMetric.codeLineHeight` (`arrowLineStepCount`)
- key-repeat (hold): `3 ×` same height (`arrowLineRepeatStepCount`)

(`DiffReaderKeyboardScroll.swift`; `DiffViewer.swift`).

| Key | Action | When | Notes | Code |
| --- | --- | --- | --- | --- |
| `Space` | Page down | Reader focused; Shift optional as only modifier | `⌘` / `⌥` / `⌃` + Space: mapping rejects | `DiffViewer.swift`; `DiffReaderKeyboardScroll.swift` |
| `⇧Space` | Page up | Reader focused | Same | Same |
| `Page Down` | Page down | Reader focused, no Shift | With Shift: mapping returns `nil` | Same |
| `Page Up` | Page up | Reader focused, no Shift | With Shift: `nil` | Same |
| `↓` | Five lines down on tap; three per repeat when held | Reader focused, no Shift | With Shift: folder nav (`⇧↓`), not scroll | Same |
| `↑` | Five lines up on tap; three per repeat when held | Reader focused, no Shift | With Shift: folder nav (`⇧↑`), not scroll | Same |

No inertia, trackpad rubber-banding, or animation on this path — a new offset is
computed and applied. `Home` / `End` are not in the scroll mapping `switch`; the
handler returns `.ignored`.

---

## Sidebar (change map)

### Filter

The "Filter files…" `TextField` has `@FocusState` and a focus ring
(`DiffSidebar.swift`). No `onKeyPress`, `onSubmit`, or dedicated shortcut: typing
filters via binding; Enter has no special action.

While the filter is focused, reader shortcuts do **not** run.

### Tree

Clicking a file calls `revealFileInReader` and returns focus to the reader
(`DiffSidebarFileRow.swift`). No dedicated keyboard handling on the tree — reader
arrows move the line cursor, and the sidebar scrolls to keep that line visible.

---

## Chat

Surface: `DiffChatPanel`, visible when `model.isChatOpen`.

| Key | Action | When | Notes | Code |
| --- | --- | --- | --- | --- |
| `Return` | Send composer draft | Composer (`TextEditor`) focused and `isEnabled` (`model.canUseSampleAgent`) | Disabled composer: `Return` is **consumed** (`.handled`) without sending | `DiffChatPanel.swift` |
| `⇧Return` | New line in draft | Composer focused | Handler returns `.ignored` for `TextEditor` to insert break | `DiffChatPanel.swift` |
| `Escape` (`onExitCommand`) | Close chat (`closeChat`) | Registered on whole panel | — | `DiffChatPanel.swift`; `DiffModel+Chat.swift` |

No keyboard shortcut in code to **open** chat; opening goes through model actions
(send, ask/explain selection, etc.).

While the composer is focused, reader `→` / `←` / `n` / `v` / `Space` do not fire.

---

## Selection popover

Appears over the hunk when there is a selection and an agent
(`DiffHunkBlock.swift`).

| Key | Action | When | Code |
| --- | --- | --- | --- |
| `Return` (`onSubmit` on `TextField`) | Send selection question (`askAboutSelection`) and clear field | "Ask something specific…" focused (and line enabled by `canAskAboutSelection`) | `DiffSelectionPopover.swift` |

No `onKeyPress` on the popover. No keyboard shortcut for "Explain selection" — button only.

---

## Welcome

The goal editor is a `TextEditor` with `@FocusState` for the focus ring only
(`WelcomeView.swift`). No `onKeyPress` / `onSubmit` / shortcut to "Open diff" from
the editor.

Buttons with `dsFocusable` (including "Open diff") can be activated by default
macOS focused-button behavior (`Space` / `Return` when the button is first
responder). That is `dsFocusable` in `DSModifiers.swift` + `WelcomeView.swift` —
not an app-registered `keyboardShortcut`.

---

## Diff top bar

Sidebar toggle, branch pill (back), and theme toggle use `dsFocusable`
(`DiffTopBar.swift`). No `keyboardShortcut`. They respond only when focused (button
behavior), not as global shortcuts.

---

## What does not exist

Confirmed in code:

1. **No menu bar with app shortcuts.** `DitGiffApp` only declares `WindowGroup` +
   `.windowStyle(.hiddenTitleBar)`. No `.commands`, `CommandGroup`, or
   `keyboardShortcut` / `KeyEquivalent` on the app target.

2. **Reader keyboard scroll is discrete paging**, not native inertial scroll. See
   reader section and comment in `DiffViewer.swift`.

3. **No** global shortcut to open/close sidebar, open chat, return to Welcome,
   toggle theme, or mark hunk read — only what the tables above list.

4. **No** `NSEvent` monitor (`addLocalMonitor` / `addGlobalMonitor`) in the app.

---

## Notes (consumed keys with no visible effect)

- With reader focused: `→` on last visible line, `←` on first, `n` with everything
  read, `⇧↓` / `⇧↑` with no adjacent folder, `⇧→` / `⇧←` on no-op (root / already
  open / already closed), and `v` with no cursor still return `.handled` — the key
  is swallowed even when the model moves nothing.
- Disabled composer: `Return` is `.handled` without sending.
- `⇧Page Down` / `⇧Page Up` on reader: mapping returns `nil`, handler returns
  `.ignored` — no paging. `⇧↓` / `⇧↑` / `⇧←` / `⇧→` are folder shortcuts, not scroll.
- Focus on a `dsFocusable` top-bar button (via Tab, for example) takes the reader
  off the shortcut path; `Space` in that state tends to activate the button, not
  page the diff.
