import Foundation

public final class ConfigStore {
    public let configDirectoryURL: URL
    public let configURL: URL
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let supportURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("TextFix", isDirectory: true)
        configDirectoryURL = supportURL
        configURL = supportURL.appendingPathComponent("config.json", isDirectory: false)
    }

    public func ensureConfigDirectory() throws {
        try fileManager.createDirectory(at: configDirectoryURL, withIntermediateDirectories: true)
    }

    public func load() -> AppConfig {
        do {
            try ensureConfigDirectory()
        } catch {
            return .defaultConfig
        }

        guard fileManager.fileExists(atPath: configURL.path) else {
            try? save(.defaultConfig)
            return .defaultConfig
        }

        guard
            let data = try? Data(contentsOf: configURL),
            let object = try? JSONSerialization.jsonObject(with: data),
            let dictionary = object as? [String: Any]
        else {
            try? save(.defaultConfig)
            return .defaultConfig
        }

        var migrated = dictionary
        var shouldSave = false

        for key in AppConfig.jsonKeys where migrated[key] == nil {
            shouldSave = true
        }

        if let legacyAPIKey = migrated["api_key"] as? String {
            let openAIKey = (migrated["openai_api_key"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if openAIKey.isEmpty {
                migrated["openai_api_key"] = legacyAPIKey
            }
            migrated.removeValue(forKey: "api_key")
            shouldSave = true
        }

        let config = AppConfig.from(dictionary: migrated)
        if shouldSave {
            try? save(config)
        }
        return config
    }

    public func save(_ config: AppConfig) throws {
        try ensureConfigDirectory()
        let data = try JSONSerialization.data(withJSONObject: config.jsonObject(), options: [.prettyPrinted, .sortedKeys])
        try data.appendingNewline().write(to: configURL, options: [.atomic])
    }
}

private extension Data {
    func appendingNewline() -> Data {
        var copy = self
        copy.append(0x0A)
        return copy
    }
}
