using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using Microsoft.Win32.SafeHandles;

namespace ClipImporter;

public sealed class VerifyException : Exception
{
    public VerifyException() : base(L("the copy doesn't match the original (verification failed): the original was left untouched")) { }
}

/// <summary>Copia delle clip nella destinazione, con avanzamento, verifica e annullamento (come Importer.swift).</summary>
public static class Importer
{
    const int Chunk = 8 * 1024 * 1024;

    public static string FolderFor(Clip clip, ImportOptions o, DateTime now) => o.FolderMode switch
    {
        FolderMode.Flat => o.DestRoot,
        FolderMode.ByShootDay => System.IO.Path.Combine(o.DestRoot, DayString(clip.Date)),
        FolderMode.ByImportDay => System.IO.Path.Combine(o.DestRoot, DayString(now)),
        _ => Sanitize(o.CustomName) is { Length: > 0 } n ? System.IO.Path.Combine(o.DestRoot, n) : o.DestRoot,
    };

    public static string TargetName(Clip clip, ImportOptions o) =>
        o.RenameWithDate ? $"{clip.Date:yyyy-MM-dd_HH-mm-ss}_{clip.Name}" : clip.Name;

    public static string DayString(DateTime d) => d.ToString("yyyy-MM-dd", System.Globalization.CultureInfo.InvariantCulture);

    public static string Sanitize(string name)
    {
        var invalid = System.IO.Path.GetInvalidFileNameChars();
        var s = new string(name.Select(c => invalid.Contains(c) ? '-' : c).ToArray()).Trim();
        return s.TrimEnd('.', ' ');
    }

    /// <summary>Spazio libero sul disco della destinazione (risale fino a una cartella esistente).</summary>
    public static long? FreeSpace(string path)
    {
        try
        {
            var root = System.IO.Path.GetPathRoot(System.IO.Path.GetFullPath(path));
            if (string.IsNullOrEmpty(root)) return null;
            var free = new DriveInfo(root).AvailableFreeSpace;
            return free > 0 ? free : null;
        }
        catch { return null; }
    }

    static string UniquePath(string path)
    {
        var dir = System.IO.Path.GetDirectoryName(path)!;
        var baseName = System.IO.Path.GetFileNameWithoutExtension(path);
        var ext = System.IO.Path.GetExtension(path);
        for (int n = 2; ; n++)
        {
            var candidate = System.IO.Path.Combine(dir, $"{baseName} ({n}){ext}");
            if (!File.Exists(candidate)) return candidate;
        }
    }

    static long SizeOf(string p) { try { return new FileInfo(p).Length; } catch { return -1; } }

    public static ImportResult Run(IReadOnlyList<Clip> clips, ImportOptions o, CancellationToken cancel, Action<ImportProgress> progress)
    {
        var result = new ImportResult();
        var start = DateTime.Now;
        bool moving = o.DeleteOriginals != DeleteMode.Keep;
        // Spostando, ogni file viene anche riletto dalla destinazione per verificarlo: il doppio dei byte
        long total = clips.Sum(c => c.ImportSize * (moving ? 2 : 1) + (o.CopyProxy ? c.ProxySize : 0));
        var sonyIndexRemovals = new Dictionary<string, List<string>>(StringComparer.OrdinalIgnoreCase);
        long done = 0;
        var lastReport = DateTime.MinValue;
        var current = new ImportProgress { FileCount = clips.Count, BytesTotal = total, StartedAt = start };

        void Report(bool force = false)
        {
            var now = DateTime.Now;
            if (!force && (now - lastReport).TotalSeconds < 0.15) return;
            lastReport = now;
            current.BytesDone = done;
            progress(current.Clone());
        }
        void OnBytes(long n) { done += n; Report(); }

        for (int index = 0; index < clips.Count; index++)
        {
            var clip = clips[index];
            if (cancel.IsCancellationRequested) { result.Cancelled = true; break; }
            current.FileIndex = index;
            current.CurrentName = clip.Name;
            current.Verb = L("Importing {0}");
            Report(true);
            bool extrasOK = true;      // XML e proxy richiesti copiati davvero (se no l'originale non si cancella)
            var verifiedPairs = new List<(string src, string dst)>();
            var folder = FolderFor(clip, o, start);
            long proxyBytes = o.CopyProxy ? clip.ProxySize : 0;
            try
            {
                Directory.CreateDirectory(folder);
                var dst = System.IO.Path.Combine(folder, TargetName(clip, o));

                if (File.Exists(dst) && SizeOf(dst) == clip.Size && (!moving || SameContents(clip.Path, dst, cancel, OnBytes)))
                {
                    // Stesso file già presente: non lo ricopio (ma completo l'eventuale RAW mancante)
                    if (!moving) done += clip.Size;
                    current.Verb = L("Importing {0}");
                    var pairs = CopyCompanions(clip, System.IO.Path.GetFileNameWithoutExtension(dst), folder, moving, cancel, OnBytes);
                    verifiedPairs.Add((clip.Path, dst)); verifiedPairs.AddRange(pairs);
                    result.Skipped.Add(clip);
                    result.Files.Add(dst);
                }
                else
                {
                    if (File.Exists(dst)) dst = UniquePath(dst);
                    var hash = CopyFile(clip.Path, dst, moving, cancel, OnBytes);
                    if (moving)
                    {
                        current.Verb = L("Verifying {0}");
                        Verify(dst, hash, cancel, OnBytes);
                        current.Verb = L("Importing {0}");
                    }
                    var dstBase = System.IO.Path.GetFileNameWithoutExtension(dst);
                    // RAW abbinato al JPEG: stesso nome, così restano accoppiati in Lightroom/Capture One
                    var pairs = CopyCompanions(clip, dstBase, folder, moving, cancel, OnBytes);
                    verifiedPairs.Add((clip.Path, dst)); verifiedPairs.AddRange(pairs);
                    result.Imported.Add(clip);
                    result.Files.Add(dst);

                    if (o.CopySidecar && clip.SidecarPath is { } xml)
                    {
                        var xmlDst = System.IO.Path.Combine(folder, $"{dstBase}M01{System.IO.Path.GetExtension(xml)}");
                        if (!File.Exists(xmlDst)) { try { File.Copy(xml, xmlDst); } catch { extrasOK = false; } }
                    }
                }
                var baseOfDst = System.IO.Path.GetFileNameWithoutExtension(verifiedPairs[0].dst);

                if (o.CopyProxy && clip.ProxyPath is { } proxy)
                {
                    // Stesso nome dell'originale dentro "Proxy": DaVinci Resolve li collega da solo
                    var proxyDir = System.IO.Path.Combine(folder, "Proxy");
                    var proxyDst = System.IO.Path.Combine(proxyDir, baseOfDst + System.IO.Path.GetExtension(proxy));
                    try
                    {
                        Directory.CreateDirectory(proxyDir);
                        if (File.Exists(proxyDst)) done += proxyBytes;
                        else CopyFile(proxy, proxyDst, false, cancel, OnBytes);
                    }
                    catch (OperationCanceledException) { throw; }
                    catch { extrasOK = false; }   // un proxy mancante non blocca la clip (ma la clip resta sulla scheda)
                }

                // Copia verificata: ora (e solo ora) si cancellano gli originali
                if (moving && !cancel.IsCancellationRequested)
                {
                    if (!extrasOK)
                    {
                        result.DeleteFailures.Add(new ImportFailure(clip, L("copied, but its XML or proxy wasn't: left on the card")));
                        continue;
                    }
                    // Mai cancellare se origine e destinazione sono lo stesso file
                    if (verifiedPairs.Any(p => SameFile(p.src, p.dst))) continue;
                    current.Verb = L("Deleting {0}");
                    Report(true);
                    try
                    {
                        DeleteOriginals(clip, o.DeleteOriginals);
                        result.Deleted.Add(clip);
                        var clipDir = System.IO.Path.GetDirectoryName(clip.Path)!;
                        if (System.IO.Path.GetFileName(clipDir).Equals("CLIP", StringComparison.OrdinalIgnoreCase))
                        {
                            var root = System.IO.Path.GetDirectoryName(clipDir)!;
                            if (!sonyIndexRemovals.TryGetValue(root, out var l)) sonyIndexRemovals[root] = l = new List<string>();
                            l.Add(clip.Name);
                        }
                    }
                    catch (Exception e) { result.DeleteFailures.Add(new ImportFailure(clip, e.Message)); }
                }
            }
            catch (OperationCanceledException) { result.Cancelled = true; break; }
            catch (Exception e) { result.Failed.Add(new ImportFailure(clip, e.Message)); }
        }
        foreach (var (root, names) in sonyIndexRemovals) SonyIndex.Remove(names, root);
        Report(true);
        return result;
    }

    /// <summary>Copia i file abbinati (es. .ARW) accanto al principale, con lo stesso nome base.</summary>
    static List<(string src, string dst)> CopyCompanions(Clip clip, string baseName, string folder, bool verify, CancellationToken cancel, Action<long> onBytes)
    {
        var pairs = new List<(string, string)>();
        foreach (var src in clip.Companions)
        {
            var dst = System.IO.Path.Combine(folder, baseName + System.IO.Path.GetExtension(src));
            var size = SizeOf(src);
            if (File.Exists(dst) && SizeOf(dst) == size)
            {
                if (verify)
                {
                    if (!SameContents(src, dst, cancel, onBytes))
                        throw new IOException(L("a different {0} already exists in the destination", System.IO.Path.GetFileName(dst)));
                }
                else onBytes(size);
            }
            else
            {
                var hash = CopyFile(src, dst, verify, cancel, onBytes);
                if (verify) Verify(dst, hash, cancel, onBytes);
            }
            pairs.Add((src, dst));
        }
        return pairs;
    }

    /// <summary>
    /// Copia a blocchi su un file temporaneo nascosto, poi lo rinomina: una copia interrotta non lascia
    /// mai un file "buono a metà". Con hashing calcola l'impronta SHA-256 dei byte letti dall'originale.
    /// </summary>
    public static byte[]? CopyFile(string src, string dst, bool hashing, CancellationToken cancel, Action<long> onBytes)
    {
        var tmp = System.IO.Path.Combine(System.IO.Path.GetDirectoryName(dst)!, "." + System.IO.Path.GetFileName(dst) + ".part");
        try { File.Delete(tmp); } catch { }
        using var hasher = hashing ? IncrementalHash.CreateHash(HashAlgorithmName.SHA256) : null;
        bool completed = false;
        try
        {
            using (var input = new FileStream(src, FileMode.Open, FileAccess.Read, FileShare.Read, 1, FileOptions.SequentialScan))
            using (var output = new FileStream(tmp, FileMode.CreateNew, FileAccess.Write, FileShare.None, 1,
                                               hashing ? FileOptions.WriteThrough : FileOptions.None))
            {
                try { File.SetAttributes(tmp, FileAttributes.Hidden); } catch { }
                var buffer = new byte[Chunk];
                int read;
                while ((read = input.Read(buffer, 0, buffer.Length)) > 0)
                {
                    cancel.ThrowIfCancellationRequested();
                    hasher?.AppendData(buffer, 0, read);
                    output.Write(buffer, 0, read);
                    onBytes(read);
                }
                output.Flush(true);
            }
            File.SetAttributes(tmp, FileAttributes.Normal);
            File.Move(tmp, dst);
            completed = true;
            // Mantiene le date originali
            try
            {
                File.SetCreationTime(dst, File.GetCreationTime(src));
                File.SetLastWriteTime(dst, File.GetLastWriteTime(src));
            }
            catch { }
            return hasher?.GetHashAndReset();
        }
        finally
        {
            if (!completed) { try { File.Delete(tmp); } catch { } }
        }
    }

    /// <summary>Rilegge la copia dal disco (senza cache) e ne confronta l'impronta SHA-256.</summary>
    public static void Verify(string dst, byte[]? expected, CancellationToken cancel, Action<long> onBytes)
    {
        var actual = HashFile(dst, cancel, onBytes, uncached: true);
        if (expected == null || !actual.AsSpan().SequenceEqual(expected))
        {
            try { File.Delete(dst); } catch { }     // copia difettosa: via
            throw new VerifyException();
        }
    }

    public static bool SameContents(string a, string b, CancellationToken cancel, Action<long> onBytes)
    {
        if (SameFile(a, b)) return true;
        var ha = HashFile(a, cancel, onBytes, uncached: false);
        var hb = HashFile(b, cancel, onBytes, uncached: true);
        return ha.AsSpan().SequenceEqual(hb);
    }

    const FileOptions NoBuffering = (FileOptions)0x20000000;   // FILE_FLAG_NO_BUFFERING

    public static byte[] HashFile(string path, CancellationToken cancel, Action<long> onBytes, bool uncached)
    {
        if (uncached)
        {
            try { return HashUncached(path, cancel, onBytes); }
            catch (OperationCanceledException) { throw; }
            catch { /* alcuni dischi non accettano letture senza cache: si ripiega sulla lettura normale */ }
        }
        using var hasher = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        using var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read, 1, FileOptions.SequentialScan);
        var buffer = new byte[Chunk];
        int read;
        while ((read = fs.Read(buffer, 0, buffer.Length)) > 0)
        {
            cancel.ThrowIfCancellationRequested();
            hasher.AppendData(buffer, 0, read);
            onBytes(read);
        }
        return hasher.GetHashAndReset();
    }

    /// <summary>Lettura con FILE_FLAG_NO_BUFFERING: i dati arrivano davvero dal disco, non dalla RAM.</summary>
    static unsafe byte[] HashUncached(string path, CancellationToken cancel, Action<long> onBytes)
    {
        using SafeFileHandle handle = File.OpenHandle(path, FileMode.Open, FileAccess.Read, FileShare.Read, NoBuffering);
        long length = RandomAccess.GetLength(handle);
        const int align = 4096;
        void* mem = NativeMemory.AlignedAlloc(Chunk, align);
        long reported = 0;
        try
        {
            using var hasher = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
            var span = new Span<byte>(mem, Chunk);
            long offset = 0;
            while (offset < length)
            {
                cancel.ThrowIfCancellationRequested();
                int read = RandomAccess.Read(handle, span, offset);
                if (read <= 0) break;
                int useful = (int)Math.Min(read, length - offset);
                hasher.AppendData(span[..useful]);
                offset += useful;
                onBytes(useful); reported += useful;
                if (read < Chunk) break;
            }
            if (offset != length) throw new IOException("short read");
            return hasher.GetHashAndReset();
        }
        catch
        {
            onBytes(-reported);     // il ripiego rileggerà tutto: annulla l'avanzamento già contato
            throw;
        }
        finally { NativeMemory.AlignedFree(mem); }
    }

    public static bool SameFile(string a, string b)
    {
        try
        {
            var fa = System.IO.Path.GetFullPath(a).TrimEnd('\\');
            var fb = System.IO.Path.GetFullPath(b).TrimEnd('\\');
            if (string.Equals(fa, fb, StringComparison.OrdinalIgnoreCase)) return true;
            var ia = FileId(fa); var ib = FileId(fb);
            return ia != null && ib != null && ia == ib;
        }
        catch { return false; }
    }

    [StructLayout(LayoutKind.Sequential)]
    struct BY_HANDLE_FILE_INFORMATION
    {
        public uint FileAttributes; public long CreationTime, LastAccessTime, LastWriteTime;
        public uint VolumeSerialNumber, FileSizeHigh, FileSizeLow, NumberOfLinks, FileIndexHigh, FileIndexLow;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool GetFileInformationByHandle(SafeFileHandle h, out BY_HANDLE_FILE_INFORMATION info);

    static string? FileId(string path)
    {
        try
        {
            using var h = File.OpenHandle(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            if (!GetFileInformationByHandle(h, out var i)) return null;
            return $"{i.VolumeSerialNumber}:{i.FileIndexHigh}:{i.FileIndexLow}";
        }
        catch { return null; }
    }

    static bool IsWriteProtected(Exception e) =>
        (e.HResult & 0xFFFF) is 19 or 5 && e is IOException or UnauthorizedAccessException;   // ERROR_WRITE_PROTECT / ACCESS_DENIED

    /// <summary>Cancella la clip e tutto ciò che la accompagna (RAW, XML, miniatura, proxy).</summary>
    public static void DeleteOriginals(Clip clip, DeleteMode mode)
    {
        var main = new[] { clip.Path }.Concat(clip.Companions).ToList();
        var extras = new[] { clip.SidecarPath, clip.ThumbnailPath, clip.ProxyPath }.Where(p => p != null).Cast<string>().ToList();
        void Remove(string p)
        {
            if (!File.Exists(p)) return;
            if (mode == DeleteMode.RecycleBin) RecycleBin.Send(p);
            else
            {
                var attr = File.GetAttributes(p);
                if ((attr & FileAttributes.ReadOnly) != 0) File.SetAttributes(p, attr & ~FileAttributes.ReadOnly);
                File.Delete(p);
            }
        }
        try { foreach (var p in main) Remove(p); }
        catch (Exception e) when (IsWriteProtected(e))
        {
            throw new IOException(L("the card is write-protected (check the LOCK switch on the side of the SD card)"), e);
        }
        foreach (var p in extras) { try { Remove(p); } catch { } }
    }
}

/// <summary>Cestino di Windows (SHFileOperation con FOF_ALLOWUNDO).</summary>
public static class RecycleBin
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct SHFILEOPSTRUCT
    {
        public IntPtr hwnd; public uint wFunc;
        [MarshalAs(UnmanagedType.LPWStr)] public string pFrom;
        [MarshalAs(UnmanagedType.LPWStr)] public string? pTo;
        public ushort fFlags; public int fAnyOperationsAborted; public IntPtr hNameMappings;
        [MarshalAs(UnmanagedType.LPWStr)] public string? lpszProgressTitle;
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    static extern int SHFileOperation(ref SHFILEOPSTRUCT op);

    const uint FO_DELETE = 3;
    const ushort FOF_SILENT = 0x4, FOF_NOCONFIRMATION = 0x10, FOF_ALLOWUNDO = 0x40, FOF_NOERRORUI = 0x400;

    public static void Send(string path)
    {
        var op = new SHFILEOPSTRUCT
        {
            wFunc = FO_DELETE,
            pFrom = System.IO.Path.GetFullPath(path) + "\0\0",
            fFlags = FOF_ALLOWUNDO | FOF_NOCONFIRMATION | FOF_SILENT | FOF_NOERRORUI,
        };
        int r = SHFileOperation(ref op);
        if (r != 0 || op.fAnyOperationsAborted != 0) throw new IOException($"Recycle Bin error 0x{r:X}");
    }
}

/// <summary>
/// Indice delle clip delle Sony XAVC (PRIVATE\M4ROOT\MEDIAPRO.XML): si tolgono solo i blocchi
/// &lt;Material&gt; delle clip cancellate, lasciando il resto identico byte per byte.
/// </summary>
public static class SonyIndex
{
    public static void Remove(IEnumerable<string> clipNames, string m4root)
    {
        var path = System.IO.Path.Combine(m4root, "MEDIAPRO.XML");
        try
        {
            if (!File.Exists(path)) return;
            var bytes = File.ReadAllBytes(path);
            bool bom = bytes.Length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF;
            var xml = new UTF8Encoding(false).GetString(bytes, bom ? 3 : 0, bytes.Length - (bom ? 3 : 0));
            var original = xml;
            foreach (var name in clipNames)
            {
                var pattern = @"[ \t]*<Material\s+uri=""\./CLIP/" + Regex.Escape(name) + @"""[^>]*?(?:/>|>.*?</Material>)[ \t]*\r?\n?";
                xml = Regex.Replace(xml, pattern, "", RegexOptions.IgnoreCase | RegexOptions.Singleline);
            }
            if (xml == original || !xml.Contains("</MediaProfile>")) return;
            var outBytes = (bom ? new byte[] { 0xEF, 0xBB, 0xBF } : Array.Empty<byte>()).Concat(new UTF8Encoding(false).GetBytes(xml)).ToArray();
            var tmp = path + ".tmp";
            File.WriteAllBytes(tmp, outBytes);
            File.Move(tmp, path, overwrite: true);
        }
        catch { }
    }
}
