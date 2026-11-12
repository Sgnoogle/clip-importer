using System.Collections.Concurrent;
using System.Diagnostics;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Windows.Storage;
using Windows.Storage.FileProperties;

namespace ClipImporter;

/// <summary>
/// Miniature: quella già pronta di Sony (THMBNL) se c'è, altrimenti la miniatura di Windows
/// (la stessa di Esplora file: funziona per video, foto e, con le estensioni RAW, anche per i RAW).
/// </summary>
public static class Thumbnails
{
    static readonly ConcurrentDictionary<string, ImageSource> cache = new(StringComparer.OrdinalIgnoreCase);
    static readonly SemaphoreSlim gate = new(4);

    public sealed record Result(ImageSource? Image, double? Duration);

    /// <summary>Percorso + nome/dimensione/data: due schede Sony hanno gli stessi nomi (C0001.MP4)
    /// e spesso la stessa lettera di unità, quindi il percorso da solo non basta.</summary>
    static string CacheKey(Clip clip) => clip.Path + "|" + clip.Key;

    public static async Task<Result> LoadAsync(Clip clip)
    {
        if (cache.TryGetValue(CacheKey(clip), out var cached)) return new Result(cached, null);
        await gate.WaitAsync().ConfigureAwait(false);
        try
        {
            ImageSource? image = null;
            double? duration = null;
            if (clip.ThumbnailPath != null) image = LoadFile(clip.ThumbnailPath, 480);
            StorageFile? file = null;
            if (image == null || (!clip.IsPhoto && clip.Duration == null))
            {
                try { file = await StorageFile.GetFileFromPathAsync(clip.Path); } catch { }
            }
            if (image == null && file != null)
            {
                try
                {
                    using var thumb = await file.GetThumbnailAsync(ThumbnailMode.SingleItem, 480, ThumbnailOptions.ResizeThumbnail);
                    if (thumb != null && thumb.Size > 0)
                    {
                        using var stream = thumb.AsStreamForRead();
                        image = FromStream(stream);
                    }
                }
                catch { }
            }
            if (image == null && clip.IsPhoto && !CardScanner.IsRaw(clip.Path)) image = LoadFile(clip.Path, 480);
            if (!clip.IsPhoto && clip.Duration == null && file != null)
            {
                try
                {
                    var props = await file.Properties.GetVideoPropertiesAsync();
                    if (props.Duration.TotalSeconds > 0) duration = props.Duration.TotalSeconds;
                }
                catch { }
            }
            if (image != null) cache[CacheKey(clip)] = image;
            return new Result(image, duration);
        }
        finally { gate.Release(); }
    }

    public static BitmapSource? LoadFile(string path, int decodeWidth)
    {
        try
        {
            using var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
            var bmp = new BitmapImage();
            bmp.BeginInit();
            bmp.CacheOption = BitmapCacheOption.OnLoad;
            bmp.CreateOptions = BitmapCreateOptions.IgnoreColorProfile;
            bmp.DecodePixelWidth = decodeWidth;
            bmp.StreamSource = fs;
            bmp.EndInit();
            bmp.Freeze();
            return bmp;
        }
        catch { return null; }
    }

    static BitmapSource? FromStream(Stream s)
    {
        try
        {
            var ms = new MemoryStream();
            s.CopyTo(ms);
            ms.Position = 0;
            var bmp = new BitmapImage();
            bmp.BeginInit();
            bmp.CacheOption = BitmapCacheOption.OnLoad;
            bmp.StreamSource = ms;
            bmp.EndInit();
            bmp.Freeze();
            return bmp;
        }
        catch { return null; }
    }

    /// <summary>Versione in bianco e nero (per le scartate).</summary>
    public static ImageSource? Gray(ImageSource? src)
    {
        if (src is not BitmapSource b) return null;
        try
        {
            var g = new FormatConvertedBitmap(b, PixelFormats.Gray8, null, 0);
            g.Freeze();
            return g;
        }
        catch { return null; }
    }
}

/// <summary>Piccole azioni di sistema: apri, mostra in Esplora file, espelli.</summary>
public static class ShellActions
{
    public static void Open(string path)
    {
        try { Process.Start(new ProcessStartInfo(path) { UseShellExecute = true }); } catch { }
    }

    /// <summary>Apre Esplora file con i file selezionati (tutti nella stessa cartella).</summary>
    public static void Reveal(IEnumerable<string> paths)
    {
        var list = paths.ToList();
        if (list.Count == 0) return;
        try
        {
            var dir = Directory.Exists(list[0]) ? list[0] : System.IO.Path.GetDirectoryName(list[0])!;
            var same = list.Where(p => string.Equals(System.IO.Path.GetDirectoryName(p), dir, StringComparison.OrdinalIgnoreCase)).ToList();
            if (Directory.Exists(list[0]) || same.Count <= 1)
            {
                var arg = Directory.Exists(list[0]) ? $"\"{list[0]}\"" : $"/select,\"{list[0]}\"";
                Process.Start(new ProcessStartInfo("explorer.exe", arg) { UseShellExecute = true });
                return;
            }
            Native.OpenFolderAndSelect(dir, same);
        }
        catch { }
    }

    /// <summary>Espelle un'unità rimovibile con il verbo "Eject" della shell (come il menu di Esplora file).</summary>
    public static bool Eject(string root)
    {
        try
        {
            var type = Type.GetTypeFromProgID("Shell.Application");
            if (type == null) return false;
            dynamic shell = Activator.CreateInstance(type)!;
            dynamic? folder = shell.NameSpace(17);            // "Questo PC"
            dynamic? item = folder?.ParseName(root.TrimEnd('\\'));
            if (item == null) return false;
            item.InvokeVerb("Eject");
            // Il verbo è asincrono: si aspetta che l'unità sparisca
            for (int i = 0; i < 40; i++)
            {
                Thread.Sleep(150);
                if (!DriveInfo.GetDrives().Any(d => d.Name.Equals(root, StringComparison.OrdinalIgnoreCase) && d.IsReady)) return true;
            }
            return false;
        }
        catch { return false; }
    }
}

static class Native
{
    [System.Runtime.InteropServices.DllImport("shell32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
    static extern int SHParseDisplayName(string name, IntPtr bindCtx, out IntPtr pidl, uint sfgaoIn, out uint psfgaoOut);

    [System.Runtime.InteropServices.DllImport("shell32.dll")]
    static extern int SHOpenFolderAndSelectItems(IntPtr pidlFolder, uint cidl, IntPtr[] apidl, uint flags);

    [System.Runtime.InteropServices.DllImport("ole32.dll")]
    static extern void CoTaskMemFree(IntPtr pv);

    public static void OpenFolderAndSelect(string folder, List<string> files)
    {
        if (SHParseDisplayName(folder, IntPtr.Zero, out var folderPidl, 0, out _) != 0) return;
        var items = new List<IntPtr>();
        try
        {
            foreach (var f in files)
                if (SHParseDisplayName(f, IntPtr.Zero, out var p, 0, out _) == 0) items.Add(p);
            SHOpenFolderAndSelectItems(folderPidl, (uint)items.Count, items.ToArray(), 0);
        }
        finally
        {
            foreach (var p in items) CoTaskMemFree(p);
            CoTaskMemFree(folderPidl);
        }
    }
}
