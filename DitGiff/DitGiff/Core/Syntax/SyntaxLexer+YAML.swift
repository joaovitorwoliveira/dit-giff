extension SyntaxLexer {
    static func tokenizeYAML(_ line: String) -> (spans: [SyntaxSpan], next: SyntaxLexerState) {
        var scanner = SyntaxLineScanner(line)
        var spans: [SyntaxSpan] = []
        let state = SyntaxLexerState.start
        var beforeColon = true

        while !scanner.isAtEnd {
            let start = scanner.offset
            guard let char = scanner.current() else { break }

            if char == "#" {
                appendSpan(start: start, length: scanner.count - start, kind: .comment, to: &spans)
                break
            }

            if char == " " || char == "\t" {
                scanner.advance()
                continue
            }

            switch char {
            case "\"":
                let length = scanDoubleQuotedString(from: &scanner)
                appendSpan(start: start, length: length, kind: .string, to: &spans)
                beforeColon = false
            case "'":
                let length = scanSingleQuotedString(from: &scanner)
                appendSpan(start: start, length: length, kind: .string, to: &spans)
                beforeColon = false
            case ":":
                appendSpan(start: start, length: 1, kind: .punctuation, to: &spans)
                scanner.advance()
                beforeColon = false
            default:
                if char.isNumber || (char == "-" && scanner.peek()?.isNumber == true) {
                    let length = scanNumber(from: &scanner)
                    appendSpan(start: start, length: length, kind: .number, to: &spans)
                    beforeColon = false
                } else if isIdentifierStart(char) {
                    let idStart = scanner.offset
                    scanner.consume { isIdentifierPart($0) || $0 == "-" }
                    let id = String(scanner.chars[idStart..<scanner.offset])
                    let kind: SyntaxTokenKind?
                    if SyntaxKeywordSets.yaml.contains(id) {
                        kind = .keyword
                    } else if beforeColon {
                        kind = .type
                    } else {
                        kind = nil
                    }
                    if let kind {
                        appendSpan(start: idStart, length: scanner.offset - idStart, kind: kind, to: &spans)
                    }
                    beforeColon = false
                } else {
                    scanner.advance()
                }
            }

            ensureLexerProgress(scanner: &scanner, iterationStart: start)
        }

        return (spans, state)
    }
}
