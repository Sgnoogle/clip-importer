namespace ClipImporter;

/// <summary>Sorveglia una cartella (e le sottocartelle) e avvisa quando qualcosa cambia.</summary>
public sealed class FolderWatcher : IDisposable
{
    readonly FileSystemWatcher? watcher;

    public FolderWatcher(string path, Action onChange)
    {
        try
        {
            watcher = new FileSystemWatcher(path)
            {
                IncludeSubdirectories = true,
                NotifyFilter = NotifyFilters.FileName | NotifyFilters.DirectoryName | NotifyFilters.Size | NotifyFilters.LastWrite,
                InternalBufferSize = 64 * 1024,
            };
            FileSystemEventHandler h = (_, e) =>
            {
                // I file temporanei delle nostre copie (".nome.part") non contano
                if (System.IO.Path.GetFileName(e.FullPath).StartsWith('.')) return;
                onChange();
            };
            watcher.Created += h; watcher.Deleted += h; watcher.Changed += h;
            watcher.Renamed += (_, e) => onChange();
            watcher.Error += (_, _) => onChange();
            watcher.EnableRaisingEvents = true;
        }
        catch { watcher = null; }
    }

    public void Dispose()
    {
        if (watcher == null) return;
        try { watcher.EnableRaisingEvents = false; watcher.Dispose(); } catch { }
    }
}
