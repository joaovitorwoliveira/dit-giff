import Testing

@testable import DitGiff

nonisolated struct SyntaxLanguageDetectTests {

    @Test func detectsSwiftExtension() {
        #expect(SyntaxLanguage.detect(path: "Sources/App.swift") == .swift)
    }

    @Test func detectsJavaScriptExtensions() {
        #expect(SyntaxLanguage.detect(path: "index.js") == .javascript)
        #expect(SyntaxLanguage.detect(path: "Component.jsx") == .javascript)
    }

    @Test func detectsTypeScriptWithUppercaseExtension() {
        #expect(SyntaxLanguage.detect(path: "src/models/User.TS") == .typescript)
    }

    @Test func detectsPlainWithoutExtension() {
        #expect(SyntaxLanguage.detect(path: "Makefile") == .plain)
        #expect(SyntaxLanguage.detect(path: "folder/README") == .plain)
    }

    @Test func detectsYAMLAndJSON() {
        #expect(SyntaxLanguage.detect(path: "config/settings.yml") == .yaml)
        #expect(SyntaxLanguage.detect(path: "package.json") == .json)
    }
}

nonisolated struct SyntaxLexerInvariantTests {

    private let sampleLines: [(String, SyntaxLanguage)] = [
        ("let x = 42 // answer", .javascript),
        ("func greet() { print(\"hi\") }", .swift),
        ("interface User { name: string }", .typescript),
        ("name: true # enabled", .yaml),
        ("{\"key\": \"value\", \"n\": 1}", .json),
        ("# Heading", .markdown),
        ("export PATH=$HOME/bin", .shell),
        ("<div class=\"box\">", .html),
        ("value = \"plain\"", .plain),
    ]

    /// Lines that historically exposed lexer hangs and overlapping spans.
    private let invariantCorpus: [String] = [
        "\"count\": -1",
        "retries: -1",
        "- item",
        " end */ let x = 1",
        "unclosed \"string",
        "   ",
        "",
        "ação 👋",
        "tab\there",
        "a + b - c * d / e == f != g && h || i ?? j < k > l <= m >= n",
    ]

    @Test func spansAreOrderedNonOverlappingAndInBounds() {
        for (line, language) in sampleLines {
            let result = SyntaxLexer.tokenize(line, language: language, state: .start)
            assertValidSpans(line: line, spans: result.spans)
        }
    }

    @Test func invariantCorpusTerminatesWithValidSpansForEveryLanguage() {
        for language in SyntaxLanguage.allCases {
            for line in invariantCorpus {
                let result = SyntaxLexer.tokenize(line, language: language, state: .start)
                assertValidSpans(line: line, spans: result.spans)
            }
        }
    }

    @Test func emptyAndWhitespaceLinesReturnNoSpans() {
        for language in SyntaxLanguage.allCases {
            let empty = SyntaxLexer.tokenize("", language: language, state: .start)
            #expect(empty.spans.isEmpty)

            let spaces = SyntaxLexer.tokenize("   \t  ", language: language, state: .start)
            #expect(spaces.spans.isEmpty)
        }
    }
}

private func assertValidSpans(line: String, spans: [SyntaxSpan]) {
    let lineLength = line.count
    var previousEnd = 0
    for span in spans {
        #expect(span.start >= previousEnd)
        #expect(span.length > 0)
        #expect(span.start + span.length <= lineLength)
        previousEnd = span.start + span.length
    }
}

nonisolated struct SyntaxLexerSwiftTests {

    @Test func tokenizesRepresentativeLine() {
        let line = "let count = 42 // tally"
        let result = SyntaxLexer.tokenize(line, language: .swift, state: .start)
        #expect(result.spans.contains(SyntaxSpan(start: 0, length: 3, kind: .keyword)))
        #expect(result.spans.contains(SyntaxSpan(start: 12, length: 2, kind: .number)))
        #expect(result.spans.contains(SyntaxSpan(start: 15, length: 8, kind: .comment)))
    }

    @Test func decoratorMainActor() {
        let line = "@MainActor func load() {}"
        let result = SyntaxLexer.tokenize(line, language: .swift, state: .start)
        #expect(result.spans.contains(SyntaxSpan(start: 0, length: 10, kind: .decorator)))
        #expect(result.spans.contains(SyntaxSpan(start: 11, length: 4, kind: .keyword)))
        #expect(result.spans.contains(SyntaxSpan(start: 16, length: 4, kind: .function)))
    }

    @Test func blockCommentAcrossLines() {
        let open = SyntaxLexer.tokenize("/* start", language: .swift, state: .start)
        #expect(open.next.inBlockComment == true, "expected inBlockComment, got \(open.next)")
        #expect(open.spans.contains(SyntaxSpan(start: 0, length: 8, kind: .comment)),
                "open spans: \(open.spans)")

        let close = SyntaxLexer.tokenize(" end */", language: .swift, state: open.next)
        #expect(close.next.inBlockComment == false)
        #expect(close.spans.contains(SyntaxSpan(start: 0, length: 7, kind: .comment)),
                "close spans: \(close.spans)")
    }

    @Test func blockCommentClosingMidLineDoesNotOverlapFollowingTokens() {
        let line = " end */ let x = 1"
        let open = SyntaxLexer.tokenize("/* start", language: .swift, state: .start)
        let result = SyntaxLexer.tokenize(line, language: .swift, state: open.next)

        assertValidSpans(line: line, spans: result.spans)
        #expect(result.spans.contains(SyntaxSpan(start: 0, length: 7, kind: .comment)))
        #expect(result.spans.contains(SyntaxSpan(start: 8, length: 3, kind: .keyword)))
        #expect(result.spans.contains(SyntaxSpan(start: 16, length: 1, kind: .number)))
    }

    @Test func unterminatedStringSetsState() {
        let line = "let s = \"unterminated"
        let result = SyntaxLexer.tokenize(line, language: .swift, state: .start)
        #expect(result.next.openString == .doubleQuote)
        #expect(result.spans.contains { $0.kind == .string })
    }

    @Test func unicodeOffsetsBeforeToken() {
        let line = "ação let x = 1"
        let result = SyntaxLexer.tokenize(line, language: .swift, state: .start)
        #expect(result.spans.contains(SyntaxSpan(start: 5, length: 3, kind: .keyword)))
        #expect(result.spans.contains(SyntaxSpan(start: 13, length: 1, kind: .number)))
    }
}

nonisolated struct SyntaxLexerJavaScriptTests {

    @Test func tokenizesRepresentativeLine() {
        let line = "const msg = 'hi'; // greet"
        let result = SyntaxLexer.tokenize(line, language: .javascript, state: .start)
        #expect(result.spans.contains(SyntaxSpan(start: 0, length: 5, kind: .keyword)))
        #expect(result.spans.contains(SyntaxSpan(start: 12, length: 4, kind: .string)))
        #expect(result.spans.contains(SyntaxSpan(start: 18, length: 8, kind: .comment)))
    }
}

nonisolated struct SyntaxLexerTypeScriptTests {

    @Test func tokenizesRepresentativeLine() {
        let line = "interface User { id: number } // model"
        let result = SyntaxLexer.tokenize(line, language: .typescript, state: .start)
        #expect(result.spans.contains(SyntaxSpan(start: 0, length: 9, kind: .keyword)))
        #expect(result.spans.contains(SyntaxSpan(start: 10, length: 4, kind: .type)))
        #expect(result.spans.contains(SyntaxSpan(start: 21, length: 6, kind: .keyword)))
        #expect(result.spans.contains(SyntaxSpan(start: 30, length: 8, kind: .comment)))
    }

    @Test func decoratorInjectable() {
        let line = "@Injectable() class Service {}"
        let result = SyntaxLexer.tokenize(line, language: .typescript, state: .start)
        #expect(result.spans.contains(SyntaxSpan(start: 0, length: 11, kind: .decorator)))
    }
}

nonisolated struct SyntaxLexerJSONTests {

    @Test func tokenizesRepresentativeLine() {
        let line = "{\"active\": true, \"count\": 3}"
        let result = SyntaxLexer.tokenize(line, language: .json, state: .start)
        #expect(result.spans.contains(SyntaxSpan(start: 1, length: 8, kind: .string)))
        #expect(result.spans.contains(SyntaxSpan(start: 11, length: 4, kind: .keyword)))
        #expect(result.spans.contains(SyntaxSpan(start: 26, length: 1, kind: .number)))
    }

    @Test func negativeNumberIncludesSign() {
        let line = "\"count\": -1"
        let result = SyntaxLexer.tokenize(line, language: .json, state: .start)
        assertValidSpans(line: line, spans: result.spans)
        #expect(result.spans.contains(SyntaxSpan(start: 9, length: 2, kind: .number)))
    }
}

nonisolated struct SyntaxLexerYAMLTests {

    @Test func tokenizesRepresentativeLine() {
        let line = "server: \"localhost\" # dev"
        let result = SyntaxLexer.tokenize(line, language: .yaml, state: .start)
        #expect(result.spans.contains(SyntaxSpan(start: 0, length: 6, kind: .type)))
        #expect(result.spans.contains(SyntaxSpan(start: 8, length: 11, kind: .string)))
        #expect(result.spans.contains(SyntaxSpan(start: 20, length: 5, kind: .comment)))
    }

    @Test func negativeNumberIncludesSign() {
        let line = "retries: -1"
        let result = SyntaxLexer.tokenize(line, language: .yaml, state: .start)
        assertValidSpans(line: line, spans: result.spans)
        #expect(result.spans.contains(SyntaxSpan(start: 9, length: 2, kind: .number)))
    }
}

nonisolated struct SyntaxLexerMarkdownTests {

    @Test func tokenizesRepresentativeLine() {
        let line = "## Title with `code` and [link](https://ex.com)"
        let result = SyntaxLexer.tokenize(line, language: .markdown, state: .start)
        #expect(result.spans.contains(SyntaxSpan(start: 0, length: 2, kind: .keyword)))
        #expect(result.spans.contains(SyntaxSpan(start: 14, length: 6, kind: .string)))
        #expect(result.spans.contains(SyntaxSpan(start: 32, length: 14, kind: .function)))
    }
}

nonisolated struct SyntaxLexerShellTests {

    @Test func tokenizesRepresentativeLine() {
        let line = "export PATH=$HOME/bin # setup"
        let result = SyntaxLexer.tokenize(line, language: .shell, state: .start)
        #expect(result.spans.contains(SyntaxSpan(start: 0, length: 6, kind: .keyword)))
        #expect(result.spans.contains(SyntaxSpan(start: 12, length: 5, kind: .type)))
        #expect(result.spans.contains(SyntaxSpan(start: 22, length: 7, kind: .comment)))
    }
}

nonisolated struct SyntaxLexerHTMLTests {

    @Test func tokenizesRepresentativeLine() {
        let line = "<div id=\"main\"></div> <!-- tail -->"
        let result = SyntaxLexer.tokenize(line, language: .html, state: .start)
        #expect(result.spans.contains(SyntaxSpan(start: 1, length: 3, kind: .keyword)))
        #expect(result.spans.contains(SyntaxSpan(start: 5, length: 2, kind: .type)))
        #expect(result.spans.contains(SyntaxSpan(start: 8, length: 6, kind: .string)))
        #expect(result.spans.contains(SyntaxSpan(start: 22, length: 13, kind: .comment)))
    }
}

nonisolated struct SyntaxLexerPlainTests {

    @Test func tokenizesRepresentativeLine() {
        let line = "count = 10 # tally"
        let result = SyntaxLexer.tokenize(line, language: .plain, state: .start)
        #expect(result.spans.contains(SyntaxSpan(start: 8, length: 2, kind: .number)))
        #expect(result.spans.contains(SyntaxSpan(start: 11, length: 7, kind: .comment)))
    }

    @Test func doesNotTreatURLSlashAsComment() {
        let line = "open https://example.com"
        let result = SyntaxLexer.tokenize(line, language: .plain, state: .start)
        #expect(!result.spans.contains { $0.kind == .comment })
    }

    @Test func emojiOffsetForString() {
        let line = "👋 \"olá\""
        let result = SyntaxLexer.tokenize(line, language: .plain, state: .start)
        #expect(result.spans.contains(SyntaxSpan(start: 2, length: 5, kind: .string)))
    }
}
