extension SyntaxLexer {
    static func tokenizePlain(_ line: String) -> (spans: [SyntaxSpan], next: SyntaxLexerState) {
        var scanner = SyntaxLineScanner(line)
        var spans: [SyntaxSpan] = []
        let state = SyntaxLexerState.start

        while !scanner.isAtEnd {
            let start = scanner.offset
            guard let char = scanner.current() else { break }

            switch char {
            case "#":
                let length = scanner.count - start
                appendSpan(start: start, length: length, kind: .comment, to: &spans)
                return (spans, state)
            case "/":
                if scanner.peek() == "/", !isURLSchemeSlash(at: scanner.offset, in: scanner.chars) {
                    let length = scanner.count - start
                    appendSpan(start: start, length: length, kind: .comment, to: &spans)
                    return (spans, state)
                }
                scanner.advance()
            case "\"":
                let length = scanDoubleQuotedString(from: &scanner)
                appendSpan(start: start, length: length, kind: .string, to: &spans)
            case "'":
                let length = scanSingleQuotedString(from: &scanner)
                appendSpan(start: start, length: length, kind: .string, to: &spans)
            default:
                if char.isNumber {
                    let length = scanNumber(from: &scanner)
                    appendSpan(start: start, length: length, kind: .number, to: &spans)
                } else {
                    scanner.advance()
                }
            }

            ensureLexerProgress(scanner: &scanner, iterationStart: start)
        }

        return (spans, state)
    }

    /// `://` in `https://` must not start a line comment.
    static func isURLSchemeSlash(at offset: Int, in chars: [Character]) -> Bool {
        guard offset > 0, offset + 1 < chars.count else { return false }
        return chars[offset - 1] == ":" && chars[offset + 1] == "/"
    }
}
