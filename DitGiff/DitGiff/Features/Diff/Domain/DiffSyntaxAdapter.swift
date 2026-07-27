/// Bridges diff hunk lines to the syntax highlighter. Core does not know about
/// Features types, so the mapping lives here.
nonisolated enum DiffSyntaxAdapter {
    /// Parallel to `hunk.lines`: `result[i]` is the syntax spans for `hunk.lines[i]`.
    static func syntaxSpans(for hunk: DiffHunk) -> [[SyntaxSpan]] {
        let language = SyntaxLanguage.detect(path: hunk.filePath)
        let syntaxLines = hunk.lines.map { line in
            SyntaxHunkLine(text: line.text, side: syntaxSide(for: line.kind))
        }
        return SyntaxHunkHighlighter.spans(for: syntaxLines, language: language)
    }

    private static func syntaxSide(for kind: DiffLineKind) -> SyntaxLineSide {
        switch kind {
        case .context: .both
        case .addition: .new
        case .deletion: .old
        }
    }
}
