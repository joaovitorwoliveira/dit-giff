import Testing

@testable import DitGiff

nonisolated struct SyntaxHunkHighlighterTests {

  @Test func removedBlockCommentDoesNotLeakIntoFollowingAddition() {
    let lines = [
      SyntaxHunkLine(text: "func foo() {", side: .both),
      SyntaxHunkLine(text: "    /* unclosed on this side", side: .old),
      SyntaxHunkLine(text: "    let x = 1", side: .new),
      SyntaxHunkLine(text: "       closes here */", side: .old),
      SyntaxHunkLine(text: "}", side: .both),
    ]

    let result = SyntaxHunkHighlighter.spans(for: lines, language: .swift)
    #expect(result.count == lines.count)

    let additionSpans = result[2]
    #expect(additionSpans.contains(SyntaxSpan(start: 4, length: 3, kind: .keyword)))
    #expect(additionSpans.contains(SyntaxSpan(start: 12, length: 1, kind: .number)))
    #expect(!additionSpans.allSatisfy { $0.kind == .comment })
  }

  @Test func addedBlockCommentDoesNotLeakIntoFollowingRemoval() {
    let lines = [
      SyntaxHunkLine(text: "func foo() {", side: .both),
      SyntaxHunkLine(text: "    /* opens on new side", side: .new),
      SyntaxHunkLine(text: "    oldLine()", side: .old),
      SyntaxHunkLine(text: "       closes on new */", side: .new),
      SyntaxHunkLine(text: "}", side: .both),
    ]

    let result = SyntaxHunkHighlighter.spans(for: lines, language: .swift)
    #expect(result.count == lines.count)

    let removalSpans = result[2]
    #expect(removalSpans.contains { $0.kind == .function })
    #expect(!removalSpans.allSatisfy { $0.kind == .comment })
  }

  @Test func blockCommentSpanningContextWithChangesInMiddle() {
    let lines = [
      SyntaxHunkLine(text: "    /* opens on context", side: .both),
      SyntaxHunkLine(text: "    added body", side: .new),
      SyntaxHunkLine(text: "    removed body", side: .old),
      SyntaxHunkLine(text: "    closes on context */", side: .both),
    ]

    let result = SyntaxHunkHighlighter.spans(for: lines, language: .swift)
    #expect(result.count == lines.count)

    #expect(result[1].allSatisfy { $0.kind == .comment })
    #expect(result[2].allSatisfy { $0.kind == .comment })

    let openSpans = result[0]
    #expect(openSpans.contains { $0.kind == .comment })

    let closeSpans = result[3]
    #expect(closeSpans.contains { $0.kind == .comment })
  }

  @Test func outputCountMatchesInputForSampleHunks() {
    let hunks: [[SyntaxHunkLine]] = [
      [
        SyntaxHunkLine(text: "+ only", side: .new),
        SyntaxHunkLine(text: "+ two", side: .new),
      ],
      [
        SyntaxHunkLine(text: "- only", side: .old),
        SyntaxHunkLine(text: "- two", side: .old),
      ],
      [
        SyntaxHunkLine(text: " context", side: .both),
        SyntaxHunkLine(text: " context2", side: .both),
      ],
      [
        SyntaxHunkLine(text: "ctx", side: .both),
        SyntaxHunkLine(text: "-old", side: .old),
        SyntaxHunkLine(text: "+new", side: .new),
        SyntaxHunkLine(text: "ctx2", side: .both),
      ],
    ]

    for hunk in hunks {
      let result = SyntaxHunkHighlighter.spans(for: hunk, language: .swift)
      #expect(result.count == hunk.count)
    }
  }

  @Test func additionsOnlyHunk() {
    let lines = [
      SyntaxHunkLine(text: "let a = 1", side: .new),
      SyntaxHunkLine(text: "let b = 2", side: .new),
    ]

    let result = SyntaxHunkHighlighter.spans(for: lines, language: .swift)
    #expect(result.count == 2)
    #expect(result[0].contains(SyntaxSpan(start: 0, length: 3, kind: .keyword)))
    #expect(result[1].contains(SyntaxSpan(start: 0, length: 3, kind: .keyword)))
  }

  @Test func removalsOnlyHunk() {
    let lines = [
      SyntaxHunkLine(text: "var x = 0", side: .old),
      SyntaxHunkLine(text: "var y = 0", side: .old),
    ]

    let result = SyntaxHunkHighlighter.spans(for: lines, language: .swift)
    #expect(result.count == 2)
    #expect(result[0].contains(SyntaxSpan(start: 0, length: 3, kind: .keyword)))
    #expect(result[1].contains(SyntaxSpan(start: 0, length: 3, kind: .keyword)))
  }

  @Test func contextOnlyHunk() {
    let lines = [
      SyntaxHunkLine(text: "func main() {", side: .both),
      SyntaxHunkLine(text: "    return", side: .both),
      SyntaxHunkLine(text: "}", side: .both),
    ]

    let result = SyntaxHunkHighlighter.spans(for: lines, language: .swift)
    #expect(result.count == 3)
    #expect(result[0].contains(SyntaxSpan(start: 0, length: 4, kind: .keyword)))
    #expect(result[1].contains(SyntaxSpan(start: 4, length: 6, kind: .keyword)))
  }

  @Test func emptyInputReturnsEmptyOutput() {
    let result = SyntaxHunkHighlighter.spans(for: [], language: .swift)
    #expect(result.isEmpty)
  }

  @Test func realisticSwiftHunk() {
    let lines = [
      SyntaxHunkLine(text: "struct User {", side: .both),
      SyntaxHunkLine(text: "    let id: Int", side: .old),
      SyntaxHunkLine(text: "    let id: UUID", side: .new),
      SyntaxHunkLine(text: "    var name: String", side: .both),
      SyntaxHunkLine(text: "}", side: .both),
    ]

    let result = SyntaxHunkHighlighter.spans(for: lines, language: .swift)
    #expect(result.count == lines.count)

    #expect(result[1].contains(SyntaxSpan(start: 4, length: 3, kind: .keyword)))
    #expect(result[1].contains(SyntaxSpan(start: 12, length: 3, kind: .type)))

    #expect(result[2].contains(SyntaxSpan(start: 4, length: 3, kind: .keyword)))
    #expect(result[2].contains(SyntaxSpan(start: 12, length: 4, kind: .type)))

    #expect(result[3].contains(SyntaxSpan(start: 4, length: 3, kind: .keyword)))
    #expect(result[3].contains(SyntaxSpan(start: 14, length: 6, kind: .type)))
  }

  @Test func realisticTypeScriptHunk() {
    let lines = [
      SyntaxHunkLine(text: "export function greet(name: string) {", side: .both),
      SyntaxHunkLine(text: "  return `Hello, ${name}`;", side: .old),
      SyntaxHunkLine(text: "  return `Hi, ${name}!`;", side: .new),
      SyntaxHunkLine(text: "}", side: .both),
    ]

    let result = SyntaxHunkHighlighter.spans(for: lines, language: .typescript)
    #expect(result.count == lines.count)

    #expect(result[0].contains(SyntaxSpan(start: 0, length: 6, kind: .keyword)))
    #expect(result[0].contains(SyntaxSpan(start: 7, length: 8, kind: .keyword)))
    #expect(result[0].contains(SyntaxSpan(start: 28, length: 6, kind: .keyword)))

    #expect(result[1].contains { $0.kind == .string })
    #expect(result[2].contains { $0.kind == .string })
  }
}
