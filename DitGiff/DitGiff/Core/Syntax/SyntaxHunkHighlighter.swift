nonisolated enum SyntaxLineSide: Equatable, Sendable {
    case old
    case new
    case both
}

nonisolated struct SyntaxHunkLine: Equatable, Sendable {
    let text: String
    let side: SyntaxLineSide
}

nonisolated enum SyntaxHunkHighlighter {
    /// Returns a parallel array: `result[i]` is the spans for `lines[i]`.
    static func spans(
        for lines: [SyntaxHunkLine],
        language: SyntaxLanguage
    ) -> [[SyntaxSpan]] {
        guard !lines.isEmpty else { return [] }

        let oldSpans = lexFlow(lines: lines, language: language, flow: .old)
        let newSpans = lexFlow(lines: lines, language: language, flow: .new)

        return lines.indices.map { index in
            switch lines[index].side {
            case .old:
                return oldSpans[index]
            case .new, .both:
                // Context lines ride the new-side flow: post-change file state is what
                // the reader is trying to understand, so ties go to the new stream.
                return newSpans[index]
            }
        }
    }

    private enum Flow {
        case old
        case new
    }

    private static func lexFlow(
        lines: [SyntaxHunkLine],
        language: SyntaxLanguage,
        flow: Flow
    ) -> [[SyntaxSpan]] {
        var result = Array(repeating: [SyntaxSpan](), count: lines.count)
        var state = SyntaxLexerState.start

        for index in lines.indices {
            guard includes(lines[index].side, in: flow) else { continue }

            let tokenized = SyntaxLexer.tokenize(
                lines[index].text,
                language: language,
                state: state
            )
            result[index] = tokenized.spans
            state = tokenized.next
        }

        return result
    }

    private static func includes(_ side: SyntaxLineSide, in flow: Flow) -> Bool {
        switch flow {
        case .old:
            return side == .old || side == .both
        case .new:
            return side == .new || side == .both
        }
    }
}
