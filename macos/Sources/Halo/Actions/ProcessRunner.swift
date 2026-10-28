import Foundation
import Synchronization

/// How a child process ended.
nonisolated struct ProcessResult: Sendable {
    var status: Int32 = -1
    var stdout = ""
    var stderr = ""
    /// The process outlived its timeout and was stopped.
    var timedOut = false
    /// Set when the process could not be started at all.
    var launchError: String?

    var succeeded: Bool { launchError == nil && !timedOut && status == 0 }

    /// The first non-empty line of `text`, trimmed and shortened to fit a toast.
    static func firstLine(of text: String, limit: Int = 120) -> String? {
        let line = text.split(whereSeparator: \.isNewline)
            .lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        guard let line else { return nil }
        return line.count > limit ? String(line.prefix(limit - 1)) + "…" : line
    }
}

/// Runs command-line tools without blocking the caller.
///
/// stdin is /dev/null, stdout and stderr are drained concurrently (a full 64 KiB pipe would
/// otherwise stall the child), and the child gets SIGTERM at the timeout, then SIGKILL 2 s later.
nonisolated enum ProcessRunner {
    @concurrent
    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval,
                    workingDirectory: URL? = nil) async -> ProcessResult {
        await withCheckedContinuation { (continuation: CheckedContinuation<ProcessResult, Never>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardInput = FileHandle.nullDevice
            if let workingDirectory { process.currentDirectoryURL = workingDirectory }
            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            let run = ProcessRun(continuation, outputs: [outPipe.fileHandleForReading, errPipe.fileHandleForReading])
            outPipe.fileHandleForReading.readabilityHandler = { run.read($0, isStdout: true) }
            errPipe.fileHandleForReading.readabilityHandler = { run.read($0, isStdout: false) }
            process.terminationHandler = { run.exited(status: $0.terminationStatus) }

            do {
                try process.run()
            } catch {
                run.failedToLaunch(error.localizedDescription)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                guard process.isRunning, run.markTimedOut() else { return }
                process.terminate()
                DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                    if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                }
            }
        }
    }
}

/// Collects one child's output and resumes the caller once it has exited and both pipes are drained.
nonisolated private final class ProcessRun: Sendable {
    private struct State {
        var stdout = Data()
        var stderr = Data()
        var stdoutOpen = true
        var stderrOpen = true
        var exitStatus: Int32?
        var timedOut = false
        var finished = false
    }

    /// Output beyond this is dropped; actions only ever show a line of it.
    private static let outputLimit = 1 << 20
    /// After exit, how long to wait for the pipes to close (a background grandchild can hold them open).
    private static let drainGrace: TimeInterval = 1

    private let state = Mutex(State())
    private let once: OnceContinuation<ProcessResult>
    private let outputs: [FileHandle]

    init(_ continuation: CheckedContinuation<ProcessResult, Never>, outputs: [FileHandle]) {
        self.once = OnceContinuation(continuation)
        self.outputs = outputs
    }

    func read(_ handle: FileHandle, isStdout: Bool) {
        let chunk = handle.availableData
        if chunk.isEmpty {
            handle.readabilityHandler = nil
            state.withLock { s in
                if isStdout { s.stdoutOpen = false } else { s.stderrOpen = false }
            }
            finishIfReady(force: false)
            return
        }
        state.withLock { s in
            if isStdout, s.stdout.count < Self.outputLimit { s.stdout.append(chunk) }
            if !isStdout, s.stderr.count < Self.outputLimit { s.stderr.append(chunk) }
        }
    }

    func exited(status: Int32) {
        state.withLock { $0.exitStatus = status }
        finishIfReady(force: false)
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.drainGrace) { self.finishIfReady(force: true) }
    }

    /// Records the timeout; false if the process already exited.
    func markTimedOut() -> Bool {
        state.withLock { s in
            guard s.exitStatus == nil else { return false }
            s.timedOut = true
            return true
        }
    }

    func failedToLaunch(_ message: String) {
        state.withLock { $0.finished = true }
        stopReading()
        once.resume(returning: ProcessResult(launchError: message))
    }

    private func finishIfReady(force: Bool) {
        let result: ProcessResult? = state.withLock { s in
            guard !s.finished, let status = s.exitStatus, force || (!s.stdoutOpen && !s.stderrOpen) else { return nil }
            s.finished = true
            return ProcessResult(status: status,
                                 stdout: String(decoding: s.stdout, as: UTF8.self),
                                 stderr: String(decoding: s.stderr, as: UTF8.self),
                                 timedOut: s.timedOut)
        }
        guard let result else { return }
        if force { stopReading() }
        once.resume(returning: result)
    }

    private func stopReading() {
        for handle in outputs { handle.readabilityHandler = nil }
    }
}

/// Resumes a continuation exactly once, from whichever callback gets there first.
nonisolated final class OnceContinuation<T: Sendable>: Sendable {
    private let continuation: Mutex<CheckedContinuation<T, Never>?>

    init(_ continuation: CheckedContinuation<T, Never>) {
        self.continuation = Mutex(continuation)
    }

    func resume(returning value: T) {
        let pending = continuation.withLock { stored -> CheckedContinuation<T, Never>? in
            let taken = stored
            stored = nil
            return taken
        }
        pending?.resume(returning: value)
    }
}

/// Runs blocking work (Accessibility IPC, Apple Event preflights) on a global queue so the main
/// thread and the cooperative pool stay free.
nonisolated enum Background {
    /// The result of `work`, or nil if it has not finished within `timeout` (it then keeps running
    /// to completion, but nobody waits for it).
    @concurrent
    static func run<T: Sendable>(timeout: TimeInterval, _ work: @escaping @Sendable () -> T) async -> T? {
        await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
            let once = OnceContinuation(continuation)
            DispatchQueue.global(qos: .userInitiated).async { once.resume(returning: work()) }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { once.resume(returning: nil) }
        }
    }
}

extension Background {
    /// Accessibility work aimed at the app with `pid`. A request to one of Halo's own windows is
    /// answered in-process, on the calling thread, and AppKit then requires the main thread, so
    /// that work runs on the main actor; requests to other apps run in the background with a
    /// timeout, so a hung app can't freeze Halo.
    @MainActor
    static func runAX<T: Sendable>(pid: pid_t, timeout: TimeInterval, _ work: @escaping @Sendable () -> T) async -> T? {
        if pid == ProcessInfo.processInfo.processIdentifier { return work() }
        return await run(timeout: timeout, work)
    }
}
