import Foundation

/// Explicit locales also select the language bundle, so pure text tests do not
/// depend on the test host's preferred language. Unsupported languages use English.
enum AppLocalization {
    nonisolated static func bundle(for locale: Locale) -> Bundle {
        let language = locale.language.languageCode?.identifier == "ko" ? "ko" : "en"
        guard let path = Bundle.main.path(forResource: language, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return .main }
        return bundle
    }
}
