import Foundation
import Logger
import Synchronization
#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import CStdio
    import Glibc
#endif

/// How a command ended and what it printed.
struct ShellOutput {
    /// The exit status, or the signal that killed the command.
    let status: Int32
    let reason: Process.TerminationReason
    let standardOutput: Data
    let standardError: Data
}

/// Runs the commands of the shell and of git, each in a session of its own, so that a signal stops every process a
/// command started, not only the one launched here.
final class ShellProcessStore: Sendable {
    /// The store of the shell and of git, which the signal handlers of the shell stop.
    static let shared = ShellProcessStore()

    private struct State {
        /// The running commands, whose process ID is also the ID of their session and process group.
        var groups: Set<pid_t> = []
        var stopping = false
    }

    private let state = Mutex(State())
    private let gracePeriod: Duration

    /// How long the outputs are still read once the command has exited, while a process it left running holds them.
    private static let drainPeriod = Duration.seconds(1)

    /// `gracePeriod` is how long the processes have to exit after the signal before they are killed. Restores the
    /// default action of `SIGCHLD`: ignored, as a parent may leave it, the commands would be reaped by the system and
    /// waiting for them would fail.
    init(gracePeriod: Duration = .seconds(5)) {
        self.gracePeriod = gracePeriod
        signal(SIGCHLD, SIG_DFL)
    }

    /// Whether the running processes have been told to stop, in which case the program is about to exit.
    var isStopping: Bool {
        state.withLock(\.stopping)
    }

    /// The number of running commands.
    var count: Int {
        state.withLock(\.groups.count)
    }

    /// Interrupts (`SIGINT`) or terminates (`SIGTERM`) every process of the running commands and waits for them to
    /// exit, killing those left once the grace period has passed. No command is launched afterwards.
    func stopRunning(signal: Int32) {
        let groups = state.withLock { state in
            state.stopping = true
            return state.groups
        }
        for group in groups {
            kill(-group, signal)
        }
        guard !Self.waitUntilGone(groups, timeout: gracePeriod) else { return }

        for group in groups {
            kill(-group, SIGKILL)
        }
        _ = Self.waitUntilGone(groups, timeout: .seconds(1))
    }

    /// Runs the executable with both outputs captured. Once the store is stopping, the command is not launched, or its
    /// result not returned: the call never returns, as the signal handler is about to exit with the status of the signal.
    func run(_ executable: String, _ arguments: [String], environment: [String: String]) throws -> ShellOutput {
        // Launched and recorded at once, so that a signal either finds the command or keeps it from being launched,
        // and so that no other command is launched while the ends of the pipes are not marked close-on-exec yet.
        let launched = try state.withLock { state -> Launch? in
            guard !state.stopping else { return nil }

            let launch = try Self.launch(executable, arguments, environment: environment)
            state.groups.insert(launch.pid)
            return launch
        }
        guard let launched else {
            ShellImpl.parkUntilExit()
        }

        let pid = launched.pid
        var termination: (Int32, Process.TerminationReason)?
        let outputs = Result { try Self.collect([launched.output, launched.error], of: pid, termination: &termination) }
        let exited = Result { try termination ?? Self.waitForExit(of: pid) }
        state.withLock { _ = $0.groups.remove(pid) }
        if isStopping {
            ShellImpl.parkUntilExit()
        }

        let (status, reason) = try exited.get()
        let output = try outputs.get()
        return ShellOutput(status: status, reason: reason, standardOutput: output[0], standardError: output[1])
    }

    // MARK: - Private

    #if canImport(Darwin)
        private static let spawnFlags = POSIX_SPAWN_SETSID | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_CLOEXEC_DEFAULT
    #else
        /// `POSIX_SPAWN_SETSID` of glibc 2.26 and later is a GNU extension, written out as Swift may not import it.
        private static let spawnFlags = 0x80 | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK
    #endif

    /// The signals that the command gets back to their default action, which ignoring them here would otherwise pass on.
    private static let defaultSignals = [SIGHUP, SIGINT, SIGQUIT, SIGPIPE, SIGTERM, SIGCHLD]

    /// Launches the command in a new session, whose process group a signal reaches as a whole, with the default action
    /// of the signals and no blocked signal, whatever the thread that launches it ignores or blocks. A session rather
    /// than a process group alone: without a controlling terminal, a tool that would prompt on it fails instead of
    /// being stopped for reading the terminal from the background.
    private static func spawn(
        _ executable: String,
        _ arguments: [String],
        environment: [String: String],
        output: Int32,
        error: Int32
    ) throws -> pid_t {
        #if canImport(Darwin)
            var actions: posix_spawn_file_actions_t?
            var attributes: posix_spawnattr_t?
        #else
            var actions = posix_spawn_file_actions_t()
            var attributes = posix_spawnattr_t()
        #endif
        try check(posix_spawn_file_actions_init(&actions))
        defer { posix_spawn_file_actions_destroy(&actions) }
        try check(posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0))
        try check(posix_spawn_file_actions_adddup2(&actions, output, STDOUT_FILENO))
        try check(posix_spawn_file_actions_adddup2(&actions, error, STDERR_FILENO))

        try check(posix_spawnattr_init(&attributes))
        defer { posix_spawnattr_destroy(&attributes) }
        var defaults = sigset_t()
        sigemptyset(&defaults)
        for signal in defaultSignals {
            sigaddset(&defaults, signal)
        }
        var mask = sigset_t()
        sigemptyset(&mask)
        try check(posix_spawnattr_setsigdefault(&attributes, &defaults))
        try check(posix_spawnattr_setsigmask(&attributes, &mask))
        try check(posix_spawnattr_setflags(&attributes, Int16(spawnFlags)))

        let argv = ([executable] + arguments).map { strdup($0) } + [nil]
        let envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            for pointer in argv + envp {
                free(pointer)
            }
        }

        var pid: pid_t = 0
        try check(posix_spawn(&pid, executable, &actions, &attributes, argv, envp))
        return pid
    }

    /// A launched command and the read ends of the pipes of its standard output and error.
    private struct Launch {
        let pid: pid_t
        let output: Int32
        let error: Int32
    }

    /// Launches the command with its outputs on new pipes, whose write ends are closed here once it has them.
    private static func launch(_ executable: String, _ arguments: [String], environment: [String: String]) throws -> Launch {
        let outputPipe = try makePipe()
        defer { close(outputPipe.write) }
        let errorPipe: (read: Int32, write: Int32)
        do {
            errorPipe = try makePipe()
        } catch {
            close(outputPipe.read)
            throw error
        }
        defer { close(errorPipe.write) }

        do {
            let pid = try spawn(executable, arguments, environment: environment, output: outputPipe.write, error: errorPipe.write)
            return Launch(pid: pid, output: outputPipe.read, error: errorPipe.read)
        } catch {
            close(outputPipe.read)
            close(errorPipe.read)
            throw error
        }
    }

    /// A pipe whose ends are closed in every launched command but the one they are given to.
    private static func makePipe() throws -> (read: Int32, write: Int32) {
        var fds: [Int32] = [-1, -1]
        #if os(Linux)
            // Atomic, where `pipe` then `fcntl` would leave the ends inheritable for a moment.
            let result = outskirts_pipe_cloexec(&fds)
        #else
            let result = pipe(&fds)
        #endif
        guard result == 0 else { throw posixError(errno) }

        #if !os(Linux)
            for fd in fds where fcntl(fd, F_SETFD, FD_CLOEXEC) == -1 {
                let error = posixError(errno)
                for fd in fds {
                    close(fd)
                }
                throw error
            }
        #endif
        return (fds[0], fds[1])
    }

    /// Reads both outputs at once, so that neither fills up while the command waits to write to the other, until they
    /// close or, once the command has exited, until the drain period has passed: a process the command left running
    /// may hold them open for as long as it lives. Reaps the command if it exits meanwhile.
    private static func collect(
        _ fds: [Int32],
        of pid: pid_t,
        termination: inout (Int32, Process.TerminationReason)?
    ) throws -> [Data] {
        defer {
            for fd in fds {
                close(fd)
            }
        }

        var outputs = fds.map { _ in Data() }
        var open = fds.map { _ in true }
        var drainDeadline: ContinuousClock.Instant?
        var buffer = [UInt8](repeating: 0, count: 65536)

        while open.contains(true) {
            if termination == nil, let exited = try exitIfExited(of: pid) {
                termination = exited
                drainDeadline = .now + drainPeriod
            }
            if let drainDeadline, ContinuousClock.now >= drainDeadline {
                break
            }

            let indices = fds.indices.filter { open[$0] }
            var polled = indices.map { pollfd(fd: fds[$0], events: Int16(POLLIN), revents: 0) }
            guard poll(&polled, nfds_t(polled.count), 100) != -1 else {
                guard errno == EINTR else { throw posixError(errno) }

                continue
            }

            for (index, entry) in zip(indices, polled) where entry.revents != 0 {
                let count = read(entry.fd, &buffer, buffer.count)
                if count > 0 {
                    outputs[index].append(contentsOf: buffer[..<count])
                } else if count == 0 {
                    open[index] = false
                } else if errno != EINTR, errno != EAGAIN {
                    throw posixError(errno)
                }
            }
        }

        return outputs
    }

    /// Reaps the command: its exit status, or the signal that killed it.
    private static func waitForExit(of pid: pid_t) throws -> (Int32, Process.TerminationReason) {
        var status: Int32 = 0
        while waitpid(pid, &status, 0) == -1 {
            guard errno == EINTR else { throw posixError(errno) }
        }
        return termination(from: status)
    }

    /// Reaps the command if it has exited, without waiting.
    private static func exitIfExited(of pid: pid_t) throws -> (Int32, Process.TerminationReason)? {
        var status: Int32 = 0
        while true {
            switch waitpid(pid, &status, WNOHANG) {
            case pid:
                return termination(from: status)
            case 0:
                return nil
            default:
                guard errno == EINTR else { throw posixError(errno) }
            }
        }
    }

    private static func termination(from status: Int32) -> (Int32, Process.TerminationReason) {
        let signal = status & 0x7F
        return signal == 0 ? ((status >> 8) & 0xFF, .exit) : (signal, .uncaughtSignal)
    }

    /// Whether every process of the groups exited within the timeout.
    private static func waitUntilGone(_ groups: Set<pid_t>, timeout: Duration) -> Bool {
        let deadline = ContinuousClock.now + timeout
        while true {
            if groups.allSatisfy({ kill(-$0, 0) == -1 && errno == ESRCH }) {
                return true
            }
            if ContinuousClock.now >= deadline {
                return false
            }
            usleep(10000)
        }
    }

    private static func check(_ result: Int32) throws {
        guard result == 0 else { throw posixError(result) }
    }

    private static func posixError(_ code: Int32) -> Error {
        POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
    }
}

public protocol Shell: Sendable {
    @discardableResult
    func exec(_ args: [String]) throws -> String
}

public final class ShellImpl: Shell {
    private let logger: ContextualLogger
    private let store: ShellProcessStore
    // outskirts:ignore - assign-only on purpose: holding the sources keeps the signal handlers installed
    /// Only kept alive here, never read; the `Mutex` makes the class `Sendable` on Linux, where
    /// `DispatchSourceSignal` is not.
    private let signalSources: Mutex<[DispatchSourceSignal]>

    /// The signals among `SIGHUP` and `SIGQUIT` that were ignored when the program started, as under `nohup`: read
    /// once, before the first shell ignores them to handle them itself.
    private static let ignoredAtLaunch = Set([SIGHUP, SIGQUIT].filter { signalNumber in
        let previous = signal(signalNumber, SIG_IGN)
        signal(signalNumber, previous)
        return unsafeBitCast(previous, to: Int.self) == unsafeBitCast(SIG_IGN, to: Int.self)
    })

    /// `sigintHandler` runs when `SIGINT`, `SIGTERM`, `SIGHUP` or `SIGQUIT` is received, before the running processes
    /// are stopped with the same signal: they run in sessions of their own, out of reach of the terminal. The program
    /// then exits with the conventional status of the signal, 128 plus its number: 130 for `SIGINT`, 143 for `SIGTERM`,
    /// 129 for `SIGHUP`, 131 for `SIGQUIT`. A `SIGHUP` or `SIGQUIT` ignored at launch, as under `nohup`, stays ignored.
    public required init(logger: Logger, sigintHandler: @escaping @Sendable () -> Void = {}) {
        self.logger = logger.contextualized(with: "shell")
        store = .shared

        let sources = [SIGINT, SIGTERM, SIGHUP, SIGQUIT].compactMap { [store] signalNumber -> DispatchSourceSignal? in
            guard !Self.ignoredAtLaunch.contains(signalNumber) else { return nil }

            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .global())
            source.setEventHandler {
                sigintHandler()
                store.stopRunning(signal: signalNumber)
                exit(128 + signalNumber)
            }
            source.resume()
            return source
        }
        signalSources = Mutex(sources)
    }

    @discardableResult
    public func exec(_ args: [String]) throws -> String {
        let (status, reason, stdout, stderr) = try exec(args)

        if reason == .exit, status == 0 {
            return stdout
        }

        let output = [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n").trimmed
        if reason == .uncaughtSignal {
            throw PeripheryError.shellCommandKilled(cmd: args, signal: status, output: output)
        }
        throw PeripheryError.shellCommandFailed(cmd: args, status: status, output: output)
    }

    // MARK: - Private

    private func exec(_ cmd: [String]) throws -> (Int32, Process.TerminationReason, String, String) {
        guard let executable = cmd.first else {
            throw PeripheryError.executableNotFound(name: "", searchPath: [])
        }

        let environment = ProcessInfo.processInfo.environment
        let executableURL = try Self.executableURL(for: executable, environment: environment)

        logger.debug(cmd.shellQuoted)

        let result = try store.run(executableURL.path, Array(cmd.dropFirst()), environment: environment)

        // Decoded leniently: a stray non UTF-8 byte, such as a Latin-1 path in a compiler warning, must neither
        // fail a successful command nor hide the output of a failed one.
        // swiftlint:disable optional_data_string_conversion
        let standardOutput = String(decoding: result.standardOutput, as: UTF8.self)
        let standardError = String(decoding: result.standardError, as: UTF8.self)
        // swiftlint:enable optional_data_string_conversion

        return (result.status, result.reason, standardOutput, standardError)
    }

    static func parkUntilExit() -> Never {
        while true {
            sleep(60)
        }
    }

    /// Resolves the executable of a command without a shell: a name containing a slash is used as a path,
    /// any other name is looked up in the `PATH` of the given environment.
    static func executableURL(for name: String, environment: [String: String]) throws -> URL {
        if name.contains("/") {
            return URL(fileURLWithPath: name)
        }

        let searchPath = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
            .filter { !$0.isEmpty }

        for directory in searchPath {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent(name)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
               !isDirectory.boolValue,
               FileManager.default.isExecutableFile(atPath: candidate.path)
            {
                return candidate
            }
        }

        throw PeripheryError.executableNotFound(name: name, searchPath: searchPath)
    }
}

public extension [String] {
    /// A human-readable, shell-quoted rendering of a command, for display only. Commands are never run through a shell.
    var shellQuoted: String {
        map(\.shellQuotedArgument).joined(separator: " ")
    }
}

public extension String {
    /// The string as a single shell word: unchanged if it only contains safe characters, single-quoted otherwise.
    var shellQuotedArgument: String {
        let safeCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@%+=:,./_-")
        if !isEmpty, unicodeScalars.allSatisfy({ safeCharacters.contains($0) }) {
            return self
        }
        return "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
