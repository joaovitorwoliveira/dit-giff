import Foundation
import Testing

@testable import DitGiff

nonisolated struct PatchAssemblyTests {
    private let runner = SystemCommandRunner()

    // MARK: - Unit: assemble

    @Test func assembleParsesTextHunksAndCountsLines() throws {
        let envelopes = [
            PatchFileEnvelope(
                path: "f.txt",
                oldPath: nil,
                change: .modified,
                body: .text("""
                @@ -1,2 +1,3 @@
                 keep
                -old
                +new
                +extra
                """),
                oldMode: "100644",
                newMode: "100644"
            ),
        ]

        let patch = try Patch.assemble(from: envelopes)
        #expect(patch.files.count == 1)
        let file = try #require(patch.files.first)
        #expect(file.path == "f.txt")
        #expect(file.hunks.count == 1)
        #expect(file.additions == 2)
        #expect(file.deletions == 1)
        #expect(file.isBinary == false)
        #expect(file.isSubmodule == false)
    }

    @Test func assembleLeavesBinarySubmoduleAndNoContentWithoutHunks() throws {
        let envelopes = [
            PatchFileEnvelope(
                path: "bin",
                oldPath: nil,
                change: .added,
                body: .binary,
                oldMode: nil,
                newMode: "100644"
            ),
            PatchFileEnvelope(
                path: "vendor",
                oldPath: nil,
                change: .added,
                body: .submodule,
                oldMode: nil,
                newMode: "160000"
            ),
            PatchFileEnvelope(
                path: "empty.txt",
                oldPath: nil,
                change: .added,
                body: .noContent,
                oldMode: nil,
                newMode: "100644"
            ),
            PatchFileEnvelope(
                path: "mode.txt",
                oldPath: nil,
                change: .modified,
                body: .noContent,
                oldMode: "100644",
                newMode: "100755"
            ),
        ]

        let patch = try Patch.assemble(from: envelopes)
        #expect(patch.files.map(\.path) == ["bin", "vendor", "empty.txt", "mode.txt"])
        #expect(patch.files[0].isBinary)
        #expect(patch.files[0].hunks.isEmpty)
        #expect(patch.files[0].additions == 0)
        #expect(patch.files[1].isSubmodule)
        #expect(patch.files[2].change == .added)
        #expect(patch.files[2].hunks.isEmpty)
        #expect(patch.files[3].change == .modified)
        #expect(patch.files[3].hunks.isEmpty)
    }

    @Test func assembleTagsHunkParserErrorsWithFilePath() {
        let envelopes = [
            PatchFileEnvelope(
                path: "broken.swift",
                oldPath: nil,
                change: .modified,
                body: .text("not a hunk header\n"),
                oldMode: "100644",
                newMode: "100644"
            ),
        ]

        #expect {
            try Patch.assemble(from: envelopes)
        } throws: { error in
            guard let error = error as? PatchError,
                  case let .hunkParseFailed(path, _) = error
            else {
                return false
            }
            #expect(path == "broken.swift")
            #expect(error.errorDescription?.contains("broken.swift") == true)
            return true
        }
    }

    // MARK: - End-to-end against real git + numstat

    @Test func loadPatchMatchesRealGitAndNumstat() async throws {
        let fixture = try await PatchAssemblyFixture.make(runner: runner)
        defer { fixture.remove() }

        let service = GitService(runner: runner)
        let repository = try await service.openRepository(at: fixture.root)
        let branches = try await service.listBranches(in: repository)
        let base = try #require(branches.first { $0.displayName == "main" && !$0.isRemote })
        let compare = try #require(branches.first { $0.displayName == "feature" && !$0.isRemote })

        let patch = try await service.loadPatch(in: repository, base: base, compare: compare)
        let byPath = Dictionary(uniqueKeysWithValues: patch.files.map { ($0.path, $0) })

        // Modified with several hunks
        let multi = try #require(byPath["multi.txt"])
        #expect(multi.change == .modified)
        #expect(multi.hunks.count >= 2)
        #expect(multi.additions == 2)
        #expect(multi.deletions == 2)

        // Added
        let added = try #require(byPath["added.txt"])
        #expect(added.change == .added)
        #expect(added.hunks.count == 1)
        #expect(added.additions == 1)
        #expect(added.deletions == 0)

        // Deleted
        let deleted = try #require(byPath["delete.txt"])
        #expect(deleted.change == .deleted)
        #expect(deleted.hunks.count == 1)
        #expect(deleted.additions == 0)
        #expect(deleted.deletions == 1)

        // Rename without content change
        let renamedPure = try #require(byPath["renamed_pure.txt"])
        #expect(renamedPure.change == .renamed(from: "rename_pure.txt"))
        #expect(renamedPure.oldPath == "rename_pure.txt")
        #expect(renamedPure.hunks.isEmpty)
        #expect(renamedPure.additions == 0)
        #expect(renamedPure.deletions == 0)

        // Rename with content change
        let renamedEdit = try #require(byPath["renamed_edit.txt"])
        #expect(renamedEdit.change == .renamed(from: "rename_edit.txt"))
        #expect(renamedEdit.hunks.count == 1)
        #expect(renamedEdit.additions == 1)
        #expect(renamedEdit.deletions == 1)

        // Space / accent
        let spaced = try #require(byPath["file with spaces.txt"])
        #expect(spaced.change == .added)
        #expect(spaced.additions == 1)
        let accent = try #require(byPath["arquivo café.txt"])
        #expect(accent.change == .added)
        #expect(accent.additions == 1)

        // Binary
        let binary = try #require(byPath["binary.bin"])
        #expect(binary.isBinary)
        #expect(binary.hunks.isEmpty)
        #expect(binary.additions == 0)
        #expect(binary.deletions == 0)

        // Mode-only
        let mode = try #require(byPath["mode.txt"])
        #expect(mode.change == .modified)
        #expect(mode.hunks.isEmpty)
        #expect(mode.additions == 0)
        #expect(mode.deletions == 0)

        // Empty new file
        let empty = try #require(byPath["empty_new.txt"])
        #expect(empty.change == .added)
        #expect(empty.hunks.isEmpty)

        // No trailing newline
        let nonewline = try #require(byPath["nonewline.txt"])
        #expect(nonewline.change == .modified)
        #expect(nonewline.additions == 1)
        #expect(nonewline.deletions == 1)

        // CRLF line endings
        let crlf = try #require(byPath["crlf.txt"])
        #expect(crlf.change == .modified)
        #expect(crlf.hunks.count == 1)
        #expect(crlf.additions == 1)
        #expect(crlf.deletions == 1)

        // Counts vs git diff --numstat
        let numstat = try await fixture.numstat(runner: runner, base: "main", compare: "feature")
        for file in patch.files {
            let key = file.path
            let expected = try #require(numstat[key], "numstat missing \(key)")
            if file.isBinary {
                #expect(expected.isBinary, "git should mark \(key) binary in numstat")
                #expect(file.additions == 0)
                #expect(file.deletions == 0)
            } else {
                #expect(expected.isBinary == false, "\(key) unexpectedly binary in numstat")
                #expect(
                    file.additions == expected.additions,
                    "additions for \(key): patch=\(file.additions) numstat=\(expected.additions)"
                )
                #expect(
                    file.deletions == expected.deletions,
                    "deletions for \(key): patch=\(file.deletions) numstat=\(expected.deletions)"
                )
            }
        }

        #expect(Set(patch.files.map(\.path)) == Set(numstat.keys))
    }
}

// MARK: - Fixture

private struct PatchAssemblyFixture {
    let root: URL

    static let gitEnvironment: [String: String] = [
        "GIT_TERMINAL_PROMPT": "0",
        "LC_ALL": "C",
        "GIT_OPTIONAL_LOCKS": "0",
    ]

    struct NumstatEntry: Equatable {
        let additions: Int
        let deletions: Int
        let isBinary: Bool
    }

    static func make(runner: SystemCommandRunner) async throws -> PatchAssemblyFixture {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("dit-giff-patch-assembly-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)

        try await runGit(runner, in: root, "init", "-b", "main")
        try await runGit(runner, in: root, "config", "core.filemode", "true")
        try await runGit(runner, in: root, "config", "core.autocrlf", "false")
        try await commit(runner, in: root, message: "initial", allowEmpty: true)

        // multi.txt — 40 lines so two distant edits become two hunks
        var multiLines = (1 ... 40).map { String(format: "line%02d", $0) }
        try (multiLines.joined(separator: "\n") + "\n")
            .write(to: root.appendingPathComponent("multi.txt"), atomically: true, encoding: .utf8)

        try "rename-pure\n".write(
            to: root.appendingPathComponent("rename_pure.txt"),
            atomically: true,
            encoding: .utf8
        )
        try """
        shared line 1
        shared line 2
        shared line 3
        unique-old
        shared line 5

        """.write(
            to: root.appendingPathComponent("rename_edit.txt"),
            atomically: true,
            encoding: .utf8
        )
        try "delete-me\n".write(
            to: root.appendingPathComponent("delete.txt"),
            atomically: true,
            encoding: .utf8
        )
        try "mode-only\n".write(
            to: root.appendingPathComponent("mode.txt"),
            atomically: true,
            encoding: .utf8
        )
        try Data("no-nl".utf8).write(to: root.appendingPathComponent("nonewline.txt"))
        try Data("crlf\r\nline2\r\n".utf8).write(to: root.appendingPathComponent("crlf.txt"))

        try await runGit(runner, in: root, "add", "-A")
        try await commit(runner, in: root, message: "base files")

        try await runGit(runner, in: root, "checkout", "-b", "feature")

        multiLines[0] = "LINE01"
        multiLines[39] = "LINE40"
        try (multiLines.joined(separator: "\n") + "\n")
            .write(to: root.appendingPathComponent("multi.txt"), atomically: true, encoding: .utf8)

        try await runGit(runner, in: root, "mv", "rename_pure.txt", "renamed_pure.txt")
        try await runGit(runner, in: root, "mv", "rename_edit.txt", "renamed_edit.txt")
        try """
        shared line 1
        shared line 2
        shared line 3
        unique-NEW
        shared line 5

        """.write(
            to: root.appendingPathComponent("renamed_edit.txt"),
            atomically: true,
            encoding: .utf8
        )

        try fm.removeItem(at: root.appendingPathComponent("delete.txt"))

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: root.appendingPathComponent("mode.txt").path
        )

        try Data("no-nlX".utf8).write(to: root.appendingPathComponent("nonewline.txt"))
        try Data("CRLF\r\nline2\r\n".utf8).write(to: root.appendingPathComponent("crlf.txt"))

        try "added\n".write(
            to: root.appendingPathComponent("added.txt"),
            atomically: true,
            encoding: .utf8
        )
        try Data().write(to: root.appendingPathComponent("empty_new.txt"))
        try "spaced\n".write(
            to: root.appendingPathComponent("file with spaces.txt"),
            atomically: true,
            encoding: .utf8
        )
        try "café\n".write(
            to: root.appendingPathComponent("arquivo café.txt"),
            atomically: true,
            encoding: .utf8
        )
        try Data([0x00, 0x01, 0xFF]).write(to: root.appendingPathComponent("binary.bin"))

        try await runGit(runner, in: root, "add", "-A")
        try await commit(runner, in: root, message: "feature changes")

        return PatchAssemblyFixture(root: root)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    /// Parse `git diff --numstat -z --find-renames` keyed by destination path.
    func numstat(
        runner: SystemCommandRunner,
        base: String,
        compare: String
    ) async throws -> [String: NumstatEntry] {
        let output = try await runner.run(
            CommandRequest(
                executable: "git",
                arguments: [
                    "-c", "core.quotePath=false",
                    "diff", "--numstat", "-z", "--find-renames",
                    "\(base)...\(compare)",
                ],
                workingDirectory: root,
                environment: Self.gitEnvironment
            )
        )
        guard output.didSucceed else {
            throw FixtureError.commandFailed(
                "diff --numstat",
                output.standardError.isEmpty ? "exit \(output.exitCode)" : output.standardError
            )
        }
        return try Self.parseNumstat(output.standardOutput)
    }

    /// `git diff --numstat -z` records:
    /// - text: `add\tdel\tpath\0`
    /// - binary: `-\t-\tpath\0`
    /// - rename: `add\tdel\t\0old\0new\0`
    static func parseNumstat(_ raw: String) throws -> [String: NumstatEntry] {
        if raw.isEmpty { return [:] }

        var result: [String: NumstatEntry] = [:]
        var cursor = raw.startIndex

        while cursor < raw.endIndex {
            if raw[cursor] == "\0" {
                cursor = raw.index(after: cursor)
                continue
            }

            guard let firstTab = raw[cursor...].firstIndex(of: "\t") else {
                throw FixtureError.commandFailed("numstat parse", "missing first tab")
            }
            let addField = String(raw[cursor..<firstTab])
            var i = raw.index(after: firstTab)
            guard let secondTab = raw[i...].firstIndex(of: "\t") else {
                throw FixtureError.commandFailed("numstat parse", "missing second tab")
            }
            let delField = String(raw[i..<secondTab])
            i = raw.index(after: secondTab)

            guard let pathEnd = raw[i...].firstIndex(of: "\0") else {
                throw FixtureError.commandFailed("numstat parse", "missing path NUL")
            }
            let pathField = String(raw[i..<pathEnd])
            i = raw.index(after: pathEnd)

            let destination: String
            if pathField.isEmpty {
                // Rename / copy: old\0new\0
                guard let oldEnd = raw[i...].firstIndex(of: "\0") else {
                    throw FixtureError.commandFailed("numstat parse", "rename missing old path")
                }
                i = raw.index(after: oldEnd)
                guard let newEnd = raw[i...].firstIndex(of: "\0") else {
                    throw FixtureError.commandFailed("numstat parse", "rename missing new path")
                }
                destination = String(raw[i..<newEnd])
                i = raw.index(after: newEnd)
            } else {
                destination = pathField
            }

            let entry: NumstatEntry
            if addField == "-", delField == "-" {
                entry = NumstatEntry(additions: 0, deletions: 0, isBinary: true)
            } else {
                guard let additions = Int(addField), let deletions = Int(delField) else {
                    throw FixtureError.commandFailed(
                        "numstat parse",
                        "non-integer counts \(addField)/\(delField) for \(destination)"
                    )
                }
                entry = NumstatEntry(additions: additions, deletions: deletions, isBinary: false)
            }
            result[destination] = entry
            cursor = i
        }

        return result
    }

    private static func commit(
        _ runner: SystemCommandRunner,
        in directory: URL,
        message: String,
        allowEmpty: Bool = false
    ) async throws {
        var args = [
            "-c", "user.email=test@dit-giff.local",
            "-c", "user.name=DitGiffTests",
            "commit", "-m", message,
        ]
        if allowEmpty {
            args.insert("--allow-empty", at: args.count - 2)
        }
        try await runGit(runner, in: directory, args)
    }

    private static func runGit(
        _ runner: SystemCommandRunner,
        in directory: URL,
        _ arguments: String...
    ) async throws {
        try await runGit(runner, in: directory, Array(arguments))
    }

    private static func runGit(
        _ runner: SystemCommandRunner,
        in directory: URL,
        _ arguments: [String]
    ) async throws {
        let output = try await runner.run(
            CommandRequest(
                executable: "git",
                arguments: arguments,
                workingDirectory: directory,
                environment: gitEnvironment
            )
        )
        guard output.didSucceed else {
            let detail = output.standardError.isEmpty
                ? "exit \(output.exitCode)"
                : output.standardError
            throw FixtureError.commandFailed(arguments.joined(separator: " "), detail)
        }
    }

    private enum FixtureError: Error, CustomStringConvertible {
        case commandFailed(String, String)

        var description: String {
            switch self {
            case let .commandFailed(command, detail):
                "git \(command) failed: \(detail)"
            }
        }
    }
}
