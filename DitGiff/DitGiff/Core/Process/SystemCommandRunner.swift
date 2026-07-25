import Foundation

/// The only type in this app that spawns a process. Nothing else may import `Process`.
nonisolated struct SystemCommandRunner: CommandRunner {
    /// What an app launched from Finder gets instead of a shell's `PATH`. `git` lives
    /// here; `claude` usually does not, so it will have to be located explicitly.
    private static let fallbackSearchPath = "/usr/bin:/bin:/usr/sbin:/sbin"

    func run(_ request: CommandRequest) async throws -> CommandOutput {
        try await withCheckedThrowingContinuation { continuation in
            // The work below blocks on two pipe reads and a process wait, so it gets
            // its own thread and leaves the caller's task free.
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try Self.runBlocking(request))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func runBlocking(_ request: CommandRequest) throws -> CommandOutput {
        let environment = ProcessInfo.processInfo.environment
            .merging(request.environment) { _, fromRequest in fromRequest }

        let process = Process()
        process.executableURL = try resolvedExecutableURL(for: request, environment: environment)
        process.arguments = request.arguments
        process.currentDirectoryURL = request.workingDirectory
        process.environment = environment

        let standardOutputPipe = Pipe()
        let standardErrorPipe = Pipe()
        process.standardOutput = standardOutputPipe
        process.standardError = standardErrorPipe

        do {
            try process.run()
        } catch {
            throw CommandFailure.launchFailed(
                executable: request.executable,
                reason: error.localizedDescription
            )
        }

        // A pipe holds about 64 KB before the writer blocks, and a `git diff` passes
        // that without trying. Reading one pipe to EOF first, or waiting for exit
        // before reading, deadlocks on exactly the input this app exists to handle.
        let standardOutputData = CollectedData()
        let standardErrorData = CollectedData()
        let reads = DispatchGroup()

        DispatchQueue.global(qos: .userInitiated).async(group: reads) {
            standardOutputData.store(standardOutputPipe.fileHandleForReading.readDataToEndOfFile())
        }
        DispatchQueue.global(qos: .userInitiated).async(group: reads) {
            standardErrorData.store(standardErrorPipe.fileHandleForReading.readDataToEndOfFile())
        }

        reads.wait()
        process.waitUntilExit()

        return CommandOutput(
            standardOutput: String(decoding: standardOutputData.value, as: UTF8.self),
            standardError: String(decoding: standardErrorData.value, as: UTF8.self),
            exitCode: process.terminationStatus
        )
    }

    // Resolving `PATH` here instead of delegating to `/usr/bin/env` is what keeps a
    // missing binary a launch failure rather than a command that ran and exited 127.
    private static func resolvedExecutableURL(
        for request: CommandRequest,
        environment: [String: String]
    ) throws -> URL {
        let fileManager = FileManager.default

        if request.executable.contains("/") {
            let url = URL(fileURLWithPath: request.executable)
            guard fileManager.isExecutableFile(atPath: url.path) else {
                throw CommandFailure.launchFailed(
                    executable: request.executable,
                    reason: "no executable file at that path"
                )
            }
            return url
        }

        let searchPath = environment["PATH"] ?? fallbackSearchPath
        for directory in searchPath.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory))
                .appendingPathComponent(request.executable)
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        throw CommandFailure.launchFailed(
            executable: request.executable,
            reason: "not found in PATH (\(searchPath))"
        )
    }
}

/// `@unchecked` is honest here: every access goes through the lock, which the compiler
/// cannot see but a reader can.
private nonisolated final class CollectedData: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func store(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        storage = data
    }

    var value: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
