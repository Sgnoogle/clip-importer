using System.Globalization;

namespace ClipImporter;

public enum MediaKind { Video, Photo }
public enum Flag { None, Pick, Reject }
public enum MediaFilter { All, Videos, Photos }
public enum SortKey { Date, Name, Duration, Size }
public enum FolderMode { Flat, ByShootDay, ByImportDay, Custom }
public enum DeleteMode { Keep, Permanent, RecycleBin }

/// <summary>Una clip video (o foto) trovata sulla scheda.</summary>
public sealed class Clip
{
    public required string Path { get; init; }             // percorso del file sulla scheda (anche identificatore)
    public string Name => System.IO.Path.GetFileName(Path);
    public long Size { get; init; }
    public DateTime Date { get; init; }
    public double? Duration { get; init; }                  // secondi (dal file XML Sony)
    public string? ThumbnailPath { get; init; }             // miniatura Sony già pronta (THMBNL)
    public string? SidecarPath { get; init; }               // XML dei metadati Sony
    public string? ProxyPath { get; init; }                 // proxy Sony (SUB)
    public long ProxySize { get; init; }
    public string? Fps { get; init; }
    public string? Resolution { get; init; }
    public MediaKind Kind { get; init; } = MediaKind.Video;
    public IReadOnlyList<string> Companions { get; init; } = Array.Empty<string>();   // es. il RAW insieme al JPEG
    public long CompanionsSize { get; init; }
    public string? Badge { get; init; }                     // "RAW + JPEG", "RAW", "HEIF"…

    public bool IsPhoto => Kind == MediaKind.Photo;
    public long ImportSize => Size + CompanionsSize;
    public string? TechLabel
    {
        get
        {
            var parts = new[] { Resolution, Fps }.Where(s => !string.IsNullOrEmpty(s)).ToArray();
            return parts.Length == 0 ? null : string.Join(" · ", parts);
        }
    }

    /// <summary>Chiave stabile per "già importata" ed etichette (uguale alla versione Mac).</summary>
    public string Key => $"{Name.ToUpperInvariant()}|{Size}|{new DateTimeOffset(Date).ToUnixTimeSeconds()}";
}

public sealed record Source(string Path, string Name, bool IsVolume);

public sealed class ImportOptions
{
    public required string DestRoot { get; init; }
    public FolderMode FolderMode { get; init; }
    public string CustomName { get; init; } = "";
    public bool CopySidecar { get; init; }
    public bool CopyProxy { get; init; }
    public bool RenameWithDate { get; init; }
    public DeleteMode DeleteOriginals { get; init; } = DeleteMode.Keep;
}

public sealed class ImportProgress
{
    public int FileIndex { get; set; }
    public int FileCount { get; set; }
    public string CurrentName { get; set; } = "";
    public long BytesDone { get; set; }
    public long BytesTotal { get; set; }
    public DateTime StartedAt { get; set; } = DateTime.Now;
    public string Verb { get; set; } = L("Importing {0}");

    public double Fraction => BytesTotal > 0 ? Math.Min(1, (double)BytesDone / BytesTotal) : 0;
    public string Title => Verb.Replace("{0}", CurrentName);
    public string Counter => L("{0} of {1}", FileIndex + 1, FileCount);

    public string Detail
    {
        get
        {
            var parts = new List<string> { L("{0} of {1}", Fmt.Bytes(BytesDone), Fmt.Bytes(BytesTotal)) };
            var elapsed = (DateTime.Now - StartedAt).TotalSeconds;
            if (elapsed > 2 && BytesDone > 0)
            {
                var speed = BytesDone / elapsed;
                parts.Add(Fmt.Bytes((long)speed) + "/s");
                parts.Add(Fmt.Remaining((BytesTotal - BytesDone) / speed));
            }
            return string.Join(" · ", parts);
        }
    }

    public ImportProgress Clone() => (ImportProgress)MemberwiseClone();
}

public sealed record ImportFailure(Clip Clip, string Message);

public sealed class ImportResult
{
    public List<Clip> Imported { get; } = new();
    public List<Clip> Skipped { get; } = new();
    public List<ImportFailure> Failed { get; } = new();
    public List<string> Files { get; } = new();
    public bool Cancelled { get; set; }
    public List<Clip> Deleted { get; } = new();
    public List<ImportFailure> DeleteFailures { get; } = new();
}

public static class Labels
{
    public static string Of(MediaFilter f) => f switch
    {
        MediaFilter.All => L("All"),
        MediaFilter.Videos => L("Videos"),
        _ => L("Photos"),
    };

    public static string Of(SortKey k) => k switch
    {
        SortKey.Date => L("Date taken"),
        SortKey.Name => L("Name"),
        SortKey.Duration => L("Duration"),
        _ => L("Size"),
    };

    public static string Of(FolderMode m) => m switch
    {
        FolderMode.Flat => L("Everything in one folder"),
        FolderMode.ByShootDay => L("One folder per shooting day"),
        FolderMode.ByImportDay => L("One folder with today's date"),
        _ => L("One folder with a custom name"),
    };

    public static bool Includes(this MediaFilter f, Clip c) => f switch
    {
        MediaFilter.Videos => c.Kind == MediaKind.Video,
        MediaFilter.Photos => c.Kind == MediaKind.Photo,
        _ => true,
    };
}

public static class Fmt
{
    static CultureInfo C => Lang.Culture;

    public static string Day(DateTime d)
    {
        var s = d.ToString(C.DateTimeFormat.LongDatePattern, C);
        return s.Length > 0 ? char.ToUpper(s[0], C) + s[1..] : s;
    }

    public static string Time(DateTime d) => d.ToString(C.DateTimeFormat.ShortTimePattern, C);
    public static string DateTimeShort(DateTime d) => d.ToString("g", C);

    /// <summary>Dimensioni come in Esplora file (base 1024).</summary>
    public static string Bytes(long b)
    {
        string[] units = { "B", "KB", "MB", "GB", "TB" };
        double v = b; int u = 0;
        while (v >= 1024 && u < units.Length - 1) { v /= 1024; u++; }
        var fmt = u == 0 ? "0" : v < 10 ? "0.##" : v < 100 ? "0.#" : "0";
        return v.ToString(fmt, C) + " " + units[u];
    }

    public static string Duration(double seconds)
    {
        var t = (int)Math.Round(seconds);
        int h = t / 3600, m = t % 3600 / 60, s = t % 60;
        return h > 0 ? $"{h}:{m:00}:{s:00}" : $"{m}:{s:00}";
    }

    public static string Remaining(double seconds)
    {
        if (double.IsNaN(seconds) || double.IsInfinity(seconds)) return "";
        if (seconds < 60) return L("less than a minute");
        return L("about {0} min left", (int)Math.Ceiling(seconds / 60));
    }

    public static string Clips(int n) => n == 1 ? L("1 clip") : L("{0} clips", n);
    public static string Photos(int n) => n == 1 ? L("1 photo") : L("{0} photos", n);

    /// <summary>"12 clip e 30 foto", "3 foto", "1 clip"</summary>
    public static string Items(IEnumerable<Clip> list)
    {
        var arr = list as IList<Clip> ?? list.ToList();
        int photos = arr.Count(c => c.IsPhoto), videos = arr.Count - photos;
        var parts = new List<string>();
        if (videos > 0 || photos == 0) parts.Add(Clips(videos));
        if (photos > 0) parts.Add(Photos(photos));
        return string.Join(L(" and "), parts);
    }
}
