import Foundation

enum ConfigManager {
    static let configDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/TextFix")
    static let configPath = configDir.appendingPathComponent("config.json")

    static func load() -> TextFixConfig {
        guard FileManager.default.fileExists(atPath: configPath.path) else {
            let config = TextFixConfig.default
            save(config)
            return config
        }

        do {
            let data = try Data(contentsOf: configPath)
            let config = try JSONDecoder().decode(TextFixConfig.self, from: data)
            return config
        } catch {
            return TextFixConfig.default
        }
    }

    static func save(_ config: TextFixConfig) {
        do {
            try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(config)
            try data.write(to: configPath, options: .atomic)
        } catch {
            print("Failed to save config: \(error)")
        }
    }
}
