extension SyntaxLexer {
    static func tokenizeHTML(
        _ line: String,
        state incoming: SyntaxLexerState
    ) -> (spans: [SyntaxSpan], next: SyntaxLexerState) {
        var scanner = SyntaxLineScanner(line)
        var spans: [SyntaxSpan] = []
        var state = incoming
        var inTag = false

        if state.inBlockComment {
            if let end = findHTMLCommentEnd(in: scanner.chars, from: 0) {
                appendSpan(start: 0, length: end, kind: .comment, to: &spans)
                scanner.index = end
                state.inBlockComment = false
            } else {
                appendSpan(start: 0, length: scanner.count, kind: .comment, to: &spans)
                return (spans, state)
            }
        }

        while !scanner.isAtEnd {
            let start = scanner.offset
            guard let char = scanner.current() else { break }

            if char == "<", scanner.peek() == "!" {
                if scanner.peek(2) == "-", scanner.peek(3) == "-" {
                    let commentStart = start
                    scanner.advance(4)
                    if let relEnd = findHTMLCommentEnd(in: scanner.chars, from: scanner.offset) {
                        appendSpan(start: commentStart, length: relEnd - commentStart, kind: .comment, to: &spans)
                        scanner.index = relEnd
                    } else {
                        appendSpan(start: commentStart, length: scanner.count - commentStart, kind: .comment, to: &spans)
                        state.inBlockComment = true
                        return (spans, state)
                    }
                    inTag = false
                    continue
                }
            }

            if char == "<" {
                scanner.advance()
                if scanner.current() == "/" {
                    scanner.advance()
                }
                inTag = true
                let tagStart = scanner.offset
                scanner.consume { $0.isLetter || $0.isNumber || $0 == "-" }
                if scanner.offset > tagStart {
                    appendSpan(start: tagStart, length: scanner.offset - tagStart, kind: .keyword, to: &spans)
                }
                continue
            }

            if char == ">" {
                scanner.advance()
                inTag = false
                continue
            }

            if char == "\"" || char == "'" {
                let length: Int
                if char == "\"" {
                    length = scanDoubleQuotedString(from: &scanner)
                } else {
                    length = scanSingleQuotedString(from: &scanner)
                }
                appendSpan(start: start, length: length, kind: .string, to: &spans)
                continue
            }

            if inTag, isIdentifierStart(char) {
                let idStart = scanner.offset
                scanner.consume { isIdentifierPart($0) || $0 == "-" }
                let kind: SyntaxTokenKind = scanner.current() == "=" ? .type : .keyword
                appendSpan(start: idStart, length: scanner.offset - idStart, kind: kind, to: &spans)
                continue
            }

            scanner.advance()
            ensureLexerProgress(scanner: &scanner, iterationStart: start)
        }

        return (spans, state)
    }

    static func findHTMLCommentEnd(in chars: [Character], from start: Int) -> Int? {
        var index = start
        while index + 2 < chars.count {
            if chars[index] == "-", chars[index + 1] == "-", chars[index + 2] == ">" {
                return index + 3
            }
            index += 1
        }
        return nil
    }
}
