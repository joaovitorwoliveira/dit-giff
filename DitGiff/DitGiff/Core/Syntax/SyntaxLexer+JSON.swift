extension SyntaxLexer {
    static func tokenizeJSON(_ line: String) -> (spans: [SyntaxSpan], next: SyntaxLexerState) {
        var scanner = SyntaxLineScanner(line)
        var spans: [SyntaxSpan] = []
        var state = SyntaxLexerState.start

        while !scanner.isAtEnd {
            let start = scanner.offset
            guard let char = scanner.current() else { break }

            switch char {
            case "\"":
                let length = scanDoubleQuotedString(from: &scanner)
                appendSpan(start: start, length: length, kind: .string, to: &spans)
            case "{", "}", "[", "]", ",", ":":
                appendSpan(start: start, length: 1, kind: .punctuation, to: &spans)
                scanner.advance()
            case "0"..."9":
                let length = scanNumber(from: &scanner)
                appendSpan(start: start, length: length, kind: .number, to: &spans)
            case "-":
                if scanner.peek()?.isNumber == true {
                    let length = scanNumber(from: &scanner)
                    appendSpan(start: start, length: length, kind: .number, to: &spans)
                } else {
                    scanner.advance()
                }
            default:
                if isIdentifierStart(char) {
                    let idStart = scanner.offset
                    scanner.consume { isIdentifierPart($0) }
                    let id = String(scanner.chars[idStart..<scanner.offset])
                    if SyntaxKeywordSets.json.contains(id) {
                        appendSpan(start: idStart, length: scanner.offset - idStart, kind: .keyword, to: &spans)
                    } else {
                        scanner.index = idStart + 1
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
