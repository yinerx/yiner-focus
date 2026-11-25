import Foundation

public enum TagEditError: Error, Equatable {
    case emptyName
    case duplicateName
    case missing
}

public enum TagLibrary {
    public static let defaults: [FocusTag] = YinerDefaults.defaultTags.enumerated().map { index, item in
        FocusTag(id: "tag-\(index)-\(item.name)", name: item.name, colorHex: item.colorHex, sortIndex: index)
    }

    public static func sorted(_ tags: [FocusTag]) -> [FocusTag] {
        tags.sorted { $0.sortIndex < $1.sortIndex }
    }

    @discardableResult
    public static func add(name: String, colorHex: String, tags: inout [FocusTag]) throws -> FocusTag {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TagEditError.emptyName }
        if tags.contains(where: { $0.name == trimmed }) { throw TagEditError.duplicateName }
        let next = (tags.map(\.sortIndex).max() ?? -1) + 1
        let tag = FocusTag(id: UUID().uuidString, name: trimmed, colorHex: normalizeHex(colorHex), sortIndex: next)
        tags.append(tag)
        return tag
    }

    public static func rename(
        id: String,
        to newName: String,
        tags: inout [FocusTag],
        sessions: inout [FocusSession]
    ) throws {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw TagEditError.emptyName }
        guard let index = tags.firstIndex(where: { $0.id == id }) else { throw TagEditError.missing }
        if tags.contains(where: { $0.id != id && $0.name == name }) { throw TagEditError.duplicateName }
        let previous = tags[index].name
        tags[index].name = name
        guard previous != name else { return }
        for sessionIndex in sessions.indices where sessions[sessionIndex].tag == previous {
            sessions[sessionIndex].tag = name
        }
    }

    public static func remove(id: String, tags: inout [FocusTag]) {
        tags.removeAll { $0.id == id }
    }

    public static func move(id: String, direction: Int, tags: inout [FocusTag]) {
        var ordered = sorted(tags)
        guard let index = ordered.firstIndex(where: { $0.id == id }) else { return }
        let target = index + direction
        guard ordered.indices.contains(target) else { return }
        ordered.swapAt(index, target)
        for position in ordered.indices {
            ordered[position].sortIndex = position
        }
        tags = ordered
    }

    public static func setColor(id: String, colorHex: String, tags: inout [FocusTag]) {
        guard let index = tags.firstIndex(where: { $0.id == id }) else { return }
        tags[index].colorHex = normalizeHex(colorHex)
    }

    /// 导入时按名称补标签。已存在则返回 false。
    @discardableResult
    public static func ensure(name: String, tags: inout [FocusTag]) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if tags.contains(where: { $0.name == trimmed }) { return false }
        let palette = YinerDefaults.defaultTags.map(\.colorHex) + YinerDefaults.extraTagColors
        let color = palette[tags.count % palette.count]
        _ = try? add(name: trimmed, colorHex: color, tags: &tags)
        return true
    }

    public static func normalizeHex(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        let hex = text.uppercased()
        guard hex.count == 6, hex.allSatisfy({ $0.isHexDigit }) else { return "#7A6A58" }
        return "#\(hex)"
    }
}
