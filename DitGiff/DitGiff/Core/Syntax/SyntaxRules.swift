/// Keyword and string-feature tables for the C-family scanner. Adding a language
/// means one `SyntaxRules` value and one `SyntaxLanguage` case — the scanner itself
/// never branches on language.
nonisolated struct SyntaxRules: Sendable {
    let keywords: Set<String>
    let supportsSingleQuoteStrings: Bool
    let supportsTripleDoubleStrings: Bool
    let supportsTemplateLiterals: Bool
    let supportsDecorators: Bool

    static let swift = SyntaxRules(
        keywords: Set([
            "actor", "as", "associatedtype", "async", "await", "break", "case", "catch",
            "class", "continue", "convenience", "default", "defer", "deinit", "do", "dynamic",
            "else", "enum", "extension", "fallthrough", "false", "fileprivate", "final",
            "for", "func", "guard", "if", "import", "in", "indirect", "init", "inout",
            "internal", "is", "lazy", "let", "mutating", "nil", "nonmutating", "open",
            "operator", "optional", "override", "postfix", "precedencegroup", "prefix",
            "private", "protocol", "public", "repeat", "required", "rethrows", "return",
            "self", "Self", "static", "struct", "subscript", "super", "switch", "throw",
            "throws", "true", "try", "typealias", "unowned", "var", "weak", "where", "while",
            "willSet", "didSet", "some", "any", "macro", "yield",
        ]),
        supportsSingleQuoteStrings: false,
        supportsTripleDoubleStrings: true,
        supportsTemplateLiterals: false,
        supportsDecorators: true
    )

    private static let javascriptKeywords: Set<String> = [
        "async", "await", "break", "case", "catch", "class", "const", "continue", "debugger",
        "default", "delete", "do", "else", "export", "extends", "false", "finally", "for",
        "function", "if", "import", "in", "instanceof", "let", "new", "null", "of", "return",
        "super", "switch", "this", "throw", "true", "try", "typeof", "undefined", "var",
        "void", "while", "with", "yield",
    ]

    private static let typescriptOnlyKeywords: Set<String> = [
        "abstract", "any", "as", "bigint", "boolean", "declare", "enum", "global", "implements",
        "infer", "interface", "is", "keyof", "module", "namespace", "never", "number", "private",
        "protected", "public", "readonly", "require", "satisfies", "string", "symbol", "type",
        "unknown",
    ]

    static let javascript = SyntaxRules(
        keywords: javascriptKeywords,
        supportsSingleQuoteStrings: true,
        supportsTripleDoubleStrings: false,
        supportsTemplateLiterals: true,
        supportsDecorators: true
    )

    static let typescript = SyntaxRules(
        keywords: javascriptKeywords.union(typescriptOnlyKeywords),
        supportsSingleQuoteStrings: true,
        supportsTripleDoubleStrings: false,
        supportsTemplateLiterals: true,
        supportsDecorators: true
    )

    static func rules(for language: SyntaxLanguage) -> SyntaxRules {
        switch language {
        case .swift:
            return .swift
        case .javascript:
            return .javascript
        case .typescript:
            return .typescript
        default:
            fatalError("Not a C-family language: \(language)")
        }
    }
}

nonisolated enum SyntaxKeywordSets {
    static let json: Set<String> = ["true", "false", "null"]
    static let yaml: Set<String> = ["true", "false", "null", "yes", "no"]
    static let shell: Set<String> = [
        "if", "then", "else", "fi", "for", "while", "do", "done", "case", "esac",
        "function", "local", "export", "return",
    ]
}
