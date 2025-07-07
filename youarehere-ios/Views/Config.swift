import Foundation

fileprivate func loadConfigValue(_ key: String) -> String {
    guard let url = Bundle.main.url(forResource: "Config", withExtension: "plist"),
          let data = try? Data(contentsOf: url),
          let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
          let value = plist[key] as? String else {
        fatalError("Missing or invalid Config.plist value for \(key)")
    }
    return value
}

struct Config {
    static var proxyBaseURL: String { loadConfigValue("ProxyBaseURL") }
    static var claudeClientAPIKey: String { loadConfigValue("ClaudeClientAPIKey") }
} 