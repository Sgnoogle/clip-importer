using System.Globalization;
using System.Text.RegularExpressions;
using System.Windows.Media.Imaging;

namespace ClipImporter;

/// <summary>
/// Riconosce le schede delle fotocamere e ne elenca le clip (stessa logica di CardScanner.swift).
/// - XAVC S / HS / S-I: PRIVATE\M4ROOT\CLIP\C0001.MP4 con C0001M01.XML, miniature in THMBNL, proxy in SUB
/// - AVCHD: PRIVATE\AVCHD\BDMV\STREAM\00000.MTS
/// - Video e foto in DCIM (JPEG, HEIF, RAW): RAW e JPEG con lo stesso nome diventano un solo elemento
/// </summary>
public static class CardScanner
{
    public static readonly HashSet<string> VideoExtensions = new(StringComparer.OrdinalIgnoreCase) { ".mp4", ".mov", ".m4v", ".mts", ".m2ts" };
    public static readonly HashSet<string> RawExtensions = new(StringComparer.OrdinalIgnoreCase) { ".arw", ".srf", ".sr2", ".dng", ".cr2", ".cr3", ".nef", ".raf", ".orf", ".rw2" };
    public static readonly HashSet<string> PhotoExtensions = new(RawExtensions.Concat(new[] { ".jpg", ".jpeg", ".hif", ".heif", ".heic", ".png", ".tif", ".tiff" }), StringComparer.OrdinalIgnoreCase);

    static bool IsVideo(string p) => VideoExtensions.Contains(System.IO.Path.GetExtension(p));
    static bool IsPhoto(string p) => PhotoExtensions.Contains(System.IO.Path.GetExtension(p));
    static bool IsMedia(string p) => IsVideo(p) || IsPhoto(p);
    public static bool IsRaw(string p) => RawExtensions.Contains(System.IO.Path.GetExtension(p));

    public static string VolumeName(string root)
    {
        try
        {
            var d = new DriveInfo(root);
            var label = d.VolumeLabel;
            var letter = d.Name.TrimEnd('\\');
            return string.IsNullOrWhiteSpace(label) ? letter : $"{label} ({letter})";
        }
        catch { return root; }
    }

    public static bool IsCameraCard(string root)
    {
        try
        {
            if (Directory.Exists(System.IO.Path.Combine(root, "PRIVATE", "M4ROOT"))) return true;
            if (Directory.Exists(System.IO.Path.Combine(root, "PRIVATE", "AVCHD"))) return true;
            var dcim = System.IO.Path.Combine(root, "DCIM");
            if (Directory.Exists(dcim))
                return SubDirs(dcim).Any(d => Files(d).Any(IsMedia));
        }
        catch { }
        return false;
    }

    /// <summary>deep: se nella struttura standard non c'è niente, cerca in tutte le sottocartelle (cartelle scelte a mano).</summary>
    public static List<Clip> Scan(string root, bool deep)
    {
        var clips = new List<Clip>();
        var clipDir = System.IO.Path.Combine(root, "PRIVATE", "M4ROOT", "CLIP");
        if (Directory.Exists(clipDir)) clips.AddRange(Files(clipDir).Where(IsVideo).Select(MakeClip));
        var avchd = System.IO.Path.Combine(root, "PRIVATE", "AVCHD", "BDMV", "STREAM");
        if (Directory.Exists(avchd)) clips.AddRange(Files(avchd).Where(IsVideo).Select(MakeClip));
        var dcim = System.IO.Path.Combine(root, "DCIM");
        if (Directory.Exists(dcim)) foreach (var d in SubDirs(dcim)) clips.AddRange(Items(Files(d)));
        if (clips.Count == 0 && deep) clips = ScanRecursive(root);
        return clips.OrderBy(c => c.Date).ToList();
    }

    static IEnumerable<string> Files(string dir)
    {
        try
        {
            return new DirectoryInfo(dir).EnumerateFiles()
                .Where(f => (f.Attributes & (FileAttributes.Hidden | FileAttributes.System)) == 0 && !f.Name.StartsWith('.'))
                .Select(f => f.FullName).ToList();
        }
        catch { return Array.Empty<string>(); }
    }

    static IEnumerable<string> SubDirs(string dir)
    {
        try { return Directory.EnumerateDirectories(dir).Where(d => !System.IO.Path.GetFileName(d).StartsWith('.')).ToList(); }
        catch { return Array.Empty<string>(); }
    }

    /// <summary>Video uno per uno, foto raggruppate per nome (DSC00001.JPG + DSC00001.ARW = un elemento).</summary>
    static IEnumerable<Clip> Items(IEnumerable<string> paths)
    {
        var list = paths.ToList();
        var videos = list.Where(IsVideo).Select(MakeClip);
        var photos = list.Where(IsPhoto)
            .GroupBy(p => System.IO.Path.Combine(System.IO.Path.GetDirectoryName(p) ?? "", System.IO.Path.GetFileNameWithoutExtension(p)).ToUpperInvariant())
            .Select(g => MakePhoto(g.ToList()));
        return videos.Concat(photos);
    }

    static List<Clip> ScanRecursive(string root)
    {
        var found = new List<string>();
        var stack = new Stack<string>();
        stack.Push(root);
        while (stack.Count > 0 && found.Count < 10000)
        {
            var dir = stack.Pop();
            foreach (var sub in SubDirs(dir))
            {
                // Le cartelle SUB contengono i proxy Sony: non sono clip da mostrare
                if (System.IO.Path.GetFileName(sub).Equals("SUB", StringComparison.OrdinalIgnoreCase)) continue;
                var attr = File.GetAttributes(sub);
                if ((attr & (FileAttributes.Hidden | FileAttributes.System | FileAttributes.ReparsePoint)) != 0) continue;
                stack.Push(sub);
            }
            found.AddRange(Files(dir).Where(IsMedia));
        }
        return Items(found).ToList();
    }

    static (long size, DateTime date) FileInfoOf(string path)
    {
        try
        {
            var fi = new FileInfo(path);
            var created = fi.CreationTime;
            var modified = fi.LastWriteTime;
            // Su ExFAT la data di creazione è quella dello scatto; se manca o è dopo la modifica, uso la modifica
            var date = created.Year > 1980 && created <= modified.AddSeconds(2) ? created : modified;
            return (fi.Length, date);
        }
        catch { return (0, DateTime.Now); }
    }

    public static Clip MakeClip(string path)
    {
        var (size, date) = FileInfoOf(path);
        var dir = System.IO.Path.GetDirectoryName(path) ?? "";
        var parent = System.IO.Path.GetDirectoryName(dir) ?? "";
        var baseName = System.IO.Path.GetFileNameWithoutExtension(path);

        string? sidecar = new[] { $"{baseName}M01.XML", $"{baseName}M01.xml", $"{baseName}.XML", $"{baseName}.xml" }
            .Select(n => System.IO.Path.Combine(dir, n)).FirstOrDefault(File.Exists);
        string? thumb = new[] { $"{baseName}T01.JPG", $"{baseName}T01.jpg" }
            .Select(n => System.IO.Path.Combine(parent, "THMBNL", n)).FirstOrDefault(File.Exists);

        string? proxy = null; long proxySize = 0;
        var subDir = System.IO.Path.Combine(parent, "SUB");
        if (Directory.Exists(subDir))
        {
            proxy = Files(subDir).FirstOrDefault(f =>
            {
                var n = System.IO.Path.GetFileName(f).ToUpperInvariant();
                return n.StartsWith(baseName.ToUpperInvariant() + "S") && n.EndsWith(".MP4");
            });
            if (proxy != null) proxySize = new FileInfo(proxy).Length;
        }

        double? duration = null; string? fps = null, resolution = null;
        if (sidecar != null)
        {
            var meta = ParseSidecar(sidecar);
            if (meta.date != null) date = meta.date.Value;
            duration = meta.duration; fps = meta.fps; resolution = meta.resolution;
        }

        return new Clip
        {
            Path = path, Size = size, Date = date, Duration = duration, ThumbnailPath = thumb, SidecarPath = sidecar,
            ProxyPath = proxy, ProxySize = proxySize, Fps = fps, Resolution = resolution,
        };
    }

    /// <summary>files: stesso nome, estensioni diverse. Il JPEG/HEIF è quello mostrato, il RAW lo accompagna.</summary>
    public static Clip MakePhoto(List<string> files)
    {
        static int Rank(string p)
        {
            var e = System.IO.Path.GetExtension(p).ToLowerInvariant();
            if (e is ".jpg" or ".jpeg") return 0;
            if (e is ".hif" or ".heif" or ".heic") return 1;
            if (RawExtensions.Contains(e)) return 3;
            return 2;
        }
        var sorted = files.OrderBy(Rank).ToList();
        var main = sorted[0];
        var others = sorted.Skip(1).ToList();
        var (size, fileDate) = FileInfoOf(main);
        long otherSize = others.Sum(o => { try { return new FileInfo(o).Length; } catch { return 0L; } });

        var (exifDate, resolution) = ReadPhotoInfo(main);
        bool hasRaw = files.Any(IsRaw);
        var ext = System.IO.Path.GetExtension(main).TrimStart('.').ToUpperInvariant();
        string Name(string e) => e is "JPG" or "JPEG" ? "JPEG" : e == "HIF" ? "HEIF" : e;
        string badge = hasRaw && others.Count > 0 ? "RAW + " + Name(ext) : hasRaw ? "RAW" : Name(ext);

        return new Clip
        {
            Path = main, Size = size, Date = exifDate ?? fileDate, Resolution = resolution, Kind = MediaKind.Photo,
            Companions = others, CompanionsSize = otherSize, Badge = badge,
        };
    }

    /// <summary>Data di scatto e risoluzione dall'EXIF (senza decodificare l'immagine).</summary>
    public static (DateTime? date, string? resolution) ReadPhotoInfo(string path)
    {
        try
        {
            using var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
            var decoder = BitmapDecoder.Create(fs, BitmapCreateOptions.DelayCreation | BitmapCreateOptions.IgnoreColorProfile, BitmapCacheOption.None);
            var frame = decoder.Frames[0];
            DateTime? date = null;
            int orientation = 1;
            if (frame.Metadata is BitmapMetadata md)
            {
                foreach (var q in new[] { "/app1/ifd/exif/{ushort=36867}", "/ifd/exif/{ushort=36867}", "/app1/ifd/{ushort=306}" })
                {
                    try
                    {
                        if (md.GetQuery(q) is string s &&
                            DateTime.TryParseExact(s.Trim('\0', ' '), "yyyy:MM:dd HH:mm:ss", CultureInfo.InvariantCulture, DateTimeStyles.AssumeLocal, out var d))
                        { date = d; break; }
                    }
                    catch { }
                }
                foreach (var q in new[] { "/app1/ifd/{ushort=274}", "/ifd/{ushort=274}" })
                {
                    try { if (md.GetQuery(q) is ushort o) { orientation = o; break; } } catch { }
                }
            }
            int w = frame.PixelWidth, h = frame.PixelHeight;
            if (orientation >= 5) (w, h) = (h, w);
            return (date, w > 0 && h > 0 ? $"{w}×{h}" : null);
        }
        catch { return (null, null); }
    }

    // MARK: XML Sony (NonRealTimeMeta)

    public static (DateTime? date, double? duration, string? fps, string? resolution) ParseSidecar(string path)
    {
        string xml;
        try { xml = File.ReadAllText(path); } catch { return (null, null, null, null); }

        string? Attr(string tag, string name)
        {
            var m = Regex.Match(xml, "<" + tag + @"\s[^>]*?\b" + name + "=\"([^\"]*)\"");
            return m.Success ? m.Groups[1].Value : null;
        }

        DateTime? date = null;
        var cd = Attr("CreationDate", "value");
        if (cd != null)
        {
            if (DateTimeOffset.TryParse(cd, CultureInfo.InvariantCulture, DateTimeStyles.None, out var dto)) date = dto.LocalDateTime;
            else if (cd.Length >= 19 && DateTime.TryParseExact(cd[..19], "yyyy-MM-dd'T'HH:mm:ss", CultureInfo.InvariantCulture, DateTimeStyles.AssumeLocal, out var d)) date = d;
        }

        double? duration = null;
        var fps = Attr("VideoFrame", "formatFps") ?? Attr("VideoFrame", "captureFps");
        if (fps != null)
        {
            var numeric = new string(fps.Where(c => char.IsDigit(c) || c == '.').ToArray());
            if (double.TryParse(numeric, NumberStyles.Float, CultureInfo.InvariantCulture, out var rate) && rate > 0)
            {
                if (fps.EndsWith("i", StringComparison.OrdinalIgnoreCase)) rate /= 2;
                if (double.TryParse(Attr("Duration", "value"), NumberStyles.Float, CultureInfo.InvariantCulture, out var frames))
                    duration = frames / rate;
            }
        }

        string? resolution = null;
        var w = Attr("VideoLayout", "pixel");
        var h = Attr("VideoLayout", "numOfVerticalLine");
        if (w != null && h != null) resolution = $"{w}×{h}";
        return (date, duration, fps, resolution);
    }
}
