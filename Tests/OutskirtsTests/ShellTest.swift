import Foundation
import Logger
@testable import Shared
import Synchronization
import SystemPackage
import TestShared
import XCTest

//
//  ShellTest.swift
//  Periphery
//
//  Created by Alexander Goodkind on 2026-10-25.
//

final class ShellTest: XCTestCase {
    func testCapturesLargeOutputFromBothStreams() throws {
        let shell = ShellImpl(logger: Logger(quiet: true, verbose: false, colorMode: .never))
        let output = try shell.exec(command(status: 0))
        XCTAssertEqual(output, "stdout:\(String(repeating: "x", count: 262_144)):end")
    }

    func testPreservesBothStreamsOnFailure() throws {
        let shell = ShellImpl(logger: Logger(quiet: true, verbose: false, colorMode: .never))
        let command = command(status: 7)

        XCTAssertThrowsError(try shell.exec(command)) { error in
            guard case let PeripheryError.shellCommandFailed(cmd, status, output) = error else {
                return XCTFail("Expected a shell command failure, received \(error)")
            }

            XCTAssertEqual(cmd, command)
            XCTAssertEqual(status, 7)
            let payload = String(repeating: "x", count: 262_144)
            XCTAssertEqual(output, "stdout:\(payload):end\nstderr:\(payload):end")
        }
    }

    func testInvalidUTF8OnStderr_doesNotFailSuccessfulCommand() throws {
        let shell = ShellImpl(logger: Logger(quiet: true, verbose: false, colorMode: .never))
        let output = try shell.exec(["/bin/sh", "-c", "printf 'caf\\351' >&2; printf ok"])
        XCTAssertEqual(output, "ok")
    }

    func testInvalidUTF8_failedCommandKeepsOutput() {
        let shell = ShellImpl(logger: Logger(quiet: true, verbose: false, colorMode: .never))

        XCTAssertThrowsError(try shell.exec(["/bin/sh", "-c", "printf 'caf\\351 broke' >&2; exit 3"])) { error in
            guard case let PeripheryError.shellCommandFailed(_, status, output) = error else {
                return XCTFail("Expected a shell command failure, received \(error)")
            }

            XCTAssertEqual(status, 3)
            XCTAssertEqual(output, "caf\u{FFFD} broke")
        }
    }

    func testSignalTermination_isReportedAsSignal() {
        let shell = ShellImpl(logger: Logger(quiet: true, verbose: false, colorMode: .never))

        XCTAssertThrowsError(try shell.exec(["/bin/sh", "-c", "echo partial; kill -9 $$"])) { error in
            guard case let PeripheryError.shellCommandKilled(_, signal, output) = error else {
                return XCTFail("Expected a killed shell command, received \(error)")
            }

            XCTAssertEqual(signal, SIGKILL)
            XCTAssertEqual(output, "partial")
            XCTAssertTrue(error.localizedDescription.contains("killed by signal 9 (SIGKILL), possibly out of memory"))
        }
    }

    /// git runs in the store of the shell, so that a signal stops it with the other processes.
    func testGitRun_isStoppedWithTheOtherProcesses() throws {
        let directory = try makeTemporaryDirectory("outskirts-git-store")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let pidFile = directory.appendingPathComponent("sleep")
        // A grace period far beyond the bound below: stopping in time proves the signal stopped git, not the kill.
        let store = ShellProcessStore(gracePeriod: .seconds(120))
        DispatchQueue.global().async {
            let alias = "alias.wait=!sleep 60 & echo $! > '\(pidFile.path)'; wait"
            _ = try? Git.run(["-c", alias, "wait"], in: FilePath(directory.path), store: store)
        }
        let sleep = try XCTUnwrap(waitForPid(in: pidFile))
        addTeardownBlock { kill(sleep, SIGKILL) }
        XCTAssertEqual(store.count, 1)

        let stopped = Date()
        store.stopRunning(signal: SIGTERM)
        XCTAssertTrue(store.isStopping)
        XCTAssertLessThan(Date().timeIntervalSince(stopped), 60, "git was not stopped by the signal")
        XCTAssertTrue(waitUntil { ProcessLiveness.isGone(sleep) }, "the process started by git outlived the signal")
    }

    /// The signal reaches every process the command started, not only the one the store launched.
    func testStopRunning_stopsTheChildrenOfTheProcess() throws {
        let directory = try makeTemporaryDirectory("outskirts-stop-group")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let pidFile = directory.appendingPathComponent("child")
        let store = ShellProcessStore()
        DispatchQueue.global().async {
            let alias = "alias.spawn=!sleep 30 & echo $! > '\(pidFile.path)'; wait"
            _ = try? Git.run(["-c", alias, "spawn"], in: FilePath(directory.path), store: store)
        }
        let child = try XCTUnwrap(waitForPid(in: pidFile))
        addTeardownBlock { kill(child, SIGKILL) }

        store.stopRunning(signal: SIGTERM)

        XCTAssertTrue(waitUntil { ProcessLiveness.isGone(child) }, "the child of the process outlived the signal")
    }

    /// A process that ignores the signal is killed after a delay instead of holding the exit forever.
    func testStopRunning_killsAProcessThatIgnoresTheSignal() throws {
        let directory = try makeTemporaryDirectory("outskirts-stop-ignored")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let pidFile = directory.appendingPathComponent("child")
        let store = ShellProcessStore(gracePeriod: .seconds(1))
        DispatchQueue.global().async {
            let alias = "alias.stubborn=!trap '' INT TERM; echo $$ > '\(pidFile.path)'; sleep 30"
            _ = try? Git.run(["-c", alias, "stubborn"], in: FilePath(directory.path), store: store)
        }
        let child = try XCTUnwrap(waitForPid(in: pidFile))
        addTeardownBlock { kill(child, SIGKILL) }

        let stopped = Date()
        store.stopRunning(signal: SIGTERM)

        XCTAssertLessThan(Date().timeIntervalSince(stopped), 5)
        XCTAssertTrue(waitUntil { ProcessLiveness.isGone(child) }, "the process that ignores the signal is still running")
    }

    /// A zombie left by a non-reaping PID 1 counts as gone, read from `/proc/<pid>/stat`.
    func testStatFields_readsStateAndGroupAfterTheLastParenthesis() {
        XCTAssertEqual(ProcessLiveness.statFields("123 (a b) c) Z 1 456 456 0")?.state, "Z")
        XCTAssertEqual(ProcessLiveness.statFields("123 (a b) c) Z 1 456 456 0")?.group, 456)
        XCTAssertEqual(ProcessLiveness.statFields("7 (sleep) S 1 7 7 0")?.state, "S")
        XCTAssertNil(ProcessLiveness.statFields("7 sleep S 1 7"))
        XCTAssertNil(ProcessLiveness.statFields("7 (sleep) S 1"))
    }

    /// Once the store is stopping, a command started afterwards is not launched.
    func testRunAfterStopRunning_doesNotLaunchTheCommand() throws {
        let directory = try makeTemporaryDirectory("outskirts-stop-late")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let marker = directory.appendingPathComponent("launched")
        let store = ShellProcessStore()
        store.stopRunning(signal: SIGTERM)

        DispatchQueue.global().async {
            _ = try? Git.run(["-c", "alias.mark=!touch '\(marker.path)'", "mark"], in: FilePath(directory.path), store: store)
        }

        XCTAssertFalse(waitUntil(timeout: 2) { FileManager.default.fileExists(atPath: marker.path) })
    }

    /// Children inherit the default action of the signals the shell ignores to handle them itself.
    func testExec_childDoesNotInheritTheIgnoredSignals() {
        let shell = ShellImpl(logger: Logger(quiet: true, verbose: false, colorMode: .never))

        XCTAssertThrowsError(try shell.exec(["/bin/sh", "-c", "kill -TERM $$; echo survived"])) { error in
            guard case let PeripheryError.shellCommandKilled(_, signal, _) = error else {
                return XCTFail("Expected a killed shell command, received \(error)")
            }

            XCTAssertEqual(signal, SIGTERM)
        }
    }

    /// A process left running by the command, holding its output open, does not keep the command from returning.
    func testExec_returnsWhenTheCommandExitsBeforeItsChildren() throws {
        let shell = ShellImpl(logger: Logger(quiet: true, verbose: false, colorMode: .never))
        let started = Date()

        let output = try shell.exec(["/bin/sh", "-c", "sleep 8 & echo $!; echo done"])

        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
        let lines = output.split(separator: "\n")
        if let child = lines.first.flatMap({ pid_t($0) }) {
            kill(child, SIGKILL)
        }
        XCTAssertEqual(lines.last, "done")
    }

    /// The command reads an empty standard input, never the one of outskirts, where a prompt would wait unseen.
    func testExec_doesNotShareTheStandardInput() throws {
        var fds: [Int32] = [0, 0]
        XCTAssertEqual(pipe(&fds), 0)
        let savedInput = dup(STDIN_FILENO)
        XCTAssertEqual(dup2(fds[0], STDIN_FILENO), STDIN_FILENO)
        close(fds[0])
        var inputOpen = true
        defer {
            if inputOpen {
                close(fds[1])
            }
            dup2(savedInput, STDIN_FILENO)
            close(savedInput)
        }

        let shell = ShellImpl(logger: Logger(quiet: true, verbose: false, colorMode: .never))
        let result = Mutex<Result<String, Error>?>(nil)
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            let output = Result { try shell.exec(["/bin/sh", "-c", "read line; echo read $?"]) }
            result.withLock { $0 = output }
            done.signal()
        }

        let finished = done.wait(timeout: .now() + 5) == .success
        if !finished {
            close(fds[1])
            inputOpen = false
            done.wait()
        }
        XCTAssertTrue(finished, "the command waited on the standard input of outskirts")
        XCTAssertEqual(try result.withLock { try $0?.get() }, "read 1\n")
    }

    /// A parent that ignores `SIGCHLD` does not keep the store from reaping the commands.
    func testRun_reapsTheCommandWhenSIGCHLDWasIgnored() throws {
        let previous = signal(SIGCHLD, SIG_IGN)
        defer { signal(SIGCHLD, previous) }

        let store = ShellProcessStore()
        let output = try store.run("/bin/sh", ["-c", "printf ok; exit 3"], environment: [:])

        XCTAssertEqual(output.status, 3)
        XCTAssertEqual(output.reason, .exit)
        XCTAssertEqual(String(bytes: output.standardOutput, encoding: .utf8), "ok")
    }

    func testPassesArgumentsLiterallyWithoutAShell() throws {
        let shell = ShellImpl(logger: Logger(quiet: true, verbose: false, colorMode: .never))
        let marker = uniqueTemporaryURL("periphery-shell")
        let hostile = "$(touch \(marker.path)) `touch \(marker.path)` 'single' \"double\" a\\b; echo injected"

        let output = try shell.exec(["printf", "%s|%s", hostile, "two words"])

        XCTAssertEqual(output, "\(hostile)|two words")
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }

    func testResolvesExecutableFromPath() throws {
        let url = try ShellImpl.executableURL(for: "printf", environment: ["PATH": "/nonexistent::/usr/bin:/bin"])
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: url.path))
        XCTAssertEqual(url.lastPathComponent, "printf")
        XCTAssertEqual(try ShellImpl.executableURL(for: "/bin/echo", environment: [:]).path, "/bin/echo")
    }

    func testThrowsWhenExecutableIsNotInPath() {
        XCTAssertThrowsError(try ShellImpl.executableURL(for: "periphery-no-such-tool", environment: ["PATH": "/usr/bin"])) { error in
            guard case let PeripheryError.executableNotFound(name, searchPath) = error else {
                return XCTFail("Expected executableNotFound, received \(error)")
            }

            XCTAssertEqual(name, "periphery-no-such-tool")
            XCTAssertEqual(searchPath, ["/usr/bin"])
        }
    }

    func testShellQuotedRendersCommandForDisplay() {
        XCTAssertEqual(
            ["xcodebuild", "-scheme", "My $(App)", "it's", ""].shellQuoted,
            "xcodebuild -scheme 'My $(App)' 'it'\\''s' ''"
        )
    }

    private func waitForPid(in file: URL) -> pid_t? {
        var pid: pid_t?
        _ = waitUntil {
            pid = (try? String(contentsOf: file, encoding: .utf8)).flatMap { pid_t($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            return pid != nil
        }
        return pid
    }

    private func waitUntil(timeout: TimeInterval = 10, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            usleep(10000)
        }
        return condition()
    }

    private func command(status: Int) -> [String] {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/ShellOutput.sh")
        return ["/bin/bash", fixture.path, String(status)]
    }
}
