import Foundation

public enum AppLanguage: String, CaseIterable {
    case korean = "ko", english = "en"
}

public enum L10n {
    public static var language: AppLanguage {
        if let flag = CommandLine.arguments.first(where: { $0.hasPrefix("--language=") }),
           let selected = AppLanguage(rawValue: String(flag.dropFirst(11))) { return selected }
        if let selected = AppLanguage(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "") { return selected }
        return Locale.preferredLanguages.first?.hasPrefix("ko") == true ? .korean : .english
    }
    private static let catalogs: [AppLanguage: [String: String]] = {
        var values: [AppLanguage: [String: String]] = [:]
        // Packaged apps use the standard resource directory; SwiftPM tests use Bundle.module.
        let packaged = Bundle.main.resourceURL?.appendingPathComponent("CodexSwitch_SwitchCore.bundle")
        let bundle = packaged.flatMap { Bundle(url: $0) } ?? Bundle.module
        for language in AppLanguage.allCases {
            guard let url = bundle.url(forResource: language.rawValue, withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let catalog = try? JSONDecoder().decode([String: String].self, from: data) else { continue }
            values[language] = catalog
        }
        return values
    }()
    public static func text(_ key: String, language: AppLanguage = language) -> String {
        catalogs[language]?[key] ?? catalogs[.english]?[key] ?? key
    }
    public static func format(_ key: String, _ arguments: String...) -> String {
        String(format: text(key), arguments: arguments)
    }
    public static func catalog(for language: AppLanguage) -> [String: String] { catalogs[language] ?? [:] }
}
