import Foundation

/// The only type in this app that spawns a process. Nothing else may import `Process`.
nonisolated struct SystemCommandRunner: CommandRunner {
    /// What an app launched from Finder gets instead of a shell's `PATH`. `git` lives
    /// here; `claude` usually does not, so it will have to be located explicitly.
    private static let fallbackSearchPath = "/usr/bin:/bin:/usr/sbin:/sbin"

    func run(_ request: CommandRequest) async throws -> CommandOutput {
        let control = ProcessControl()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                // The work below blocks on two pipe reads and a process wait, so it gets
                // its own thread and leaves the caller's task free.
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let output = try Self.runBlocking(request, control: control)
                        continuation.resume(returning: output)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            control.cancel()
        }
    }

    func stream(_ request: CommandRequest) -> AsyncThrowingStream<CommandStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let control = ProcessControl()
            // Cancel must reach ProcessControl directly. Wrapping the worker in another
            // Task left a window where producer.cancel() ran before withTaskCancellationHandler
            // was installed, so the child survived. onTermination is the consumer-cancel seam.
            continuation.onTermination = { @Sendable _ in
                control.cancel()
            }
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try Self.streamBlocking(
                        request,
                        control: control,
                        continuation: continuation
                    )
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private static func runBlocking(
        _ request: CommandRequest,
        control: ProcessControl
    ) throws -> CommandOutput {
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
        let standardInputPipe = attachedStandardInputPipe(for: request, process: process)

        do {
            try process.run()
        } catch {
            throw CommandFailure.launchFailed(
                executable: request.executable,
                reason: error.localizedDescription
            )
        }

        // Attach after `run()` so `terminate()` is always aimed at a live process.
        // If the task already cancelled, this terminates immediately.
        control.attach(process)

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

        // Readers must be running before stdin is written: a child that echoes stdin
        // can fill the stdout pipe and stall while we are still writing.
        try writeAndCloseStandardInput(standardInputPipe, text: request.standardInput)

        reads.wait()
        process.waitUntilExit()

        // Always reap via waitUntilExit above — cancel must not leave a zombie.
        // Do not return partial pipes as a successful answer.
        if control.isCancelled {
            throw CancellationError()
        }

        return CommandOutput(
            standardOutput: String(decoding: standardOutputData.value, as: UTF8.self),
            standardError: String(decoding: standardErrorData.value, as: UTF8.self),
            exitCode: process.terminationStatus
        )
    }

    private static func streamBlocking(
        _ request: CommandRequest,
        control: ProcessControl,
        continuation: AsyncThrowingStream<CommandStreamEvent, Error>.Continuation
    ) throws {
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
        let standardInputPipe = attachedStandardInputPipe(for: request, process: process)

        do {
            try process.run()
        } catch {
            throw CommandFailure.launchFailed(
                executable: request.executable,
                reason: error.localizedDescription
            )
        }

        control.attach(process)

        // Blocking availableData on dedicated queues, matching run()'s style.
        // readabilityHandler must be cleared on EOF or the handle retains the
        // handler and leaks across runs.
        let reads = DispatchGroup()

        DispatchQueue.global(qos: .userInitiated).async(group: reads) {
            readLines(from: standardOutputPipe.fileHandleForReading) { line in
                continuation.yield(.standardOutputLine(line))
            }
        }
        DispatchQueue.global(qos: .userInitiated).async(group: reads) {
            readLines(from: standardErrorPipe.fileHandleForReading) { line in
                continuation.yield(.standardErrorLine(line))
            }
        }

        try writeAndCloseStandardInput(standardInputPipe, text: request.standardInput)

        reads.wait()
        process.waitUntilExit()

        // Always reap via waitUntilExit above — cancel must not leave a zombie.
        // Do not yield `.exited` after cancel: the consumer already dropped the stream.
        if control.isCancelled {
            continuation.finish(throwing: CancellationError())
            return
        }

        continuation.yield(.exited(code: process.terminationStatus))
        continuation.finish()
    }

    private static func attachedStandardInputPipe(
        for request: CommandRequest,
        process: Process
    ) -> Pipe? {
        guard request.standardInput != nil else { return nil }
        let pipe = Pipe()
        process.standardInput = pipe
        return pipe
    }

    private static func writeAndCloseStandardInput(_ pipe: Pipe?, text: String?) throws {
        guard let pipe, let text else { return }
        let handle = pipe.fileHandleForWriting
        try handle.write(contentsOf: Data(text.utf8))
        try handle.close()
    }

    private static func readLines(from handle: FileHandle, emit: (String) -> Void) {
        var buffer = Data()
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer[buffer.startIndex..<newline]
                let afterNewline = buffer.index(after: newline)
                buffer.removeSubrange(buffer.startIndex..<afterNewline)
                emit(String(decoding: lineData, as: UTF8.self))
            }
        }
        if !buffer.isEmpty {
            emit(String(decoding: buffer, as: UTF8.self))
        }
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

/// Holds the live `Process` so the cancellation handler can terminate it without
/// racing the blocking worker, and without calling `terminate` on a process that
/// never started or has already exited.
private nonisolated final class ProcessControl: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    func attach(_ process: Process) {
        lock.lock()
        let shouldTerminate = cancelled
        self.process = process
        lock.unlock()
        if shouldTerminate {
            terminateIfRunning(process)
        }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let process = self.process
        lock.unlock()
        if let process {
            terminateIfRunning(process)
        }
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    private func terminateIfRunning(_ process: Process) {
        // `terminate()` is a no-op when the process is not running — that covers the
        // race where the child exits naturally in the same moment as cancel.
        guard process.isRunning else { return }
        process.terminate()
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
