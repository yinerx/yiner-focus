import Foundation

public struct CSVRowIssue: Equatable, Sendable {
    public var line: Int
    public var message: String

    public init(line: Int, message: String) {
        self.line = line
        self.message = message
    }
}

public struct ImportOutcome: Equatable, Sendable {
    public var added: Int
    public var skipped: Int
    public var failed: Int
    public var errors: [CSVRowIssue]
    public var createdTags: [String]

    public init(added: Int, skipped: Int, failed: Int, errors: [CSVRowIssue], createdTags: [String]) {
        self.added = added
        self.skipped = skipped
        self.failed = failed
        self.errors = errors
        self.createdTags = createdTags
    }

    public var summary: String {
        var parts = ["新增 \(added) 条", "跳过 \(skipped) 条", "无法解析 \(failed) 条"]
        if !createdTags.isEmpty {
            parts.append("新建标签 \(createdTags.joined(separator: "、"))")
        }
        if let first = errors.first {
            parts.append("例如第 \(first.line) 行：\(first.message)")
        }
        return parts.joined(separator: "。")
    }
}

public struct StoreSnapshot: Codable, Equatable, Sendable {
    public var version: Int
    public var sessions: [FocusSession]
    public var tags: [FocusTag]
    public var settings: FocusSettings
    public var webRules: [WebRule]
    public var appRules: [AppRule]
    public var engine: FocusEngine

    public init(
        version: Int = 1,
        sessions: [FocusSession],
        tags: [FocusTag],
        settings: FocusSettings,
        webRules: [WebRule],
        appRules: [AppRule],
        engine: FocusEngine
    ) {
        self.version = version
        self.sessions = sessions
        self.tags = tags
        self.settings = settings
        self.webRules = webRules
        self.appRules = appRules
        self.engine = engine
    }

    public static func fresh(now: Date = Date()) -> StoreSnapshot {
        let settings = FocusSettings.standard
        return StoreSnapshot(
            version: 1,
            sessions: [],
            tags: TagLibrary.defaults,
            settings: settings,
            webRules: [],
            appRules: [],
            engine: FocusEngine(settings: settings, now: now)
        )
    }

    /// 相同 ID 跳过，不覆盖本机已有记录。解析失败的行记下来，其它行继续。
    public mutating func importFlowCSV(_ text: String, timeZone: TimeZone) -> ImportOutcome {
        let rows = parseCSV(text)
        guard let header = rows.first else {
            return ImportOutcome(
                added: 0, skipped: 0, failed: 1,
                errors: [CSVRowIssue(line: 1, message: "文件是空的")],
                createdTags: []
            )
        }
        let expected = YinerDefaults.csvHeader.split(separator: ",").map(String.init)
        guard header == expected else {
            return ImportOutcome(
                added: 0, skipped: 0, failed: 1,
                errors: [CSVRowIssue(line: 1, message: "表头与导出格式不一致")],
                createdTags: []
            )
        }

        var added = 0
        var skipped = 0
        var failed = 0
        var errors: [CSVRowIssue] = []
        var createdTags: [String] = []
        var seen = Set(sessions.map(\.id))

        for (offset, fields) in rows.dropFirst().enumerated() {
            let line = offset + 2
            if fields.allSatisfy({ $0.isEmpty }) { continue }
            do {
                let session = try parseSession(fields, timeZone: timeZone)
                if seen.contains(session.id) {
                    skipped += 1
                    continue
                }
                if !session.tag.isEmpty && TagLibrary.ensure(name: session.tag, tags: &tags) {
                    createdTags.append(session.tag)
                }
                sessions.append(session)
                seen.insert(session.id)
                added += 1
            } catch let issue as RowParseError {
                failed += 1
                errors.append(CSVRowIssue(line: line, message: issue.message))
            } catch {
                failed += 1
                errors.append(CSVRowIssue(line: line, message: "无法解析"))
            }
        }

        return ImportOutcome(
            added: added,
            skipped: skipped,
            failed: failed,
            errors: errors,
            createdTags: createdTags
        )
    }

    public func exportFlowCSV(timeZone: TimeZone) -> String {
        let lines = sessions.filter(shouldExport).map { exportLine($0, timeZone: timeZone) }
        return ([YinerDefaults.csvHeader] + lines).joined(separator: "\n")
    }
}

private struct RowParseError: Error {
    var message: String
}

private func shouldExport(_ session: FocusSession) -> Bool {
    guard session.status == .completed else { return false }
    switch session.kind {
    case .focus, .preserved:
        return true
    case .shortBreak, .longBreak:
        return YinerDefaults.exportBreaks
    }
}

private func exportLine(_ session: FocusSession, timeZone: TimeZone) -> String {
    let typeValue: String
    switch session.kind {
    case .focus:
        typeValue = YinerDefaults.exportedFocusType
    case .shortBreak:
        typeValue = YinerDefaults.storedShortBreakType
    case .longBreak:
        typeValue = YinerDefaults.storedLongBreakType
    case .preserved:
        typeValue = session.typeRaw
    }
    let completed = session.completedAt.map { WallTime.format(date: $0, timeZone: timeZone) } ?? ""
    return [
        quoteCSV(typeValue),
        quoteCSV(session.title),
        quoteCSV(session.tag),
        formatHMS(session.durationNetSeconds),
        formatHMS(session.durationGrossSeconds),
        WallTime.format(date: session.startedAt, timeZone: timeZone),
        completed,
        quoteCSV(session.id)
    ].joined(separator: ",")
}

private func quoteCSV(_ text: String) -> String {
    "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
}

private func parseSession(_ fields: [String], timeZone: TimeZone) throws -> FocusSession {
    guard fields.count == 8 else {
        throw RowParseError(message: "列数不是 8")
    }
    let typeRaw = fields[0]
    guard !typeRaw.isEmpty else { throw RowParseError(message: "缺少 Type") }
    let title = fields[1]
    let tag = fields[2]
    guard let net = parseHMS(fields[3]) else { throw RowParseError(message: "净时长格式不对") }
    guard let gross = parseHMS(fields[4]) else { throw RowParseError(message: "含中断时长格式不对") }
    guard let started = WallTime.parse(fields[5], timeZone: timeZone) else {
        throw RowParseError(message: "开始时间格式不对")
    }
    let completedText = fields[6]
    let completed: Date?
    if completedText.isEmpty {
        completed = nil
    } else if let date = WallTime.parse(completedText, timeZone: timeZone) {
        completed = date
    } else {
        throw RowParseError(message: "完成时间格式不对")
    }
    let identifier = fields[7].trimmingCharacters(in: .whitespacesAndNewlines)
    guard !identifier.isEmpty else { throw RowParseError(message: "缺少 ID") }

    let kind: SessionKind
    if typeRaw == YinerDefaults.exportedFocusType {
        kind = .focus
    } else if typeRaw == YinerDefaults.storedShortBreakType {
        kind = .shortBreak
    } else if typeRaw == YinerDefaults.storedLongBreakType {
        kind = .longBreak
    } else {
        kind = .preserved
    }
    let status: SessionStatus = completed == nil ? .incomplete : .completed
    return FocusSession(
        id: identifier,
        kind: kind,
        typeRaw: typeRaw,
        title: title,
        tag: tag,
        durationNetSeconds: net,
        durationGrossSeconds: gross,
        startedAt: started,
        completedAt: completed,
        status: status,
        cycleLengthSnapshot: nil
    )
}

func parseCSV(_ text: String) -> [[String]] {
    var rows: [[String]] = []
    var row: [String] = []
    var field = ""
    var inQuotes = false
    let characters = Array(text)
    var index = 0
    while index < characters.count {
        let character = characters[index]
        if inQuotes {
            if character == "\"" {
                if index + 1 < characters.count && characters[index + 1] == "\"" {
                    field.append("\"")
                    index += 2
                    continue
                }
                inQuotes = false
                index += 1
                continue
            }
            field.append(character)
            index += 1
            continue
        }
        if character == "\"" {
            inQuotes = true
            index += 1
            continue
        }
        if character == "," {
            row.append(field)
            field = ""
            index += 1
            continue
        }
        if character == "\n" || character == "\r" {
            if character == "\r", index + 1 < characters.count, characters[index + 1] == "\n" {
                index += 1
            }
            row.append(field)
            field = ""
            if !(row.count == 1 && row[0].isEmpty) {
                rows.append(row)
            }
            row = []
            index += 1
            continue
        }
        field.append(character)
        index += 1
    }
    if inQuotes || !field.isEmpty || !row.isEmpty {
        row.append(field)
        if !(row.count == 1 && row[0].isEmpty) {
            rows.append(row)
        }
    }
    if let first = rows.first, first.first?.hasPrefix("\u{feff}") == true {
        var cleaned = first
        cleaned[0] = String(cleaned[0].dropFirst())
        rows[0] = cleaned
    }
    return rows
}
