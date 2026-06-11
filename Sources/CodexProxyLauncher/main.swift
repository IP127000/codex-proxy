import AppKit
import Foundation
import os

private let launcherBundleID = "com.local.codex-proxy"
private let codexBundleID = "com.openai.codex"
private let codexPath = "/Applications/Codex.app"

private let proxy = ProxySettings(host: "127.0.0.1", port: 10808)

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

        for app in runningCodexApps {
            logger.info("Terminating Codex pid=\(app.processIdentifier, privacy: .public)")
            if !app.terminate() {
                app.forceTerminate()
            }
        }

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            let stillRunning = runningCodexApps.contains { !$0.isTerminated }
            if !stillRunning { break }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }

        for app in runningCodexApps where !app.isTerminated {
            logger.info("Force terminating Codex pid=\(app.processIdentifier, privacy: .public)")
            app.forceTerminate()
        }

        await terminateResidualCodexHelpers()
        try? await Task.sleep(nanoseconds: 700_000_000)
    }

    private func terminateResidualCodexHelpers() async {
        let patterns = [
            "^/Applications/Codex\\.app/"
        ]

        for pattern in patterns {
            await runProcess("/usr/bin/pkill", arguments: ["-TERM", "-f", pattern])
        }

        try? await Task.sleep(nanoseconds: 500_000_000)

        for pattern in patterns {
            await runProcess("/usr/bin/pkill", arguments: ["-KILL", "-f", pattern])
        }
    }

    private func runProcess(_ executable: String, arguments: [String]) async {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                // If the target process is already gone, there is nothing else to do.
            }
        }.value
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
