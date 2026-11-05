import Foundation

/// Lingua dell'interfaccia. Le traduzioni stanno in Resources/strings.json (lo stesso file della
/// versione Windows): la chiave è il testo inglese, `{0}`, `{1}`… sono i valori da inserire.
/// Per aggiungere o correggere una lingua basta modificare quel file.
enum Lang {
    static let supported = ["en", "it", "es", "fr", "de", "pt", "ru", "ja", "ko", "zh"]

    /// Prima lingua preferita del sistema che sia tra quelle supportate (altrimenti inglese).
    static var code: String = {
        for pref in Locale.preferredLanguages {
            let base = String(pref.lowercased().prefix(2))
            if supported.contains(base) { return base }
        }
        return "en"
    }()

    static var isItalian: Bool { code == "it" }

    /// Lingua usata per date e numeri: quella del sistema se coincide con l'interfaccia, altrimenti l'interfaccia.
    static var locale: Locale {
        let sys = Locale.preferredLanguages.first ?? "en"
        return sys.lowercased().hasPrefix(code) ? Locale(identifier: sys) : Locale(identifier: code)
    }

    static var table: [String: String] = load(code)

    static func load(_ code: String, from url: URL? = nil) -> [String: String] {
        guard code != "en",
              let url = url ?? Bundle.main.url(forResource: "strings", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let all = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let langs = all["translations"] as? [String: [String: String]]
        else { return [:] }
        return langs[code] ?? [:]
    }

    /// Per le prove: cambia lingua leggendo le traduzioni da un file.
    static func use(_ newCode: String, stringsFile: URL? = nil) {
        code = newCode
        table = load(newCode, from: stringsFile)
    }
}

/// Categoria plurale (regole CLDR semplificate) per il numero `n` nella lingua attuale.
/// Una traduzione può fornire varianti "chiave#one", "chiave#few", "chiave#many", "chiave#other".
func pluralCategory(_ n: Int, lang: String = Lang.code) -> String {
    let n = abs(n)
    switch lang {
    case "ja", "ko", "zh": return "other"
    case "ru":
        let m10 = n % 10, m100 = n % 100
        if m10 == 1 && m100 != 11 { return "one" }
        if (2...4).contains(m10) && !(12...14).contains(m100) { return "few" }
        return "many"
    case "fr", "pt": return n <= 1 ? "one" : "other"
    default: return n == 1 ? "one" : "other"
    }
}

/// Testo tradotto: `L("Delete {0} from the card?", name)`. Se fra i valori c'è un numero intero,
/// il primo decide la forma plurale (vedi `pluralCategory`).
func L(_ key: String, _ args: Any...) -> String {
    var s = Lang.table[key] ?? key
    if let n = args.first(where: { $0 is Int }) as? Int,
       let variant = Lang.table[key + "#" + pluralCategory(n)] {
        s = variant
    }
    for (i, a) in args.enumerated() { s = s.replacingOccurrences(of: "{\(i)}", with: "\(a)") }
    return s
}
