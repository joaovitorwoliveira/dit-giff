/// The sidebar tree. Directories carry their depth so a row knows its own indentation
/// without walking back up.
nonisolated struct DiffTreeDirectory: Identifiable, Equatable, Sendable {
    /// "Sources/Billing/" — unique, and what the open/closed state is keyed on.
    let path: String
    let name: String
    let depth: Int
    let children: [DiffTreeNode]

    var id: String { path }
}

nonisolated enum DiffTreeNode: Identifiable, Equatable, Sendable {
    case directory(DiffTreeDirectory)
    case file(DiffFile, depth: Int)

    var id: String {
        switch self {
        case let .directory(directory): directory.id
        case let .file(file, _): file.id
        }
    }

    var depth: Int {
        switch self {
        case let .directory(directory): directory.depth
        case let .file(_, depth): depth
        }
    }
}

nonisolated enum DiffTree {
    /// Groups a flat list of paths into folders, keeping the order the files arrive in.
    /// Within a level, directories come before the files that sit directly in it.
    static func build(files: [DiffFile]) -> [DiffTreeNode] {
        build(files: files, prefix: "", depth: 0)
    }

    private static func build(files: [DiffFile], prefix: String, depth: Int) -> [DiffTreeNode] {
        var directoryOrder: [String] = []
        var filesByDirectory: [String: [DiffFile]] = [:]
        var looseFiles: [DiffFile] = []

        for file in files {
            let remainder = file.path.dropFirst(prefix.count)
            let components = remainder.split(separator: "/")
            guard components.count > 1, let head = components.first.map(String.init) else {
                looseFiles.append(file)
                continue
            }
            if filesByDirectory[head] == nil {
                directoryOrder.append(head)
            }
            filesByDirectory[head, default: []].append(file)
        }

        var nodes: [DiffTreeNode] = directoryOrder.map { name in
            let path = prefix + name + "/"
            let children = build(files: filesByDirectory[name] ?? [], prefix: path, depth: depth + 1)
            return .directory(
                DiffTreeDirectory(path: path, name: name, depth: depth, children: children)
            )
        }
        nodes += looseFiles.map { .file($0, depth: depth) }
        return nodes
    }
}

/// How many of a folder's descendant files match a binary mark (viewed, collapsed, …).
/// Drives the three-state folder controls and the click rule: not-all → all, all → none.
nonisolated enum DiffAggregateState: Equatable, Sendable {
    case none
    case some
    case all

    static func of(matchingCount: Int, total: Int) -> DiffAggregateState {
        guard total > 0, matchingCount > 0 else { return .none }
        if matchingCount >= total { return .all }
        return .some
    }

    /// Whether the next click should turn every descendant on.
    var togglesTowardAll: Bool { self != .all }
}

extension DiffTreeDirectory {
    /// Every file under this folder, including those nested in subfolders at any depth.
    var descendantFiles: [DiffFile] {
        children.flatMap { node -> [DiffFile] in
            switch node {
            case let .directory(directory):
                return directory.descendantFiles
            case let .file(file, _):
                return [file]
            }
        }
    }
}
