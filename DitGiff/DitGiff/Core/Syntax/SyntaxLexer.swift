/// Character-indexed view of a single line. Offsets are always in `Character` counts
/// so accents and emoji stay aligned with what SwiftUI will paint.
struct SyntaxLineScanner {
    let chars: [Character]
    var index: Int = 0

    var count: Int { chars.count }
    var isAtEnd: Bool { index >= chars.count }

    var offset: Int { index }

    init(_ line: String) {
        chars = Array(line)
    }

    func current() -> Character? {
        guard index < chars.count else { return nil }
        return chars[index]
    }

    func peek(_ ahead: Int = 1) -> Character? {
        let target = index + ahead
        guard target < chars.count else { return nil }
        return chars[target]
    }

    mutating func advance(_ count: Int = 1) {
        index += count
    }

    mutating func consume(while predicate: (Character) -> Bool) {
        while let char = current(), predicate(char) {
            advance()
        }
    }
}

nonisolated enum SyntaxLexer {
    static func tokenize(
        _ line: String,
        language: SyntaxLanguage,
        state: SyntaxLexerState
    ) -> (spans: [SyntaxSpan], next: SyntaxLexerState) {
        switch language {
        case .swift, .javascript, .typescript:
            return CFamilySyntaxLexer.tokenize(line, rules: SyntaxRules.rules(for: language), state: state)
        case .json:
            return tokenizeJSON(line)
        case .yaml:
            return tokenizeYAML(line)
        case .markdown:
            return tokenizeMarkdown(line)
        case .shell:
            return tokenizeShell(line)
        case .html:
            return tokenizeHTML(line, state: state)
        case .plain:
            return tokenizePlain(line)
        }
    }
}

// MARK: - Span helpers

extension SyntaxLexer {
    static func appendSpan(
        start: Int,
        length: Int,
        kind: SyntaxTokenKind,
        to spans: inout [SyntaxSpan]
    ) {
        guard length > 0 else { return }
        spans.append(SyntaxSpan(start: start, length: length, kind: kind))
    }

    static func isIdentifierStart(_ char: Character) -> Bool {
        char.isLetter || char == "_"
    }

    static func isIdentifierPart(_ char: Character) -> Bool {
        char.isLetter || char.isNumber || char == "_"
    }
}

// MARK: - Numbers

extension SyntaxLexer {
    /// Lexers run on the main thread when a hunk is materialized; a rule that
    /// matches without consuming would freeze the UI.
    static func ensureLexerProgress(
        scanner: inout SyntaxLineScanner,
        iterationStart: Int
    ) {
        guard scanner.offset == iterationStart else { return }
        scanner.advance()
    }

    static func scanNumber(from scanner: inout SyntaxLineScanner) -> Int {
        let start = scanner.offset
        guard scanner.current() != nil else { return 0 }

        if let sign = scanner.current(), sign == "+" || sign == "-" {
            guard let next = scanner.peek(), next.isNumber else { return 0 }
            scanner.advance()
        }

        guard let first = scanner.current(), first.isNumber else { return 0 }

        if first == "0", let second = scanner.peek() {
            if second == "x" || second == "X" {
                scanner.advance(2)
                scanner.consume { $0.isHexDigit || $0 == "_" }
                return scanner.offset - start
            }
            if second == "b" || second == "B" {
                scanner.advance(2)
                scanner.consume { $0 == "0" || $0 == "1" || $0 == "_" }
                return scanner.offset - start
            }
        }

        scanner.consume { $0.isNumber || $0 == "_" || $0 == "." }

        if let exp = scanner.current(), exp == "e" || exp == "E" {
            scanner.advance()
            if let sign = scanner.current(), sign == "+" || sign == "-" {
                scanner.advance()
            }
            scanner.consume { $0.isNumber || $0 == "_" }
        }

        return scanner.offset - start
    }

    static func isNumberStart(_ char: Character, in scanner: SyntaxLineScanner) -> Bool {
        guard char.isNumber else { return false }
        if char == "0" {
            return true
        }
        // Avoid treating `.5` as number start unless preceded by digit — handled at call site.
        return true
    }
}

// MARK: - Shared string scanners

extension SyntaxLexer {
    static func scanDoubleQuotedString(from scanner: inout SyntaxLineScanner) -> Int {
        let start = scanner.offset
        scanner.advance()
        while let char = scanner.current() {
            if char == "\\" {
                scanner.advance(2)
                continue
            }
            if char == "\"" {
                scanner.advance()
                return scanner.offset - start
            }
            scanner.advance()
        }
        return scanner.offset - start
    }

    static func scanSingleQuotedString(from scanner: inout SyntaxLineScanner) -> Int {
        let start = scanner.offset
        scanner.advance()
        while let char = scanner.current() {
            if char == "\\" {
                scanner.advance(2)
                continue
            }
            if char == "'" {
                scanner.advance()
                return scanner.offset - start
            }
            scanner.advance()
        }
        return scanner.offset - start
    }
}
