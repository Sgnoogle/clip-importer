using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Win32;

namespace ClipImporter;

public static class AppPaths
{
    public static string DataDir
    {
        get
        {
            var dir = Environment.GetEnvironmentVariable("CLIPIMPORTER_DATA")
                      ?? System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Clip Importer");
            Directory.CreateDirectory(dir);
            return dir;
        }
    }

    public static string File(string name) => System.IO.Path.Combine(DataDir, name);

    internal static void WriteAtomic(string path, string text)
    {
        var tmp = path + ".tmp";
        System.IO.File.WriteAllText(tmp, text);
        System.IO.File.Move(tmp, path, overwrite: true);
    }
}

/// <summary>Ricorda quali clip sono già state importate (anche togliendo e reinserendo la scheda).</summary>
public static class ImportedStore
{
    static string FilePath => AppPaths.File("imported.json");

    public static HashSet<string> Load()
    {
        try { return new HashSet<string>(JsonSerializer.Deserialize<List<string>>(File.ReadAllText(FilePath)) ?? new()); }
        catch { return new HashSet<string>(); }
    }

    public static void Save(HashSet<string> keys)
    {
        try { AppPaths.WriteAtomic(FilePath, JsonSerializer.Serialize(keys.OrderBy(k => k).ToList())); } catch { }
    }

    // Coppie RAW + JPEG: Clip.Key = foto importata per intero. I singoli file si ricordano a parte, così dopo
    // aver importato solo il JPEG il RAW non risulta "già importato" (e cancellarlo avvisa).
    // Data del file e non EXIF: senza codec il RAW da solo non ha la data di scatto.
    static string FileKey(PhotoPart p) =>
        $"{System.IO.Path.GetFileName(p.Path).ToUpperInvariant()}|{p.Size}|{new DateTimeOffset(p.Modified).ToUnixTimeSeconds()}";
    static string PartKey(PhotoPart p) => "PART|" + FileKey(p);
    /// <summary>Lasciato apposta sulla scheda spostando solo l'altro formato.</summary>
    static string LeftKey(PhotoPart p) => "LEFT|" + FileKey(p);

    /// <summary>Tutti i file che si importerebbero con questa scelta sono già stati importati?</summary>
    public static bool IsImported(Clip clip, PhotoFormat format, HashSet<string> keys)
    {
        if (keys.Contains(clip.Key)) return true;
        var wanted = clip.PartsFor(format);
        return wanted.Count > 0 && wanted.All(p => keys.Contains(PartKey(p)));
    }

    /// <summary>Nuova = da importare. Non lo sono i file lasciati apposta sulla scheda, finché non si cambia scelta.</summary>
    public static bool IsNew(Clip clip, PhotoFormat format, HashSet<string> keys) =>
        !IsImported(clip, format, keys) && !IsLeftBehind(clip, format, keys);

    public static bool IsLeftBehind(Clip clip, PhotoFormat format, HashSet<string> keys) =>
        WasLeft(clip, keys) && !clip.Parts.Any(p => format.Wants(p));

    /// <summary>Rimasta sulla scheda dopo aver spostato solo l'altro formato (qualunque sia la scelta di adesso).</summary>
    public static bool WasLeft(Clip clip, HashSet<string> keys) =>
        clip.Parts.Count > 0 && !clip.IsRawPair && clip.Parts.All(p => keys.Contains(LeftKey(p)));

    /// <summary>Segna come importata la foto intera <paramref name="clip"/> con i soli file scelti; moved: spostata, non copiata.</summary>
    public static void Record(Clip clip, PhotoFormat format, bool moved, HashSet<string> keys)
    {
        var taken = clip.PartsFor(format);
        if (taken.Count == clip.Parts.Count) keys.Add(clip.Key);
        foreach (var p in taken) { keys.Add(PartKey(p)); keys.Remove(LeftKey(p)); }
        if (moved) foreach (var p in clip.Parts.Where(p => !taken.Contains(p))) keys.Add(LeftKey(p));
    }

    /// <summary>Dal menu: segna (o toglie il segno a) tutta la foto.</summary>
    public static void Set(Clip clip, bool imported, HashSet<string> keys)
    {
        if (imported) { Record(clip, PhotoFormat.Both, false, keys); return; }
        keys.Remove(clip.Key);
        foreach (var p in clip.Parts) { keys.Remove(PartKey(p)); keys.Remove(LeftKey(p)); }
    }
}

/// <summary>Etichette scelta/scartata, ricordate tra un avvio e l'altro.</summary>
public static class FlagStore
{
    static string FilePath => AppPaths.File("flags.json");

    public static Dictionary<string, Flag> Load()
    {
        try
        {
            var raw = JsonSerializer.Deserialize<Dictionary<string, string>>(File.ReadAllText(FilePath)) ?? new();
            return raw.Where(kv => kv.Value is "pick" or "reject")
                      .ToDictionary(kv => kv.Key, kv => kv.Value == "pick" ? Flag.Pick : Flag.Reject);
        }
        catch { return new Dictionary<string, Flag>(); }
    }

    public static void Save(Dictionary<string, Flag> flags)
    {
        var raw = flags.Where(kv => kv.Value != Flag.None)
                       .ToDictionary(kv => kv.Key, kv => kv.Value == Flag.Pick ? "pick" : "reject");
        try { AppPaths.WriteAtomic(FilePath, JsonSerializer.Serialize(raw)); } catch { }
    }
}

/// <summary>Impostazioni (salvate in %AppData%\Clip Importer\settings.json).</summary>
public sealed class Settings
{
    public SortKey SortKey { get; set; } = SortKey.Date;
    public bool Ascending { get; set; } = true;
    public bool HideImported { get; set; }
    public MediaFilter MediaFilter { get; set; } = MediaFilter.All;
    public double ThumbSize { get; set; } = 230;
    public string DestinationPath { get; set; } =
        System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyVideos), "Sony");
    public FolderMode FolderMode { get; set; } = FolderMode.ByShootDay;
    public string CustomFolderName { get; set; } = "";
    public bool CopySidecar { get; set; }
    public bool CopyProxy { get; set; }
    public bool RenameWithDate { get; set; }
    public PhotoFormat PhotoFormat { get; set; } = PhotoFormat.Both;
    public bool RevealAfter { get; set; } = true;
    public bool EjectAfter { get; set; }
    public bool AutoOpen { get; set; } = true;
    public bool DeleteAfter { get; set; }
    public bool MoveConfirmed { get; set; }
    public bool DidConfigureLoginItem { get; set; }
    public bool TrayHintShown { get; set; }
    public List<string> RecentFolders { get; set; } = new();

    static string FilePath => AppPaths.File("settings.json");
    static readonly JsonSerializerOptions Options = new() { WriteIndented = true, Converters = { new JsonStringEnumConverter() } };

    public static Settings Load()
    {
        try { return JsonSerializer.Deserialize<Settings>(File.ReadAllText(FilePath), Options) ?? new Settings(); }
        catch { return new Settings(); }
    }

    public void Save()
    {
        try { AppPaths.WriteAtomic(FilePath, JsonSerializer.Serialize(this, Options)); } catch { }
    }
}

/// <summary>Avvio automatico all'accesso: chiave Run dell'utente, con --background (resta nell'area di notifica).</summary>
public static class LoginItem
{
    const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    const string Name = "Clip Importer";

    public static bool IsEnabled
    {
        get
        {
            try { using var k = Registry.CurrentUser.OpenSubKey(RunKey); return k?.GetValue(Name) != null; }
            catch { return false; }
        }
    }

    public static void SetEnabled(bool enabled)
    {
        try
        {
            using var k = Registry.CurrentUser.CreateSubKey(RunKey, true);
            if (!enabled) { k.DeleteValue(Name, false); return; }
            var exe = Environment.ProcessPath;
            if (exe != null) k.SetValue(Name, $"\"{exe}\" --background");
        }
        catch { }
    }
}
