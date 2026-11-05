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
