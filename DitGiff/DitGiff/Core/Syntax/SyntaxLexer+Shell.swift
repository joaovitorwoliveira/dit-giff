extension SyntaxLexer {
    static func tokenizeShell(_ line: String) -> (spans: [SyntaxSpan], next: SyntaxLexerState) {
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
            case "\"", "'":
                let length: Int
                if char == "\"" {
                    length = scanDoubleQuotedString(from: &scanner)
                } else {
                    length = scanSingleQuotedString(from: &scanner)
                }
                appendSpan(start: start, length: length, kind: .string, to: &spans)
            case "$":
                let varStart = scanner.offset
                scanner.advance()
                if scanner.current() == "{" {
                    scanner.advance()
                    scanner.consume { $0 != "}" }
                    if scanner.current() == "}" {
                        scanner.advance()
                    }
                } else {
                    scanner.consume { isIdentifierPart($0) }
                }
                appendSpan(start: varStart, length: scanner.offset - varStart, kind: .type, to: &spans)
            default:
                if char.isNumber {
                    let length = scanNumber(from: &scanner)
                    appendSpan(start: start, length: length, kind: .number, to: &spans)
                } else if isIdentifierStart(char) {
                    let idStart = scanner.offset
                    scanner.consume { isIdentifierPart($0) }
                    let id = String(scanner.chars[idStart..<scanner.offset])
                    if SyntaxKeywordSets.shell.contains(id) {
                        appendSpan(start: idStart, length: scanner.offset - idStart, kind: .keyword, to: &spans)
                    } else if scanner.current() == "(" {
                        appendSpan(start: idStart, length: scanner.offset - idStart, kind: .function, to: &spans)
                    } else {
                        // plain identifier
                    }
                } else {
                    scanner.advance()
                }
            }

            ensureLexerProgress(scanner: &scanner, iterationStart: start)
        }

        return (spans, state)
    }
}
