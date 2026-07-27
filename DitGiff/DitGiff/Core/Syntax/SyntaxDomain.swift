nonisolated enum SyntaxTokenKind: Equatable, Sendable {
    case keyword
    case type
    case string
    case number
    case comment
    case function
    case decorator
    case punctuation
}

nonisolated struct SyntaxSpan: Equatable, Sendable {
    let start: Int
    let length: Int
    let kind: SyntaxTokenKind
}

/// Delimiter for a string that was opened but not closed before end-of-line.
nonisolated enum SyntaxStringDelimiter: Equatable, Sendable {
    case doubleQuote
    case singleQuote
    case backtick
    case tripleDouble
}

nonisolated struct SyntaxLexerState: Equatable, Sendable {
    static let start = SyntaxLexerState()

    var inBlockComment: Bool
    var openString: SyntaxStringDelimiter?

    init(inBlockComment: Bool = false, openString: SyntaxStringDelimiter? = nil) {
        self.inBlockComment = inBlockComment
        self.openString = openString
    }
}
