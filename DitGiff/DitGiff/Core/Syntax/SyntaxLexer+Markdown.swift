extension SyntaxLexer {
    static func tokenizeMarkdown(_ line: String) -> (spans: [SyntaxSpan], next: SyntaxLexerState) {
        var scanner = SyntaxLineScanner(line)
        var spans: [SyntaxSpan] = []
        let state = SyntaxLexerState.start

        if let first = scanner.current(), first == "#" {
            let headingStart = scanner.offset
            while scanner.current() == "#" {
                scanner.advance()
            }
            if scanner.current() == " " || scanner.isAtEnd {
                appendSpan(
                    start: headingStart,
                    length: scanner.offset - headingStart,
                    kind: .keyword,
                    to: &spans
                )
            } else {
                scanner.index = headingStart
            }
        }

        while !scanner.isAtEnd {
            let start = scanner.offset
            guard let char = scanner.current() else { break }

            if char == "`" {
                let length = scanBacktickSpan(from: &scanner)
                appendSpan(start: start, length: length, kind: .string, to: &spans)
            } else if char == "(", start > 0, scanner.chars[start - 1] == "]" {
                scanner.advance()
                let urlStart = scanner.offset
                while let current = scanner.current(), current != ")" {
                    scanner.advance()
                }
                let urlLength = scanner.offset - urlStart
                if urlLength > 0 {
                    appendSpan(start: urlStart, length: urlLength, kind: .function, to: &spans)
                }
            } else {
                scanner.advance()
            }

            ensureLexerProgress(scanner: &scanner, iterationStart: start)
        }

        return (spans, state)
    }

    static func scanBacktickSpan(from scanner: inout SyntaxLineScanner) -> Int {
        let start = scanner.offset
        scanner.advance()
        while let char = scanner.current() {
            if char == "`" {
                scanner.advance()
                return scanner.offset - start
            }
            scanner.advance()
        }
        return scanner.offset - start
    }
}
