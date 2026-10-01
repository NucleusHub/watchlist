import Foundation

/// Where tapping "Open" takes a title.
enum OpenLinks {
    static func target(for item: Item, settings: WatchlistSettings) -> OpenTarget {
        item.openTarget ?? settings.openDefault(for: item.type) ?? OpenTarget()
    }

    static func url(for item: Item, settings: WatchlistSettings) -> URL? {
        url(target(for: item, settings: settings), title: item.title, year: item.year)
    }

    static func url(_ target: OpenTarget, title: String, year: Int?) -> URL? {
        let year = year.map(String.init) ?? ""
        let string: String
        switch target.type {
        case .tmdb: string = "https://www.themoviedb.org/search?query=\(enc(title))"
        case .csfd: string = "https://www.csfd.cz/hledat/?q=\(enc(title))"
        case .google: string = "https://www.google.com/search?q=\(enc("\(title) \(year)".trimmingCharacters(in: .whitespaces)))"
        case .custom:
            let tpl = target.customUrl.trimmingCharacters(in: .whitespaces)
            guard !tpl.isEmpty else { return nil }
            string = tpl.replacingOccurrences(of: "{title}", with: enc(format(title, target.titleFormat)))
                .replacingOccurrences(of: "{year}", with: enc(year))
        }
        return URL(string: string)
    }

    /// `encodeURIComponent`.
    static func enc(_ s: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")
        return s.trimmingCharacters(in: .whitespaces).addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    static func format(_ title: String, _ format: OpenTarget.TitleFormat) -> String {
        let raw = title.trimmingCharacters(in: .whitespaces)
        let words = raw.components(separatedBy: CharacterSet.letters.union(.decimalDigits).inverted).filter { !$0.isEmpty }
        func cap(_ w: String) -> String { w.prefix(1).uppercased() + w.dropFirst().lowercased() }
        switch format {
        case .raw: return raw
        case .lower: return raw.lowercased()
        case .kebab: return words.joined(separator: "-").lowercased()
        case .snake: return words.joined(separator: "_").lowercased()
        case .pascal: return words.map(cap).joined()
        case .camel: return words.enumerated().map { $0.offset == 0 ? $0.element.lowercased() : cap($0.element) }.joined()
        }
    }
}
