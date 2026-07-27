nonisolated enum SyntaxLanguage: Equatable, Sendable, CaseIterable {
    case swift
    case javascript
    case typescript
    case json
    case yaml
    case markdown
    case shell
    case html
    case plain

    static func detect(path: String) -> SyntaxLanguage {
        let filename = path.split(separator: "/").last.map(String.init) ?? path
        guard let dotIndex = filename.lastIndex(of: "."),
              dotIndex != filename.startIndex
        else {
            return .plain
        }

        let extensionStart = filename.index(after: dotIndex)
        let ext = String(filename[extensionStart...]).lowercased()

        switch ext {
        case "swift":
            return .swift
        case "js", "jsx", "mjs", "cjs":
            return .javascript
        case "ts", "tsx", "mts", "cts":
            return .typescript
        case "json", "jsonc":
            return .json
        case "yml", "yaml":
            return .yaml
        case "md", "markdown":
            return .markdown
        case "sh", "bash", "zsh", "fish":
            return .shell
        case "html", "htm":
            return .html
        default:
            return .plain
        }
    }
}
