using System.Globalization;
using System.Reflection;
using System.Text.Json;

namespace ClipImporter;

/// <summary>
/// Lingua dell'interfaccia. Stesso sistema della versione Mac (Sources/Lang.swift):
/// le traduzioni stanno in Resources/strings.json (condiviso) e windows/strings.windows.json
/// (frasi solo Windows, che hanno la precedenza). La chiave è il testo inglese; {0}, {1}… sono i valori.
/// Varianti plurali facoltative: "chiave#one", "#few", "#many", "#other" (regole CLDR semplificate).
/// </summary>
public static class Lang
{
    public static readonly string[] Supported = { "en", "it", "es", "fr", "de", "pt", "ru", "ja", "ko", "zh" };

    public static string Code { get; private set; } = Detect();
    static Dictionary<string, string> table = Load(Code);

    static string Detect()
    {
        var env = Environment.GetEnvironmentVariable("CLIPIMPORTER_LANG");
        if (!string.IsNullOrEmpty(env) && Supported.Contains(env)) return env;
        var ui = CultureInfo.CurrentUICulture.TwoLetterISOLanguageName.ToLowerInvariant();
        return Supported.Contains(ui) ? ui : "en";
    }

    /// <summary>Cultura per date e numeri: quella del sistema se è nella stessa lingua, altrimenti la lingua dell'interfaccia.</summary>
    public static CultureInfo Culture
    {
        get
        {
            var sys = CultureInfo.CurrentCulture;
            if (sys.TwoLetterISOLanguageName.Equals(Code, StringComparison.OrdinalIgnoreCase)) return sys;
            try { return CultureInfo.GetCultureInfo(Code == "pt" ? "pt-BR" : Code == "zh" ? "zh-Hans" : Code); }
            catch { return CultureInfo.InvariantCulture; }
        }
    }

    public static void Use(string code)
    {
        Code = code;
        table = Load(code);
    }

    /// <summary>Tutte le traduzioni: lingua → (chiave → testo), con le frasi Windows sopra quelle condivise.</summary>
    public static Dictionary<string, Dictionary<string, string>> LoadAll()
    {
        var result = new Dictionary<string, Dictionary<string, string>>();
        foreach (var file in new[] { "strings.json", "strings.windows.json" })
        {
            using var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream(file);
            if (stream == null) continue;
            using var doc = JsonDocument.Parse(stream, new JsonDocumentOptions { CommentHandling = JsonCommentHandling.Skip, AllowTrailingCommas = true });
            if (!doc.RootElement.TryGetProperty("translations", out var langs)) continue;
            foreach (var lang in langs.EnumerateObject())
            {
                if (!result.TryGetValue(lang.Name, out var dict)) result[lang.Name] = dict = new Dictionary<string, string>();
                foreach (var kv in lang.Value.EnumerateObject())
                    if (kv.Value.ValueKind == JsonValueKind.String) dict[kv.Name] = kv.Value.GetString() ?? "";
            }
        }
        return result;
    }

    static Dictionary<string, string> Load(string code)
    {
        if (code == "en") return new Dictionary<string, string>();
        try { return LoadAll().TryGetValue(code, out var t) ? t : new Dictionary<string, string>(); }
        catch { return new Dictionary<string, string>(); }
    }

    /// <summary>Categoria plurale (CLDR semplificato), identica a pluralCategory() della versione Mac.</summary>
    public static string PluralCategory(long n, string? lang = null)
    {
        lang ??= Code;
        n = Math.Abs(n);
        switch (lang)
        {
            case "ja": case "ko": case "zh": return "other";
            case "ru":
                long m10 = n % 10, m100 = n % 100;
                if (m10 == 1 && m100 != 11) return "one";
                if (m10 >= 2 && m10 <= 4 && !(m100 >= 12 && m100 <= 14)) return "few";
                return "many";
            case "fr": case "pt": return n <= 1 ? "one" : "other";
            default: return n == 1 ? "one" : "other";
        }
    }

    /// <summary>Testo tradotto: L("Delete {0} from the card?", name). Il primo intero sceglie la forma plurale.</summary>
    public static string L(string key, params object[] args)
    {
        var s = table.TryGetValue(key, out var t) ? t : key;
        var firstInt = args.FirstOrDefault(a => a is int || a is long);
        if (firstInt != null && table.TryGetValue(key + "#" + PluralCategory(Convert.ToInt64(firstInt)), out var variant))
            s = variant;
        for (int i = 0; i < args.Length; i++)
            s = s.Replace("{" + i + "}", Convert.ToString(args[i], Culture));
        return s;
    }
}
