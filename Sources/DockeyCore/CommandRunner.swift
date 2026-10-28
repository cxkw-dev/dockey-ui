import Darwin
import Foundation

/// A process request is an executable plus discrete arguments, never a shell command.
public struct CommandRequest: Sendable, Equatable {
    public let executableURL: URL
    public let arguments: [String]
    public let timeout: TimeInterval
    public let outputLimitBytes: Int
    public init(
        executableURL: URL, arguments: [String], timeout: TimeInterval = 20,
        outputLimitBytes: Int = 8 * 1_024 * 1_024
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.timeout = timeout
        self.outputLimitBytes = max(1_024, outputLimitBytes)
    }
}

public struct CommandOutput: Sendable, Equatable {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32
    public init(stdout: String = "", stderr: String = "", exitCode: Int32 = 0) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
    }
}

public protocol CommandRunning: Sendable {
    func run(_ request: CommandRequest) async throws -> CommandOutput
    func stream(_ request: CommandRequest) -> AsyncThrowingStream<String, Error>
    func cancelAll()
}

extension CommandRunning {
    public func cancelAll() {}
}

public struct ProcessCommandRunner: CommandRunning {
    private let sessions = ProcessSessionRegistry()
    public init() {}

    /// Cancels only subprocesses created by this runner, including children still
    /// winding down after ordinary task cancellation. It never targets the engine.
    public func cancelAll() { sessions.cancelAll() }

    public func run(_ request: CommandRequest) async throws -> CommandOutput {
        let session = ProcessSession(request: request)
        let id = sessions.insert(session)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                session.start { [sessions] result in
                    sessions.remove(id)
                    continuation.resume(with: result)
                }
            }
        } onCancel: {
            session.cancel()
        }
    }

    public func stream(_ request: CommandRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingNewest(64)) { continuation in
            let session = ProcessSession(request: request) { text in
                switch continuation.yield(text) {
                case .enqueued: return true
                case .dropped, .terminated: return false
                @unknown default: return false
                }
            }
            let id = sessions.insert(session)
            continuation.onTermination = { @Sendable _ in session.cancel() }
            session.start { [sessions] result in
                sessions.remove(id)
                switch result {
                case .success(let output) where output.exitCode == 0: continuation.finish()
                case .success(let output):
                    continuation.finish(throwing: DockerError.commandFailed(String(output.stderr.prefix(2_048))))
                case .failure(let error): continuation.finish(throwing: error)
                }
            }
        }
    }
}

private final class ProcessSessionRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var active: [UUID: ProcessSession] = [:]
    private var retiring: [UUID: ProcessSession] = [:]

    func insert(_ session: ProcessSession) -> UUID {
        let id = UUID()
        lock.withLock { active[id] = session }
        return id
    }

    func remove(_ id: UUID) {
        let needsReaping = lock.withLock { () -> Bool in
            guard let session = active.removeValue(forKey: id), session.hasRunningProcess else { return false }
            retiring[id] = session
            return true
        }
        if needsReaping { scheduleReaping(id) }
    }

    func cancelAll() {
        let owned = lock.withLock { Array(active.values) + Array(retiring.values) }
        // Force termination is intentional at application shutdown: delayed work
        // scheduled inside a terminating host process cannot guarantee cleanup.
        owned.forEach { $0.cancel(immediately: true) }
    }

    private func scheduleReaping(_ id: UUID) {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self else { return }
            let remaining = lock.withLock { () -> ProcessSession? in
                guard let session = retiring[id] else { return nil }
                if !session.hasRunningProcess {
                    retiring.removeValue(forKey: id)
                    return nil
                }
                return session
            }
            if let remaining {
                remaining.cancel(immediately: true)
                scheduleReaping(id)
            }
        }
    }
}

/// Foundation Process is bridged onto background queues. All shared state is protected by `lock`.
/// Separate pipe readers avoid the deadlock caused by draining stdout and stderr sequentially.
private final class ProcessSession: @unchecked Sendable {
    private let request: CommandRequest
    private let process = Process()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private let readers = DispatchGroup()
    private let lock = NSLock()
    private var stdout = Data()
    private var stderr = Data()
    private var pendingLine = Data()
    private var pendingErrorLine = Data()
    private var completion: (@Sendable (Result<CommandOutput, Error>) -> Void)?
    private var emit: (@Sendable (String) -> Bool)?
    private var failure: (any Error)?
    private var finished = false
    private var launched = false
    private var timer: DispatchSourceTimer?

    init(request: CommandRequest, emit: (@Sendable (String) -> Bool)? = nil) {
        self.request = request
        self.emit = emit
        process.executableURL = request.executableURL
        process.arguments = request.arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] =
            "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + (environment["PATH"] ?? "")
        environment["LC_ALL"] = "C"
        // Context selection is always an explicit argument; ambient host/TLS overrides must not reroute it.
        for key in ["DOCKER_HOST", "DOCKER_CONTEXT", "DOCKER_TLS_VERIFY", "DOCKER_CERT_PATH"] {
            environment.removeValue(forKey: key)
        }
        process.environment = environment
        readers.enter()
        readers.enter()
    }

    func start(completion: @escaping @Sendable (Result<CommandOutput, Error>) -> Void) {
        let cancelled = lock.withLock { () -> (any Error)? in
            self.completion = completion
            return failure
        }
        if let cancelled {
            finish(.failure(cancelled))
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            process.terminationHandler = { [weak self] process in
                guard let self else { return }
                let status = process.terminationStatus
                readers.notify(queue: .global(qos: .userInitiated)) { [self] in
                    let result = lock.withLock { () -> Result<CommandOutput, Error> in
                        if let failure { return .failure(failure) }
                        return .success(
                            CommandOutput(
                                stdout: String(decoding: stdout, as: UTF8.self),
                                stderr: String(decoding: stderr, as: UTF8.self), exitCode: status))
                    }
                    finish(result)
                }
            }
            do {
                try lock.withLock {
                    if let failure { throw failure }
                    try process.run()
                    launched = true
                }
            } catch {
                finish(.failure(error))
                return
            }
            try? stdoutPipe.fileHandleForWriting.close()
            try? stderrPipe.fileHandleForWriting.close()
            read(stdoutPipe.fileHandleForReading, isError: false)
            read(stderrPipe.fileHandleForReading, isError: true)
            if request.timeout > 0 {
                let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
                timer.schedule(deadline: .now() + request.timeout)
                timer.setEventHandler { [weak self] in self?.abort(DockerError.timedOut) }
                let shouldStart = lock.withLock { () -> Bool in
                    guard !finished else { return false }
                    self.timer = timer
                    return true
                }
                if shouldStart {
                    timer.resume()
                } else {
                    timer.setEventHandler {}
                    timer.resume()
                    timer.cancel()
                }
            }
        }
    }

    var hasRunningProcess: Bool { lock.withLock { launched && process.isRunning } }

    func cancel(immediately: Bool = false) { abort(CancellationError(), immediately: immediately) }

    private func read(_ handle: FileHandle, isError: Bool) {
        DispatchQueue.global(qos: .utility).async { [self] in
            defer {
                flushLine(isError: isError)
                try? handle.close()
                readers.leave()
            }
            do {
                let descriptor = handle.fileDescriptor
                var bytes = [UInt8](repeating: 0, count: 8_192)
                while !lock.withLock({ finished }) {
                    // FileHandle.read(upToCount:) can wait to fill its requested
                    // buffer on macOS. A pipe read must deliver sparse live logs
                    // immediately, without waiting for 8 KiB or child exit.
                    let count = bytes.withUnsafeMutableBytes { buffer in
                        Darwin.read(descriptor, buffer.baseAddress, buffer.count)
                    }
                    if count == 0 { break }
                    if count < 0 {
                        let code = errno
                        if code == EINTR { continue }
                        throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
                    }
                    append(Data(bytes.prefix(count)), isError: isError)
                }
            } catch {
                if !lock.withLock({ finished }) { abort(error) }
            }
        }
    }

    private func append(_ data: Data, isError: Bool) {
        var text: String?
        var handler: (@Sendable (String) -> Bool)?
        let overflow = lock.withLock { () -> Bool in
            guard !finished else { return false }
            if let emit {
                if isError {
                    // stderr also contains ordinary container log records. Keep only a short
                    // diagnostic tail for a failed CLI exit, rather than growing it forever.
                    stderr.append(data)
                    if stderr.count > 4_096 { stderr.removeFirst(stderr.count - 4_096) }
                    pendingErrorLine.append(data)
                    if let end = pendingErrorLine.lastIndex(of: 10) {
                        text = String(decoding: pendingErrorLine[...end], as: UTF8.self)
                        pendingErrorLine.removeSubrange(...end)
                        handler = emit
                    } else if pendingErrorLine.count > 65_536 {
                        return true
                    }
                } else {
                    pendingLine.append(data)
                    if let end = pendingLine.lastIndex(of: 10) {
                        text = String(decoding: pendingLine[...end], as: UTF8.self)
                        pendingLine.removeSubrange(...end)
                        handler = emit
                    } else if pendingLine.count > 65_536 {
                        return true
                    }
                }
            } else if isError {
                guard stdout.count + stderr.count + data.count <= request.outputLimitBytes else { return true }
                stderr.append(data)
            } else {
                guard stdout.count + stderr.count + data.count <= request.outputLimitBytes else { return true }
                stdout.append(data)
            }
            return false
        }
        if overflow { abort(DockerError.outputLimitExceeded) }
        if let text, let handler, !handler(text) { abort(DockerError.outputLimitExceeded) }
    }

    private func flushLine(isError: Bool) {
        let output = lock.withLock { () -> (String, (@Sendable (String) -> Bool))? in
            guard !finished, let emit else { return nil }
            let remaining = isError ? pendingErrorLine : pendingLine
            guard !remaining.isEmpty else { return nil }
            let text = String(decoding: remaining, as: UTF8.self)
            if isError {
                pendingErrorLine.removeAll(keepingCapacity: false)
            } else {
                pendingLine.removeAll(keepingCapacity: false)
            }
            return (text, emit)
        }
        if let (text, handler) = output, !handler(text) { abort(DockerError.outputLimitExceeded) }
    }

    private func abort(_ error: any Error, immediately: Bool = false) {
        let pid = lock.withLock { () -> Int32? in
            guard !finished || immediately else { return nil }
            if failure == nil { failure = error }
            return launched && process.isRunning ? process.processIdentifier : nil
        }
        if let pid, pid > 0 {
            kill(pid, immediately ? SIGKILL : SIGTERM)
            if !immediately {
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5) { [process] in
                    if process.isRunning { kill(pid, SIGKILL) }
                }
            }
        }
        if lock.withLock({ completion != nil }) { finish(.failure(error)) }
    }

    private func finish(_ result: Result<CommandOutput, Error>) {
        let action = lock.withLock {
            () -> ((@Sendable (Result<CommandOutput, Error>) -> Void), DispatchSourceTimer?)? in
            guard !finished, let completion else { return nil }
            finished = true
            self.completion = nil
            emit = nil
            let timer = self.timer
            self.timer = nil
            return (completion, timer)
        }
        guard let (completion, timer) = action else { return }
        timer?.setEventHandler {}
        timer?.cancel()
        // The reader owns its descriptor until its loop exits. Cancellation
        // terminates the child, which closes its pipe writers and wakes read().
        // Closing a descriptor from another thread risks descriptor-reuse races.
        completion(result)
    }
}
