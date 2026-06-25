import AppKit
import Darwin
import Foundation
import os

private let launcherBundleID = "com.local.codex-proxy"
private let codexBundleID = "com.openai.codex"
private let codexPath = "/Applications/Codex.app"

private let proxy = ProxySettings(host: "127.0.0.1", port: 10808)
private let gracefulShutdownTimeout: TimeInterval = 5
private let residualShutdownTimeout: TimeInterval = 3

private final class AppDelegate: NSObject, NSApplicationDelegate {
    private let launcher = CodexProxyLauncher()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            do {
                try await launcher.restartCodexThroughProxy()
                NSApp.terminate(nil)
            } catch {
                showFailure(error)
                NSApp.terminate(nil)
            }
        }
    }

    private func showFailure(_ error: Error) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "codex-proxy 启动失败"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}

private final class CodexProxyLauncher {
    private let logger = Logger(subsystem: launcherBundleID, category: "launcher")

    @MainActor
    func restartCodexThroughProxy() async throws {
        let codexURL = try validateCodexApp()

        logger.info("Stopping Codex before relaunch")
        await stopRunningCodex(targetURL: codexURL)

        logger.info("Opening Codex with HTTP(S) and SOCKS5 proxy settings")
        _ = try await openCodex(at: codexURL)
    }

    private func validateCodexApp() throws -> URL {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: codexPath, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw LauncherError.codexAppMissing(codexPath)
        }
        return URL(fileURLWithPath: codexPath, isDirectory: true)
    }

    @MainActor
    private func stopRunningCodex(targetURL: URL) async {
        let targetPath = targetURL.standardizedFileURL.path
        let runningCodexApps = NSWorkspace.shared.runningApplications.filter { app in
            if app.bundleIdentifier == codexBundleID {
                return true
            }
            return app.bundleURL?.standardizedFileURL.path == targetPath
        }
        let codexRootPIDs = Set(runningCodexApps.map { Int32($0.processIdentifier) })
        let knownRelatedPIDs = await collectCodexRelatedProcessIDs(rootPIDs: codexRootPIDs)

        for app in runningCodexApps {
            logger.info("Terminating Codex pid=\(app.processIdentifier, privacy: .public)")
            if !app.terminate() {
                app.forceTerminate()
            }
        }

        let deadline = Date().addingTimeInterval(gracefulShutdownTimeout)
        while Date() < deadline {
            let stillRunning = runningCodexApps.contains { !$0.isTerminated }
            if !stillRunning { break }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }

        for app in runningCodexApps where !app.isTerminated {
            logger.info("Force terminating Codex pid=\(app.processIdentifier, privacy: .public)")
            app.forceTerminate()
        }

        await terminateResidualCodexHelpers(previouslySeenPIDs: knownRelatedPIDs, rootPIDs: codexRootPIDs)
        try? await Task.sleep(nanoseconds: 700_000_000)
    }

    private func terminateResidualCodexHelpers(previouslySeenPIDs: Set<Int32>, rootPIDs: Set<Int32>) async {
        var residualPIDs = previouslySeenPIDs
        residualPIDs.formUnion(await collectCodexRelatedProcessIDs(rootPIDs: rootPIDs))
        residualPIDs.remove(Int32(ProcessInfo.processInfo.processIdentifier))
        residualPIDs = residualPIDs.filter { isProcessRunning($0) }

        if residualPIDs.isEmpty {
            logger.info("No residual Codex helper processes found")
            return
        }

        for pid in residualPIDs.sorted() {
            logger.info("Terminating residual Codex helper pid=\(pid, privacy: .public)")
            signalProcess(pid, signal: SIGTERM)
        }

        await waitUntilGone(residualPIDs, timeout: residualShutdownTimeout)

        let stubbornPIDs = residualPIDs.filter { isProcessRunning($0) }
        for pid in stubbornPIDs.sorted() {
            logger.info("Force terminating residual Codex helper pid=\(pid, privacy: .public)")
            signalProcess(pid, signal: SIGKILL)
        }
    }

    private func collectCodexRelatedProcessIDs(rootPIDs: Set<Int32>) async -> Set<Int32> {
        let processes = await processSnapshot()
        let directMatches = Set(processes.compactMap { process -> Int32? in
            if rootPIDs.contains(process.pid) || isCodexOwnedCommand(process.command) {
                return process.pid
            }
            return nil
        })

        return directMatches.union(descendants(of: directMatches, in: processes))
    }

    private func descendants(of rootPIDs: Set<Int32>, in processes: [ProcessSnapshot]) -> Set<Int32> {
        var childrenByParent: [Int32: [Int32]] = [:]
        for process in processes {
            childrenByParent[process.ppid, default: []].append(process.pid)
        }

        var result = Set<Int32>()
        var queue = Array(rootPIDs)

        while let pid = queue.popLast() {
            for childPID in childrenByParent[pid, default: []] where !result.contains(childPID) {
                result.insert(childPID)
                queue.append(childPID)
            }
        }

        return result
    }

    private func isCodexOwnedCommand(_ command: String) -> Bool {
        let standardizedCodexPath = URL(fileURLWithPath: codexPath, isDirectory: true).standardizedFileURL.path
        if command.hasPrefix(standardizedCodexPath + "/") {
            return true
        }

        let codexComputerUseFragments = [
            ".codex/computer-use/Codex Computer Use.app/",
            ".codex/plugins/cache/openai-bundled/computer-use/",
            ".codex/plugins/cache/openai-bundled/record-and-replay/"
        ]
        if command.contains("Codex Computer Use.app/"), codexComputerUseFragments.contains(where: command.contains) {
            return true
        }

        return command.contains("SkyComputerUseService")
            || command.contains("SkyComputerUseClient")
            || command.contains("CUALockScreenGuardian")
    }

    private func processSnapshot() async -> [ProcessSnapshot] {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/ps")
            process.arguments = ["axo", "pid=,ppid=,command="]
            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = Pipe()

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                return []
            }

            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                return []
            }

            return output.split(separator: "\n").compactMap { line in
                ProcessSnapshot(String(line))
            }
        }.value
    }

    private func signalProcess(_ pid: Int32, signal: Int32) {
        _ = Darwin.kill(pid_t(pid), signal)
    }

    private func isProcessRunning(_ pid: Int32) -> Bool {
        Darwin.kill(pid_t(pid), 0) == 0 || errno == EPERM
    }

    private func waitUntilGone(_ pids: Set<Int32>, timeout: TimeInterval) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if pids.allSatisfy({ !isProcessRunning($0) }) {
                return
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
    }

    @MainActor
    private func openCodex(at codexURL: URL) async throws -> NSRunningApplication {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.environment = launchEnvironment()
        configuration.arguments = launchArguments()

        return try await withCheckedThrowingContinuation { continuation in
            NSWorkspace.shared.openApplication(at: codexURL, configuration: configuration) { app, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let app {
                    continuation.resume(returning: app)
                } else {
                    continuation.resume(throwing: LauncherError.openReturnedNoApplication)
                }
            }
        }
    }

    private func launchEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment

        environment["HTTP_PROXY"] = proxy.httpProxyURL
        environment["HTTPS_PROXY"] = proxy.httpProxyURL
        environment["ALL_PROXY"] = proxy.socks5ProxyURL
        environment["SOCKS_PROXY"] = proxy.socks5ProxyURL

        environment["http_proxy"] = proxy.httpProxyURL
        environment["https_proxy"] = proxy.httpProxyURL
        environment["all_proxy"] = proxy.socks5ProxyURL
        environment["socks_proxy"] = proxy.socks5ProxyURL

        environment["npm_config_proxy"] = proxy.httpProxyURL
        environment["npm_config_https_proxy"] = proxy.httpProxyURL

        environment["NO_PROXY"] = "localhost,127.0.0.1,::1"
        environment["no_proxy"] = "localhost,127.0.0.1,::1"
        environment["MallocNanoZone"] = "0"
        return environment
    }

    private func launchArguments() -> [String] {
        [
            "--proxy-server=\(proxy.chromiumProxyServer)",
            "--proxy-bypass-list=localhost;127.0.0.1;::1"
        ]
    }
}

private struct ProcessSnapshot {
    let pid: Int32
    let ppid: Int32
    let command: String

    init?(_ line: String) {
        let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count == 3,
              let pidValue = Int32(parts[0]),
              let ppidValue = Int32(parts[1])
        else {
            return nil
        }

        let command = String(parts[2]).trimmingCharacters(in: .whitespaces)
        guard !command.isEmpty else {
            return nil
        }

        self.pid = pidValue
        self.ppid = ppidValue
        self.command = command
    }
}

private struct ProxySettings {
    let host: String
    let port: Int

    var httpProxyURL: String {
        "http://\(host):\(port)"
    }

    var socks5ProxyURL: String {
        "socks5://\(host):\(port)"
    }

    var chromiumProxyServer: String {
        "http=\(host):\(port);https=\(host):\(port);socks=socks5://\(host):\(port)"
    }
}

private enum LauncherError: LocalizedError {
    case codexAppMissing(String)
    case openReturnedNoApplication

    var errorDescription: String? {
        switch self {
        case .codexAppMissing(let path):
            return "找不到 Codex.app：\(path)"
        case .openReturnedNoApplication:
            return "系统没有返回已启动的 Codex 进程"
        }
    }
}

let app = NSApplication.shared
private let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
