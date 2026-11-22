using System.Globalization;

namespace ClipImporter;

public enum MediaKind { Video, Photo }
public enum Flag { None, Pick, Reject }
public enum MediaFilter { All, Videos, Photos }
public enum SortKey { Date, Name, Duration, Size }
public enum FolderMode { Flat, ByShootDay, ByImportDay, Custom }
public enum DeleteMode { Keep, Permanent, RecycleBin }
/// <summary>Cosa importare delle foto scattate in RAW + JPEG (Processed = JPEG o HEIF).</summary>
public enum PhotoFormat { Both, Processed, Raw }

/// <summary>Uno dei file di una foto (il JPEG, il RAW…).</summary>
public sealed record PhotoPart(string Path, long Size, DateTime Modified, bool IsRaw);

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

    public IReadOnlyList<PhotoPart> Parts { get; init; } = Array.Empty<PhotoPart>();  // tutti i file della foto (il principale per primo)

    /// <summary>Scattata in RAW + JPEG (o RAW + HEIF): si può scegliere quale dei due importare.</summary>
    public bool IsRawPair => Parts.Any(p => p.IsRaw) && Parts.Any(p => !p.IsRaw);

    /// <summary>Il formato che accompagna il RAW: "JPEG", "HEIF"…</summary>
    public string ProcessedLabel => Badge?.Replace("RAW + ", "") ?? "JPEG";

    /// <summary>I file da importare con questa scelta (la scelta vale solo per le coppie RAW + JPEG).</summary>
    public IReadOnlyList<PhotoPart> PartsFor(PhotoFormat format) => IsRawPair ? Parts.Where(p => format.Wants(p)).ToList() : Parts;

    /// <summary>La stessa foto con i soli file da importare: è quella che si copia, si verifica e (spostando) si cancella.
    /// Il file escluso non ne fa parte, quindi non viene mai toccato.</summary>
    public Clip Restricted(PhotoFormat format)
    {
        if (format == PhotoFormat.Both || !IsRawPair) return this;
        var wanted = PartsFor(format);
        if (wanted.Count == 0) return this;
        var others = wanted.Skip(1).ToList();
        return new Clip
        {
            Path = wanted[0].Path, Size = wanted[0].Size, Date = Date, Resolution = Resolution, Kind = MediaKind.Photo,
            Companions = others.Select(p => p.Path).ToList(), CompanionsSize = others.Sum(p => p.Size), Parts = wanted,
            Badge = format == PhotoFormat.Raw ? "RAW" : ProcessedLabel,
        };
    }

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
    /// <summary>Byte dei file davvero importati (mostrati all'utente), senza la rilettura di verifica.</summary>
    public long CopiedDone { get; set; }
    public long CopiedTotal { get; set; }

    /// <summary>Quanta parte di shown corrisponde al lavoro fatto. In virgola mobile: byte × byte non sta in un long
    /// già con un file da circa 3 GB (2 GB spostando), e i GB mostrati diventerebbero sbagliati.</summary>
    public static long ShownBytes(long work, long total, long shown)
    {
        if (total <= 0 || shown <= 0 || work <= 0) return 0;
        if (work >= total) return shown;
        return Math.Min(shown, (long)((double)work / total * shown));
    }

    public double Fraction => BytesTotal > 0 ? Math.Min(1, (double)BytesDone / BytesTotal) : 0;
    public string Title => Verb.Replace("{0}", CurrentName);
    public string Counter => L("{0} of {1}", FileIndex + 1, FileCount);

    public string Detail
    {
        get
        {
            long shownTotal = CopiedTotal > 0 ? CopiedTotal : BytesTotal;
            long shownDone = CopiedTotal > 0 ? Math.Min(CopiedDone, CopiedTotal) : BytesDone;
            var parts = new List<string> { L("{0} of {1}", Fmt.Bytes(shownDone), Fmt.Bytes(shownTotal)) };
            var elapsed = (DateTime.Now - StartedAt).TotalSeconds;
            if (elapsed > 2 && BytesDone > 0 && shownDone > 0)
            {
                parts.Add(Fmt.Bytes((long)(shownDone / elapsed)) + "/s");
                parts.Add(Fmt.Remaining((BytesTotal - BytesDone) / (BytesDone / elapsed)));
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

    /// <summary>processed: come si chiama l'altro formato ("JPEG" o "HEIF")</summary>
    public static string Of(PhotoFormat f, string processed) => f switch
    {
        PhotoFormat.Both => L("Both"),
        PhotoFormat.Processed => L("{0} only", processed),
        _ => L("{0} only", "RAW"),
    };

    public static bool Wants(this PhotoFormat f, PhotoPart p) => f switch
    {
        PhotoFormat.Processed => !p.IsRaw,
        PhotoFormat.Raw => p.IsRaw,
        _ => true,
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
