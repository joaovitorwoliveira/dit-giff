/// Scanner shared by Swift, JavaScript, and TypeScript. Language differences live
/// entirely in `SyntaxRules`; this file never switches on `SyntaxLanguage`.
nonisolated enum CFamilySyntaxLexer {

    static func tokenize(
        _ line: String,
        rules: SyntaxRules,
        state incoming: SyntaxLexerState
    ) -> (spans: [SyntaxSpan], next: SyntaxLexerState) {
        var scanner = SyntaxLineScanner(line)
        var spans: [SyntaxSpan] = []
        var state = incoming

        if state.inBlockComment {
            if let end = consumeBlockCommentTail(from: &scanner) {
                SyntaxLexer.appendSpan(start: 0, length: end, kind: .comment, to: &spans)
                scanner.index = end
                state.inBlockComment = false
            } else {
                SyntaxLexer.appendSpan(start: 0, length: scanner.count, kind: .comment, to: &spans)
                return (spans, state)
            }
        }

        if let delimiter = state.openString {
            let consumed = consumeOpenString(delimiter: delimiter, from: &scanner)
            SyntaxLexer.appendSpan(start: 0, length: consumed.length, kind: .string, to: &spans)
            state.openString = consumed.stillOpen ? delimiter : nil
            if consumed.stillOpen {
                return (spans, state)
            }
        }

        while !scanner.isAtEnd {
            let start = scanner.offset
            guard let char = scanner.current() else { break }

            if char == "/" {
                if scanner.peek() == "/" {
                    let length = scanner.count - start
                    SyntaxLexer.appendSpan(start: start, length: length, kind: .comment, to: &spans)
                    return (spans, state)
                }
                if scanner.peek() == "*" {
                    let commentStart = start
                    scanner.advance(2)
                    if let relEnd = findBlockCommentEnd(in: scanner.chars, from: scanner.offset) {
                        let length = relEnd - commentStart
                        SyntaxLexer.appendSpan(start: commentStart, length: length, kind: .comment, to: &spans)
                        scanner.index = relEnd
                    } else {
                        let length = scanner.count - commentStart
                        SyntaxLexer.appendSpan(start: commentStart, length: length, kind: .comment, to: &spans)
                        state.inBlockComment = true
                        return (spans, state)
                    }
                    continue
                }
            }

            if rules.supportsDecorators, char == "@" {
                let decoratorStart = start
                scanner.advance()
                guard SyntaxLexer.isIdentifierStart(scanner.current() ?? " ") else {
                    continue
                }
                scanner.consume { SyntaxLexer.isIdentifierPart($0) }
                SyntaxLexer.appendSpan(
                    start: decoratorStart,
                    length: scanner.offset - decoratorStart,
                    kind: .decorator,
                    to: &spans
                )
                continue
            }

            if char == "\"" {
                if rules.supportsTripleDoubleStrings,
                   scanner.peek() == "\"", scanner.peek(2) == "\""
                {
                    let result = scanTripleDoubleString(from: &scanner)
                    SyntaxLexer.appendSpan(start: start, length: result.length, kind: .string, to: &spans)
                    if result.stillOpen {
                        state.openString = .tripleDouble
                        return (spans, state)
                    }
                    continue
                }
                let length = scanCString(from: &scanner, delimiter: "\"")
                SyntaxLexer.appendSpan(start: start, length: length, kind: .string, to: &spans)
                if !stringClosed(start: start, length: length, delimiter: "\"", in: scanner.chars) {
                    state.openString = .doubleQuote
                    return (spans, state)
                }
                continue
            }

            if rules.supportsSingleQuoteStrings, char == "'" {
                let length = scanCString(from: &scanner, delimiter: "'")
                SyntaxLexer.appendSpan(start: start, length: length, kind: .string, to: &spans)
                if !stringClosed(start: start, length: length, delimiter: "'", in: scanner.chars) {
                    state.openString = .singleQuote
                    return (spans, state)
                }
                continue
            }

            if rules.supportsTemplateLiterals, char == "`" {
                let result = scanTemplateLiteral(from: &scanner)
                SyntaxLexer.appendSpan(start: start, length: result.length, kind: .string, to: &spans)
                if result.stillOpen {
                    state.openString = .backtick
                    return (spans, state)
                }
                continue
            }

            if char.isNumber || (char == "." && scanner.peek()?.isNumber == true) {
                let length = SyntaxLexer.scanNumber(from: &scanner)
                SyntaxLexer.appendSpan(start: start, length: length, kind: .number, to: &spans)
                continue
            }

            if SyntaxLexer.isIdentifierStart(char) {
                let idStart = scanner.offset
                scanner.consume { SyntaxLexer.isIdentifierPart($0) }
                let id = String(scanner.chars[idStart..<scanner.offset])
                if let kind = spanKindForIdentifier(
                    id,
                    rules: rules,
                    followedByOpenParen: scanner.current() == "("
                ) {
                    SyntaxLexer.appendSpan(
                        start: idStart,
                        length: scanner.offset - idStart,
                        kind: kind,
                        to: &spans
                    )
                }
                continue
            }

            if let punctLength = scanPunctuation(from: &scanner) {
                SyntaxLexer.appendSpan(start: start, length: punctLength, kind: .punctuation, to: &spans)
                continue
            }

            scanner.advance()
            SyntaxLexer.ensureLexerProgress(scanner: &scanner, iterationStart: start)
        }

        return (spans, state)
    }

    // MARK: - Identifier classification

    static func spanKindForIdentifier(
        _ id: String,
        rules: SyntaxRules,
        followedByOpenParen: Bool
    ) -> SyntaxTokenKind? {
        if rules.keywords.contains(id) {
            return .keyword
        }
        if id.first?.isUppercase == true {
            return .type
        }
        if followedByOpenParen {
            return .function
        }
        return nil
    }

    // MARK: - Block comments

    private static func findBlockCommentEnd(in chars: [Character], from start: Int) -> Int? {
        var index = start
        while index + 1 < chars.count {
            if chars[index] == "*", chars[index + 1] == "/" {
                return index + 2
            }
            index += 1
        }
        return nil
    }

    private static func consumeBlockCommentTail(from scanner: inout SyntaxLineScanner) -> Int? {
        findBlockCommentEnd(in: scanner.chars, from: 0)
    }

    // MARK: - Strings

    private static func stringClosed(
        start: Int,
        length: Int,
        delimiter: Character,
        in chars: [Character]
    ) -> Bool {
        guard length > 0, start + length - 1 < chars.count else { return false }
        return chars[start + length - 1] == delimiter
    }

    private static func scanCString(from scanner: inout SyntaxLineScanner, delimiter: Character) -> Int {
        let start = scanner.offset
        scanner.advance()
        while let char = scanner.current() {
            if char == "\\" {
                scanner.advance(2)
                continue
            }
            if char == delimiter {
                scanner.advance()
                return scanner.offset - start
            }
            scanner.advance()
        }
        return scanner.offset - start
    }

    private static func scanTripleDoubleString(from scanner: inout SyntaxLineScanner) -> (length: Int, stillOpen: Bool) {
        let start = scanner.offset
        scanner.advance(3)
        while scanner.offset + 2 < scanner.count {
            if scanner.current() == "\"", scanner.peek() == "\"", scanner.peek(2) == "\"" {
                scanner.advance(3)
                return (scanner.offset - start, false)
            }
            if scanner.current() == "\\" {
                scanner.advance(2)
                continue
            }
            scanner.advance()
        }
        scanner.index = scanner.count
        return (scanner.offset - start, true)
    }

    private static func scanTemplateLiteral(from scanner: inout SyntaxLineScanner) -> (length: Int, stillOpen: Bool) {
        let start = scanner.offset
        scanner.advance()
        while let char = scanner.current() {
            if char == "\\" {
                scanner.advance(2)
                continue
            }
            if char == "`" {
                scanner.advance()
                return (scanner.offset - start, false)
            }
            scanner.advance()
        }
        return (scanner.offset - start, true)
    }

    private static func consumeOpenString(
        delimiter: SyntaxStringDelimiter,
        from scanner: inout SyntaxLineScanner
    ) -> (length: Int, stillOpen: Bool) {
        let start = scanner.offset
        switch delimiter {
        case .tripleDouble:
            while scanner.offset + 2 < scanner.count {
                if scanner.current() == "\"", scanner.peek() == "\"", scanner.peek(2) == "\"" {
                    scanner.advance(3)
                    return (scanner.offset - start, false)
                }
                if scanner.current() == "\\" {
                    scanner.advance(2)
                    continue
                }
                scanner.advance()
            }
            scanner.index = scanner.count
            return (scanner.offset - start, true)
        case .doubleQuote:
            let length = scanCString(from: &scanner, delimiter: "\"")
            return (length, !stringClosed(start: start, length: length, delimiter: "\"", in: scanner.chars))
        case .singleQuote:
            let length = scanCString(from: &scanner, delimiter: "'")
            return (length, !stringClosed(start: start, length: length, delimiter: "'", in: scanner.chars))
        case .backtick:
            return scanTemplateLiteral(from: &scanner)
        }
    }

    // MARK: - Punctuation

    private static let twoCharOperators: Set<String> = [
        "==", "!=", "<=", ">=", "&&", "||", "??", "->", "=>", "+=", "-=", "*=", "/=",
        "%=", "&=", "|=", "^=", "::", "?.", "!!", "..",
    ]

    private static let oneCharPunctuation: Set<Character> = [
        "{", "}", "(", ")", "[", "]", ";", ",", ".", ":", "+", "-", "*", "/", "%",
        "=", "<", ">", "!", "&", "|", "^", "~", "?",
    ]

    private static func scanPunctuation(from scanner: inout SyntaxLineScanner) -> Int? {
        let start = scanner.offset
        if start + 2 < scanner.count {
            let three = String(scanner.chars[start..<(start + 3)])
            if three == "..." {
                scanner.advance(3)
                return 3
            }
        }
        if start + 1 < scanner.count {
            let two = String(scanner.chars[start..<(start + 2)])
            if twoCharOperators.contains(two) {
                scanner.advance(2)
                return 2
            }
        }
        if let char = scanner.current(), oneCharPunctuation.contains(char) {
            scanner.advance()
            return 1
        }
        return nil
    }
}
