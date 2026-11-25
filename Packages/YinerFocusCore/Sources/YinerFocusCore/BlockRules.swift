import Foundation

public enum ShieldVerdict: Equatable, Sendable {
    /// 当前不是「专注进行中」，屏蔽规则不生效。
    case shieldingOff
    case leave
    case replace
}

public struct ShieldInput: Equatable, Sendable {
    public var urlString: String
    public var rules: [String]
    public var mode: WebListMode
    public var phase: SessionPhase
    public var runState: RunState
    public var blockPageFileName: String

    public init(
        urlString: String,
        rules: [String],
        mode: WebListMode,
        phase: SessionPhase,
        runState: RunState,
        blockPageFileName: String = YinerDefaults.blockPageFileName
    ) {
        self.urlString = urlString
        self.rules = rules
        self.mode = mode
        self.phase = phase
        self.runState = runState
        self.blockPageFileName = blockPageFileName
    }
}

public func shieldVerdict(_ input: ShieldInput) -> ShieldVerdict {
    let active = input.phase == .focus && input.runState == .running
    if !active {
        return .shieldingOff
    }
    if isOwnBlockPage(input.urlString, fileName: input.blockPageFileName) || isBrowserInternal(input.urlString) {
        return .leave
    }
    guard isHTTP(input.urlString) else { return .leave }
    let matched = input.rules.contains { ruleMatches($0, url: input.urlString) }
    switch input.mode {
    case .block:
        return matched ? .replace : .leave
    case .allow:
        return matched ? .leave : .replace
    }
}

public func ruleMatches(_ rule: String, url: String) -> Bool {
    let trimmed = rule.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }
    if trimmed.first == YinerDefaults.exactRulePrefix {
        let body = String(trimmed.dropFirst())
        return exactEqual(body, url)
    }
    return url.range(of: trimmed, options: .caseInsensitive) != nil
}

/// 已选浏览器的收起文案。多于一个时用列表顺序里的第一个名称，加上其余数量。
public func browserSelectionSummary(selected: [KnownBrowser]) -> String {
    let ordered = KnownBrowser.allCases.filter { selected.contains($0) }
    guard let first = ordered.first else { return "未选择" }
    if ordered.count == 1 { return first.displayName }
    return "\(first.displayName) + \(ordered.count - 1)"
}

public func shouldHideApplication(
    bundleID: String?,
    ownBundleID: String,
    blockedBundleIDs: Set<String>,
    phase: SessionPhase,
    runState: RunState
) -> Bool {
    guard phase == .focus, runState == .running else { return false }
    guard let bundleID, !bundleID.isEmpty else { return false }
    if bundleID == ownBundleID { return false }
    return blockedBundleIDs.contains(bundleID)
}

public enum WebRuleEdit {
    /// 空字符串或已有同文（不区分大小写）时不添加。
    public static func add(_ raw: String, to rules: inout [WebRule]) -> WebRule? {
        let pattern = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty else { return nil }
        if rules.contains(where: { $0.pattern.compare(pattern, options: .caseInsensitive) == .orderedSame }) {
            return nil
        }
        let rule = WebRule(pattern: pattern)
        rules.append(rule)
        return rule
    }
}

public enum AppRuleEdit {
    /// 已存在同一 Bundle ID 时只更新显示名，返回 false。
    @discardableResult
    public static func add(bundleID: String, displayName: String, to rules: inout [AppRule]) -> Bool {
        let identifier = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty else { return false }
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let index = rules.firstIndex(where: { $0.bundleID == identifier }) {
            rules[index].displayName = name.isEmpty ? identifier : name
            return false
        }
        rules.append(AppRule(bundleID: identifier, displayName: name.isEmpty ? identifier : name))
        return true
    }
}

private func exactEqual(_ ruleBody: String, _ url: String) -> Bool {
    normalizeExact(ruleBody).caseInsensitiveCompare(normalizeExact(url)) == .orderedSame
}

private func normalizeExact(_ text: String) -> String {
    var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.hasSuffix("/") {
        value.removeLast()
    }
    return value
}

private func isHTTP(_ urlString: String) -> Bool {
    guard let scheme = URL(string: urlString)?.scheme?.lowercased() else { return false }
    return scheme == "http" || scheme == "https"
}

private func isOwnBlockPage(_ urlString: String, fileName: String) -> Bool {
    let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let url = URL(string: trimmed), url.scheme?.lowercased() == "file" else { return false }
    return url.lastPathComponent.compare(fileName, options: .caseInsensitive) == .orderedSame
}

private func isBrowserInternal(_ urlString: String) -> Bool {
    let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return true }
    guard let scheme = URL(string: trimmed)?.scheme?.lowercased() else {
        return trimmed.lowercased().hasPrefix("about:")
    }
    let internalSchemes: Set<String> = [
        "about", "chrome", "chrome-extension", "chrome-untrusted",
        "safari-resource", "safari-web-extension", "arc", "edge", "brave", "devtools"
    ]
    return internalSchemes.contains(scheme)
}
