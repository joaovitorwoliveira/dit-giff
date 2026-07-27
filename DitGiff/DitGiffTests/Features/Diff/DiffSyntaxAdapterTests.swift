import Testing

@testable import DitGiff

nonisolated struct DiffSyntaxAdapterTests {

    @Test func outputCountMatchesHunkLinesForSeveralHunks() {
        let hunks: [DiffHunk] = [
            diffSyntaxTestHunk(
                path: "a.swift",
                lines: [
                    diffSyntaxTestLine(kind: .addition, text: "let a = 1"),
                    diffSyntaxTestLine(kind: .addition, text: "let b = 2"),
                ]
            ),
            diffSyntaxTestHunk(
                path: "b.swift",
                lines: [
                    diffSyntaxTestLine(kind: .deletion, text: "var x = 0"),
                    diffSyntaxTestLine(kind: .deletion, text: "var y = 0"),
                ]
            ),
            diffSyntaxTestHunk(
                path: "c.swift",
                lines: [
                    diffSyntaxTestLine(kind: .context, text: " context"),
                    diffSyntaxTestLine(kind: .context, text: " context2"),
                ]
            ),
            diffSyntaxTestHunk(
                path: "d.swift",
                lines: [
                    diffSyntaxTestLine(kind: .context, text: "ctx"),
                    diffSyntaxTestLine(kind: .deletion, text: "-old"),
                    diffSyntaxTestLine(kind: .addition, text: "+new"),
                    diffSyntaxTestLine(kind: .context, text: "ctx2"),
                ]
            ),
        ]

        for hunk in hunks {
            let result = DiffSyntaxAdapter.syntaxSpans(for: hunk)
            #expect(result.count == hunk.lines.count)
        }
    }

    @Test func removedBlockCommentDoesNotLeakIntoFollowingAddition() {
        let hunk = diffSyntaxTestHunk(
            path: "Leak.swift",
            lines: [
                diffSyntaxTestLine(kind: .context, text: "func foo() {"),
                diffSyntaxTestLine(kind: .deletion, text: "    /* unclosed on this side"),
                diffSyntaxTestLine(kind: .addition, text: "    let x = 1"),
                diffSyntaxTestLine(kind: .deletion, text: "       closes here */"),
                diffSyntaxTestLine(kind: .context, text: "}"),
            ]
        )

        let result = DiffSyntaxAdapter.syntaxSpans(for: hunk)
        #expect(result.count == hunk.lines.count)

        let additionSpans = result[2]
        #expect(additionSpans.contains(SyntaxSpan(start: 4, length: 3, kind: .keyword)))
        #expect(additionSpans.contains(SyntaxSpan(start: 12, length: 1, kind: .number)))
        #expect(!additionSpans.allSatisfy { $0.kind == SyntaxTokenKind.comment })
    }

    @Test func languageComesFromHunkFilePath() {
        let swiftText = "export function greet(name: string) {"
        let swiftHunk = diffSyntaxTestHunk(
            path: "greet.swift",
            lines: [diffSyntaxTestLine(kind: .context, text: swiftText)]
        )
        let tsHunk = diffSyntaxTestHunk(
            path: "greet.ts",
            lines: [diffSyntaxTestLine(kind: .context, text: swiftText)]
        )

        let swiftSpans = DiffSyntaxAdapter.syntaxSpans(for: swiftHunk)[0]
        let tsSpans = DiffSyntaxAdapter.syntaxSpans(for: tsHunk)[0]

        #expect(!swiftSpans.contains(SyntaxSpan(start: 0, length: 6, kind: .keyword)))
        #expect(tsSpans.contains(SyntaxSpan(start: 0, length: 6, kind: .keyword)))
        #expect(tsSpans.contains(SyntaxSpan(start: 7, length: 8, kind: .keyword)))
    }

    @Test func emptyHunkReturnsEmptySpansWithoutCrashing() {
        let hunk = diffSyntaxTestHunk(path: "empty.swift", lines: [])
        let result = DiffSyntaxAdapter.syntaxSpans(for: hunk)
        #expect(result.isEmpty)
    }

    @Test func unknownExtensionStillColorsStringAndNumber() {
        let hunk = diffSyntaxTestHunk(
            path: "data.unknown",
            lines: [diffSyntaxTestLine(kind: .context, text: "value = \"hello\" 42")]
        )

        let spans = DiffSyntaxAdapter.syntaxSpans(for: hunk)[0]
        #expect(spans.contains { $0.kind == SyntaxTokenKind.string })
        #expect(spans.contains { $0.kind == SyntaxTokenKind.number })
    }
}

private func diffSyntaxTestHunk(path: String, lines: [DiffLine]) -> DiffHunk {
    DiffHunk(
        id: "\(path)#0",
        filePath: path,
        header: "@@",
        location: "\(path):1",
        note: nil,
        explanation: nil,
        reply: nil,
        lines: lines
    )
}

private func diffSyntaxTestLine(kind: DiffLineKind, text: String) -> DiffLine {
    DiffLine(
        oldNumber: 1,
        newNumber: 1,
        kind: kind,
        segments: [DiffLineSegment(text: text)]
    )
}
