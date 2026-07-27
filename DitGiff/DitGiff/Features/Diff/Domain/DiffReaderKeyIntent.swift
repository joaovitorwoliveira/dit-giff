/// Every reader keyboard shortcut, as a single dispatch the view can switch on.
/// `nil` from the mapping means "not our shortcut — leave it to the system".
nonisolated enum DiffReaderKeyIntent: Equatable, Sendable {
    case nextFile
    case previousFile
    case nextFolder
    case previousFolder
    case openFocusedFolder
    case closeFocusedFolder
    case nextUnreadFile
    case toggleViewed
    case scroll(DiffReaderScrollIntent)

    /// Hold-to-scan files is intentional for bare ←/→. Folder jumps, `n`, and `v`
    /// still refuse repeat — holding those would sweep the tree or mark everything
    /// viewed. In-file scroll always allows repeat.
    var allowsKeyRepeat: Bool {
        switch self {
        case .nextFile, .previousFile, .scroll:
            return true
        case .nextFolder, .previousFolder, .openFocusedFolder, .closeFocusedFolder,
            .nextUnreadFile, .toggleViewed:
            return false
        }
    }
}

/// Runs a reader intent against named actions. Kept pure so tests catch a flipped
/// switch arm without mounting `DiffViewer`.
nonisolated enum DiffReaderKeyIntentDispatch {
    struct Actions {
        var goToNextFile: () -> Void
        var goToPreviousFile: () -> Void
        var goToNextFolder: () -> Void
        var goToPreviousFolder: () -> Void
        var openFocusedFolder: () -> Void
        var closeFocusedFolder: () -> Void
        var goToNextUnreadFile: () -> Void
        var toggleViewed: () -> Void
        var scroll: (DiffReaderScrollIntent) -> Void
    }

    static func perform(_ intent: DiffReaderKeyIntent, actions: Actions) {
        switch intent {
        case .nextFile:
            actions.goToNextFile()
        case .previousFile:
            actions.goToPreviousFile()
        case .nextFolder:
            actions.goToNextFolder()
        case .previousFolder:
            actions.goToPreviousFolder()
        case .openFocusedFolder:
            actions.openFocusedFolder()
        case .closeFocusedFolder:
            actions.closeFocusedFolder()
        case .nextUnreadFile:
            actions.goToNextUnreadFile()
        case .toggleViewed:
            actions.toggleViewed()
        case .scroll(let scroll):
            actions.scroll(scroll)
        }
    }
}

/// Hardware / character key for reader shortcuts, without SwiftUI types so tests can
/// drive the same decision `DiffViewer.handleKeyPress` uses.
nonisolated struct DiffReaderKeyEvent: Equatable, Sendable {
    enum Key: Equatable, Sendable {
        case leftArrow
        case rightArrow
        case upArrow
        case downArrow
        case space
        case pageUp
        case pageDown
        case character(String)
    }

    var key: Key
    var modifiers: DiffReaderKeyModifiers
}

nonisolated struct DiffReaderKeyModifiers: Equatable, Sendable {
    var shift: Bool = false
    var command: Bool = false
    var option: Bool = false
    var control: Bool = false

    /// Cmd / Option / Control always belong to the system, never to reader shortcuts.
    /// Shift alone must NOT block — that was the Bug A regression: a viewer-level
    /// `modifiers.isEmpty` guard discarded Shift+↑/↓ before mapping ran.
    var blocksReaderShortcut: Bool { command || option || control }

    /// True when the reader may own this chord (Shift allowed; ⌘/⌥/⌃ never).
    var allowsReaderShortcut: Bool { !blocksReaderShortcut }
}

/// The exact decision `DiffViewer.handleKeyPress` makes after bridging `KeyPress`.
/// Kept pure so a reintroduced empty-modifiers guard cannot hide behind green
/// mapping-only tests.
nonisolated enum DiffReaderKeyPressPipeline {
    static func intent(
        for event: DiffReaderKeyEvent,
        isRepeat: Bool
    ) -> DiffReaderKeyIntent? {
        // Shift is intentional for folder chords — never require modifiers.isEmpty.
        guard event.modifiers.allowsReaderShortcut else { return nil }
        guard let intent = DiffReaderKeyIntentMapping.intent(for: event) else { return nil }
        guard !isRepeat || intent.allowsKeyRepeat else { return nil }
        return intent
    }
}

/// Single place that turns a key + modifiers into a reader intent. The viewer is a thin
/// dispatch over this; tests prove wiring here so they cannot stay green if ←/→ flip.
nonisolated enum DiffReaderKeyIntentMapping {
    static func intent(for event: DiffReaderKeyEvent) -> DiffReaderKeyIntent? {
        if event.modifiers.blocksReaderShortcut { return nil }

        switch event.key {
        case .leftArrow:
            // Shift is the only arrow modifier the reader owns — folder close, not
            // previous-file. Bare ← stays file navigation.
            if event.modifiers.shift { return .closeFocusedFolder }
            return .previousFile
        case .rightArrow:
            if event.modifiers.shift { return .openFocusedFolder }
            return .nextFile
        case .upArrow:
            // Intercept Shift before scroll mapping so Shift+↑ never becomes line-up.
            if event.modifiers.shift { return .previousFolder }
            return scrollIntent(kind: .upArrow, shift: false)
        case .downArrow:
            if event.modifiers.shift { return .nextFolder }
            return scrollIntent(kind: .downArrow, shift: false)
        case .space:
            return scrollIntent(kind: .space, shift: event.modifiers.shift)
        case .pageUp:
            return scrollIntent(kind: .pageUp, shift: event.modifiers.shift)
        case .pageDown:
            return scrollIntent(kind: .pageDown, shift: event.modifiers.shift)
        case .character(let character):
            // Letters only fire with no modifiers (shift would change the character
            // and is rejected here the same way the old viewer guard did).
            guard !event.modifiers.shift else { return nil }
            switch DiffReaderLetterKeyMapping.action(for: character) {
            case .nextUnreadFile: return .nextUnreadFile
            case .toggleViewed: return .toggleViewed
            case nil: return nil
            }
        }
    }

    private static func scrollIntent(
        kind: DiffReaderScrollKeyEvent.Kind,
        shift: Bool
    ) -> DiffReaderKeyIntent? {
        DiffReaderScrollKeyMapping.intent(
            for: DiffReaderScrollKeyEvent(kind: kind, shift: shift)
        )
        .map { .scroll($0) }
    }
}
