import Foundation

public enum StoreLoad: Equatable, Sendable {
    case fresh
    case loaded(StoreSnapshot)
    case failed(String)
}

public enum LocalStore {
    public static func storeURL(in applicationSupport: URL) -> URL {
        applicationSupport
            .appendingPathComponent(YinerDefaults.storeFolderName, isDirectory: true)
            .appendingPathComponent(YinerDefaults.storeFileName)
    }

    public static func load(from url: URL) -> StoreLoad {
        guard FileManager.default.fileExists(atPath: url.path) else { return .fresh }
        do {
            let data = try Data(contentsOf: url)
            let snapshot = try decoder().decode(StoreSnapshot.self, from: data)
            return .loaded(snapshot)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    public static func save(_ snapshot: StoreSnapshot, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder().encode(snapshot)
        try data.write(to: url, options: .atomic)
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

public enum WidgetSummaryFile {
    public static func fileURL(in container: URL) -> URL {
        container.appendingPathComponent(YinerDefaults.widgetFileName)
    }

    public static func save(_ payload: TodayWidgetPayload, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        try data.write(to: url, options: .atomic)
    }

    public static func load(from url: URL) -> TodayWidgetPayload? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(TodayWidgetPayload.self, from: data)
    }
}
