import AppKit
import Darwin
import Foundation
import YinerFocusCore

/// 用系统自带的 osascript 读已选浏览器的标签。浏览器没在运行时不发脚本，避免把它拉起来。
final class BrowserBlocker {
    var onUpdate: (([KnownBrowser: String?]) -> Void)?
    private var busy = false

    func poll(snapshot: StoreSnapshot, blockPageURL: URL?) {
        guard !busy else { return }
        let settings = snapshot.settings
        let engine = snapshot.engine
        guard engine.phase == .focus, engine.runState == .running else { return }
        let rules = snapshot.webRules.map(\.pattern)
        if settings.webMode == .block && rules.isEmpty { return }
        let selected = settings.enabledBrowsers
        guard !selected.isEmpty else { return }

        guard let blockPageURL else {
            var missing: [KnownBrowser: String?] = [:]
            for browser in selected {
                missing[browser] = "找不到本地拦截页。"
            }
            onUpdate?(missing)
            return
        }

        let running = selected.filter { browser in
            !NSRunningApplication.runningApplications(withBundleIdentifier: browser.bundleIdentifier).isEmpty
        }
        let destination = blockPageURL.absoluteString + "?mode=" + settings.webMode.rawValue
        let mode = settings.webMode
        busy = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            var messages: [KnownBrowser: String?] = [:]
            for browser in selected where !running.contains(browser) {
                messages[browser] = nil
            }
            for browser in running {
                messages[browser] = self.scan(
                    browser,
                    rules: rules,
                    mode: mode,
                    destination: destination
                )
            }
            DispatchQueue.main.async {
                self.busy = false
                self.onUpdate?(messages)
            }
        }
    }

    private func scan(
        _ browser: KnownBrowser,
        rules: [String],
        mode: WebListMode,
        destination: String
    ) -> String? {
        switch runOSA(readScript(browser.appleScriptName)) {
        case .failure(let message):
            return message
        case .success(let output):
            var replacements: [(Int, Int)] = []
            for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
                let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                guard parts.count >= 3, let window = Int(parts[0]), let tab = Int(parts[1]) else { continue }
                let url = parts.dropFirst(2).joined(separator: "\t")
                let verdict = shieldVerdict(ShieldInput(
                    urlString: url,
                    rules: rules,
                    mode: mode,
                    phase: .focus,
                    runState: .running
                ))
                if verdict == .replace {
                    replacements.append((window, tab))
                }
            }
            guard !replacements.isEmpty else { return nil }
            switch runOSA(writeScript(browser.appleScriptName, replacements: replacements, destination: destination)) {
            case .failure(let message):
                return message
            case .success:
                return nil
            }
        }
    }
}

private enum OSAResult {
    case success(String)
    case failure(String)
}

private final class PipeBuffer {
    private let lock = NSLock()
    private var storage = Data()

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        storage.append(chunk)
        lock.unlock()
    }

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

private func runOSA(_ source: String) -> OSAResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-e", source]
    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr
    let outBuffer = PipeBuffer()
    let errBuffer = PipeBuffer()
    stdout.fileHandleForReading.readabilityHandler = { handle in
        outBuffer.append(handle.availableData)
    }
    stderr.fileHandleForReading.readabilityHandler = { handle in
        errBuffer.append(handle.availableData)
    }
    do {
        try process.run()
    } catch {
        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil
        return .failure("没有能启动自动化脚本。")
    }
    let deadline = Date().addingTimeInterval(YinerDefaults.blockScriptTimeoutSeconds)
    while process.isRunning && Date() < deadline {
        Thread.sleep(forTimeInterval: 0.05)
    }
    if process.isRunning {
        process.terminate()
        let killDeadline = Date().addingTimeInterval(0.4)
        while process.isRunning && Date() < killDeadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil
        return .failure("读取超时。这次没有改动它的标签。")
    }
    process.waitUntilExit()
    stdout.fileHandleForReading.readabilityHandler = nil
    stderr.fileHandleForReading.readabilityHandler = nil
    outBuffer.append(stdout.fileHandleForReading.readDataToEndOfFile())
    errBuffer.append(stderr.fileHandleForReading.readDataToEndOfFile())
    let out = String(data: outBuffer.data, encoding: .utf8) ?? ""
    let err = String(data: errBuffer.data, encoding: .utf8) ?? ""
    if process.terminationStatus == 0 {
        return .success(out)
    }
    let lower = err.lowercased()
    if err.contains("-600") || lower.contains("not running") || lower.contains("isn't running") || lower.contains("未运行") {
        return .success("")
    }
    if err.contains("-1743") || err.contains("-1744") || lower.contains("not authorized") || lower.contains("不允许") {
        return .failure("系统没有允许银耳专注控制它。请到系统设置 › 隐私与安全性 › 自动化里打开。")
    }
    return .failure("暂时读不到它的标签。如果刚升级过浏览器，稍后再试。")
}

private func readScript(_ applicationName: String) -> String {
    """
    tell application "\(applicationName)"
      set chunks to {}
      set wi to 0
      repeat with w in windows
        set wi to wi + 1
        set ti to 0
        repeat with t in tabs of w
          set ti to ti + 1
          try
            set u to URL of t as text
          on error
            set u to ""
          end try
          set end of chunks to ((wi as text) & tab & (ti as text) & tab & u)
        end repeat
      end repeat
      set AppleScript's text item delimiters to linefeed
      return chunks as text
    end tell
    """
}

private func writeScript(
    _ applicationName: String,
    replacements: [(Int, Int)],
    destination: String
) -> String {
    let target = escapeAppleScript(destination)
    var lines = ["tell application \"\(applicationName)\""]
    for item in replacements {
        lines.append("set URL of tab \(item.1) of window \(item.0) to \"\(target)\"")
    }
    lines.append("end tell")
    return lines.joined(separator: "\n")
}

private func escapeAppleScript(_ text: String) -> String {
    text
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
}
