using System.Security.Cryptography;
using System.Text.RegularExpressions;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace ClipImporter;

/// <summary>
/// ClipImporter.exe --selftest &lt;cartella&gt;
/// Prova senza finestre usata da GitHub Actions: crea una finta scheda Sony, la legge, importa,
/// sposta con verifica, controlla MEDIAPRO.XML e le traduzioni. Codice di uscita 0 = tutto ok.
/// </summary>
public static class SelfTest
{
    static int failures;
    static void Check(bool ok, string what)
    {
        Console.WriteLine((ok ? "PASS  " : "FAIL  ") + what);
        if (!ok) failures++;
    }

    public static int Run(string baseDir)
    {
        Environment.SetEnvironmentVariable("CLIPIMPORTER_DATA", System.IO.Path.Combine(baseDir, "clipimporter-selftest-data"));
        var root = System.IO.Path.Combine(baseDir, "clipimporter-selftest-" + Guid.NewGuid().ToString("N")[..8]);
        Console.WriteLine($"Clip Importer self-test in {root}");
        try
        {
            TestScanAndMove(root);
            TestCopyAndSkip(root);
            TestStrings();
            TestPlurals();
        }
        catch (Exception e)
        {
            Check(false, "unexpected exception: " + e);
        }
        finally
        {
            try { Directory.Delete(root, true); } catch { }
        }
        Console.WriteLine(failures == 0 ? "ALL TESTS PASSED" : $"{failures} TEST(S) FAILED");
        return failures == 0 ? 0 : 1;
    }

    // MARK: finta scheda

    static byte[] MakeJpeg(int w, int h, byte shade)
    {
        int stride = w * 4;
        var px = new byte[stride * h];
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++)
            {
                int i = y * stride + x * 4;
                px[i] = (byte)(x * 255 / w); px[i + 1] = shade; px[i + 2] = (byte)(y * 255 / h); px[i + 3] = 255;
            }
        var bmp = BitmapSource.Create(w, h, 96, 96, PixelFormats.Bgr32, null, px, stride);
        var enc = new JpegBitmapEncoder { QualityLevel = 85 };
        enc.Frames.Add(BitmapFrame.Create(bmp));
        using var ms = new MemoryStream();
        enc.Save(ms);
        return ms.ToArray();
    }

    const string SonyXml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <NonRealTimeMeta xmlns="urn:schemas-professionalDisc:nonRealTimeMeta:ver.2.00" lastUpdate="2026-04-17T16:22:04+02:00">
        	<Duration value="250"/>
        	<CreationDate value="2026-04-17T16:22:04+02:00"/>
        	<VideoFormat>
        		<VideoFrame videoCodec="AVC_3840_2160_HP@L51" captureFps="25p" formatFps="25p"/>
        		<VideoLayout pixel="3840" numOfVerticalLine="2160" aspectRatio="16:9"/>
        	</VideoFormat>
        </NonRealTimeMeta>
        """;

    const string MediaPro = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\r\n<MediaProfile xmlns=\"http://xmlns.sony.net/pro/metadata/mediaprofile\" version=\"2.10\">\r\n\t<Contents>\r\n" +
        "\t\t<Material uri=\"./CLIP/C0001.MP4\" type=\"MP4\" fps=\"25p\" dur=\"250\">\r\n\t\t\t<RelevantInfo uri=\"./CLIP/C0001M01.XML\" type=\"XML\"/>\r\n\t\t\t<RelevantInfo uri=\"./THMBNL/C0001T01.JPG\" type=\"JPG\"/>\r\n\t\t</Material>\r\n" +
        "\t\t<Material uri=\"./CLIP/C0002.MP4\" type=\"MP4\" fps=\"25p\" dur=\"100\">\r\n\t\t\t<RelevantInfo uri=\"./CLIP/C0002M01.XML\" type=\"XML\"/>\r\n\t\t</Material>\r\n" +
        "\t</Contents>\r\n</MediaProfile>\r\n";

    static string MakeCard(string dir)
    {
        var card = System.IO.Path.Combine(dir, "card");
        var clipDir = System.IO.Path.Combine(card, "PRIVATE", "M4ROOT", "CLIP");
        var thumbDir = System.IO.Path.Combine(card, "PRIVATE", "M4ROOT", "THMBNL");
        var dcim = System.IO.Path.Combine(card, "DCIM", "100MSDCF");
        Directory.CreateDirectory(clipDir); Directory.CreateDirectory(thumbDir); Directory.CreateDirectory(dcim);
        var rnd = new Random(42);
        var video = new byte[3 * 1024 * 1024 + 123];
        rnd.NextBytes(video);
        File.WriteAllBytes(System.IO.Path.Combine(clipDir, "C0001.MP4"), video);
        File.WriteAllText(System.IO.Path.Combine(clipDir, "C0001M01.XML"), SonyXml);
        File.WriteAllBytes(System.IO.Path.Combine(thumbDir, "C0001T01.JPG"), MakeJpeg(320, 180, 40));
        File.WriteAllText(System.IO.Path.Combine(card, "PRIVATE", "M4ROOT", "MEDIAPRO.XML"), MediaPro);
        var jpg = MakeJpeg(600, 400, 160);
        File.WriteAllBytes(System.IO.Path.Combine(dcim, "DSC00001.JPG"), jpg);
        var raw = new byte[1024 * 1024];
        rnd.NextBytes(raw);
        File.WriteAllBytes(System.IO.Path.Combine(dcim, "DSC00001.ARW"), raw);
        return card;
    }

    static string Sha(string path) => Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(path)));

    // MARK: prove

    static void TestScanAndMove(string root)
    {
        var card = MakeCard(System.IO.Path.Combine(root, "move"));
        Check(CardScanner.IsCameraCard(card), "camera card detected");
        var clips = CardScanner.Scan(card, deep: false);
        Check(clips.Count == 2, $"scan finds 2 items (found {clips.Count})");
        var video = clips.FirstOrDefault(c => !c.IsPhoto);
        var photo = clips.FirstOrDefault(c => c.IsPhoto);
        Check(video != null && Math.Abs((video.Duration ?? 0) - 10) < 0.01, $"video duration from Sony XML = 10 s ({video?.Duration})");
        Check(video?.Resolution == "3840×2160" && video.Fps == "25p", $"video resolution/fps ({video?.Resolution} {video?.Fps})");
        Check(video?.ThumbnailPath != null, "video THMBNL thumbnail found");
        Check(video?.Date == new DateTimeOffset(2026, 4, 17, 16, 22, 4, TimeSpan.FromHours(2)).LocalDateTime, $"video date from XML ({video?.Date:o})");
        Check(photo != null && photo.Companions.Count == 1 && photo.Badge == "RAW + JPEG", $"RAW+JPEG paired ({photo?.Badge}, {photo?.Companions.Count})");
        Check(photo?.Resolution == "600×400", $"photo resolution from header ({photo?.Resolution})");
        Check(Thumbnails.LoadFile(video?.ThumbnailPath ?? "", 200) != null, "thumbnail decodes");

        var hashes = new Dictionary<string, string>
        {
            ["C0001.MP4"] = Sha(video!.Path),
            ["DSC00001.JPG"] = Sha(photo!.Path),
            ["DSC00001.ARW"] = Sha(photo.Companions[0]),
        };
        var dest = System.IO.Path.Combine(root, "move-dest");
        var o = new ImportOptions { DestRoot = dest, FolderMode = FolderMode.Flat, DeleteOriginals = DeleteMode.Permanent };
        int reports = 0;
        var r = Importer.Run(clips, o, CancellationToken.None, _ => reports++);
        Check(r.Imported.Count == 2 && r.Failed.Count == 0, $"move: imported 2, failed 0 ({r.Imported.Count}, {string.Join("; ", r.Failed.Select(f => f.Message))})");
        Check(r.Deleted.Count == 2 && r.DeleteFailures.Count == 0, $"move: originals deleted ({r.Deleted.Count}, {string.Join("; ", r.DeleteFailures.Select(f => f.Message))})");
        Check(reports > 0, "progress reported");
        foreach (var (name, hash) in hashes)
        {
            var p = System.IO.Path.Combine(dest, name);
            Check(File.Exists(p) && Sha(p) == hash, $"destination {name} identical to original");
        }
        Check(!File.Exists(video.Path) && !File.Exists(video.SidecarPath!) && !File.Exists(video.ThumbnailPath!), "video, XML and thumbnail removed from card");
        Check(!File.Exists(photo.Path) && !File.Exists(photo.Companions[0]), "JPEG and RAW removed from card");
        var mediapro = File.ReadAllText(System.IO.Path.Combine(card, "PRIVATE", "M4ROOT", "MEDIAPRO.XML"));
        Check(!mediapro.Contains("C0001") && mediapro.Contains("./CLIP/C0002.MP4") && mediapro.Contains("</MediaProfile>"),
              "MEDIAPRO.XML: only the moved clip's <Material> removed");
        Check(!Directory.EnumerateFiles(dest, "*.part", SearchOption.AllDirectories).Any(), "no temporary .part files left");

        // Mai cancellare se sorgente e destinazione coincidono
        var same = CardScanner.Scan(dest, deep: true);
        var r2 = Importer.Run(same, new ImportOptions { DestRoot = dest, FolderMode = FolderMode.Flat, DeleteOriginals = DeleteMode.Permanent },
                              CancellationToken.None, _ => { });
        Check(r2.Deleted.Count == 0 && hashes.Keys.All(n => File.Exists(System.IO.Path.Combine(dest, n))), "same-folder move deletes nothing");
    }

    static void TestCopyAndSkip(string root)
    {
        var card = MakeCard(System.IO.Path.Combine(root, "copy"));
        var clips = CardScanner.Scan(card, deep: false);
        var dest = System.IO.Path.Combine(root, "copy-dest");
        var o = new ImportOptions { DestRoot = dest, FolderMode = FolderMode.ByShootDay, CopySidecar = true, RenameWithDate = false };
        var r = Importer.Run(clips, o, CancellationToken.None, _ => { });
        Check(r.Imported.Count == 2 && r.Deleted.Count == 0, "copy: 2 imported, nothing deleted");
        Check(clips.All(c => File.Exists(c.Path)), "copy: originals still on card");
        var day = System.IO.Path.Combine(dest, "2026-04-17");
        Check(File.Exists(System.IO.Path.Combine(day, "C0001.MP4")) && File.Exists(System.IO.Path.Combine(day, "C0001M01.XML")),
              "copy: shooting-day folder with clip and XML sidecar");
        var again = Importer.Run(clips, o, CancellationToken.None, _ => { });
        Check(again.Skipped.Count == 2 && again.Imported.Count == 0, "re-import skips identical files");

        using var cts = new CancellationTokenSource();
        cts.Cancel();
        var cancelled = Importer.Run(clips, new ImportOptions { DestRoot = System.IO.Path.Combine(root, "cancel-dest") }, cts.Token, _ => { });
        Check(cancelled.Cancelled && cancelled.Imported.Count == 0, "cancel stops the import");
    }

    static readonly Regex Placeholder = new(@"\{\d+\}");
    static HashSet<string> Placeholders(string s) => new(Placeholder.Matches(s).Select(m => m.Value));

    static void TestStrings()
    {
        var all = Lang.LoadAll();
        Check(all.Count > 0, $"translations loaded ({string.Join(", ", all.Keys.OrderBy(k => k))})");
        int bad = 0;
        foreach (var (lang, table) in all)
        {
            Check(Lang.Supported.Contains(lang), $"language '{lang}' is supported");
            foreach (var (key, value) in table)
            {
                var baseKey = key.Contains('#') ? key[..key.IndexOf('#')] : key;
                if (!Placeholders(baseKey).SetEquals(Placeholders(value)))
                {
                    bad++;
                    Console.WriteLine($"      [{lang}] placeholder mismatch: \"{key}\" → \"{value}\"");
                }
            }
        }
        Check(bad == 0, "every translation keeps its {0}/{1} placeholders");

        foreach (var lang in Lang.Supported)
        {
            Lang.Use(lang);
            var s = L("Import {0} new · {1}", 3, "1 GB");
            Check(s.Contains('3') && s.Contains("1 GB") && !s.Contains("{0}"), $"[{lang}] L() formats: {s}");
        }
        Lang.Use("en");
    }

    static void TestPlurals()
    {
        Check(PluralCategory(1, "ru") == "one" && PluralCategory(2, "ru") == "few" && PluralCategory(5, "ru") == "many"
              && PluralCategory(21, "ru") == "one" && PluralCategory(11, "ru") == "many" && PluralCategory(13, "ru") == "many",
              "Russian plural rules");
        Check(PluralCategory(0, "fr") == "one" && PluralCategory(2, "fr") == "other" && PluralCategory(0, "en") == "other"
              && PluralCategory(7, "ja") == "other", "other plural rules");
    }
}
