using System.Collections.ObjectModel;
using System.Collections.Specialized;
using System.Media;
using System.Windows;
using System.Windows.Threading;
using Microsoft.Win32;

namespace ClipImporter;

/// <summary>Stato dell'app (stessa logica di AppState.swift).</summary>
public sealed class AppState : Observable
{
    public static AppState Shared { get; } = new();

    readonly Settings s = Settings.Load();
    readonly Dispatcher ui = Application.Current?.Dispatcher ?? Dispatcher.CurrentDispatcher;

    // Sorgenti e clip
    public ObservableCollection<Source> Sources { get; } = new();
    Source? current;
    public Source? Current { get => current; private set { if (Set(ref current, value)) { Raise(nameof(HasSource)); Raise(nameof(SourceName)); Raise(nameof(IsVolume)); Raise(nameof(SourcePlace)); Raise(nameof(DeleteAfterLabel)); } } }
    public bool HasSource => current != null;
    public string SourceName => current?.Name ?? "";
    public bool IsVolume => current?.IsVolume ?? true;

    List<Clip> clips = new();
    public IReadOnlyList<Clip> Clips => clips;
    readonly Dictionary<string, ClipItem> items = new(StringComparer.OrdinalIgnoreCase);
    public ObservableCollection<DaySection> Sections { get; } = new();

    bool scanning;
    public bool Scanning { get => scanning; private set { if (Set(ref scanning, value)) RaiseView(); } }

    readonly HashSet<string> selection = new(StringComparer.OrdinalIgnoreCase);
    string? anchor;
    HashSet<string> importedKeys = ImportedStore.Load();
    Dictionary<string, Flag> flags = FlagStore.Load();
    FolderWatcher? watcher;
    int rescanToken;
    bool pendingRescan;

    // Importazione
    ImportProgress? progress;
    public ImportProgress? Progress { get => progress; private set { if (Set(ref progress, value)) { Raise(nameof(IsImporting)); Raise(nameof(NotImporting)); } } }
    public bool IsImporting => progress != null;
    public bool NotImporting => progress == null;
    CancellationTokenSource? cancelSource;
    string? banner;
    public string? Banner { get => banner; private set => Set(ref banner, value); }
    int bannerToken;

    /// <summary>Chiamata quando serve mostrare la finestra (es. scheda appena inserita).</summary>
    public Action? WantsWindow;

    bool altHeld;
    /// <summary>Alt premuto: come ⌥ sul Mac, trasforma "Importa" in "Sposta".</summary>
    public bool AltHeld { get => altHeld; set { if (Set(ref altHeld, value)) RaiseButtons(); } }

    AppState()
    {
        // Ripristina le cartelle usate l'ultima volta (solo quelle che esistono ancora)
        foreach (var p in s.RecentFolders.Where(Directory.Exists))
            Sources.Add(new Source(p, System.IO.Path.GetFileName(p.TrimEnd('\\')) is { Length: > 0 } n ? n : p, false));
    }

    // MARK: Impostazioni

    void Save() => s.Save();
    public SortKey SortKey { get => s.SortKey; set { s.SortKey = value; Save(); Raise(); Raise(nameof(SortLabel)); Rebuild(); } }
    public bool Ascending { get => s.Ascending; set { s.Ascending = value; Save(); Raise(); Rebuild(); } }
    public bool HideImported { get => s.HideImported; set { s.HideImported = value; Save(); Raise(); Rebuild(); } }
    public MediaFilter MediaFilter
    {
        get => s.MediaFilter;
        set
        {
            s.MediaFilter = value; Save(); Raise();
            Raise(nameof(FilterAll)); Raise(nameof(FilterVideos)); Raise(nameof(FilterPhotos));
            // Quello che non si vede non resta selezionato
            selection.IntersectWith(clips.Where(value.Includes).Select(c => c.Path));
            Rebuild();
        }
    }
    public bool FilterAll { get => MediaFilter == MediaFilter.All; set { if (value) MediaFilter = MediaFilter.All; } }
    public bool FilterVideos { get => MediaFilter == MediaFilter.Videos; set { if (value) MediaFilter = MediaFilter.Videos; } }
    public bool FilterPhotos { get => MediaFilter == MediaFilter.Photos; set { if (value) MediaFilter = MediaFilter.Photos; } }
    public double ThumbSize { get => s.ThumbSize; set { s.ThumbSize = value; Save(); Raise(); Raise(nameof(ThumbHeight)); } }
    public double ThumbHeight => ThumbSize * 9 / 16;
    public string DestinationPath { get => s.DestinationPath; set { s.DestinationPath = value; Save(); Raise(); Raise(nameof(DestinationDisplay)); Raise(nameof(DestinationPreview)); } }
    public FolderMode FolderMode { get => s.FolderMode; set { s.FolderMode = value; Save(); Raise(); Raise(nameof(IsCustomFolder)); Raise(nameof(DestinationPreview)); } }
    public bool IsCustomFolder => FolderMode == FolderMode.Custom;
    public string CustomFolderName { get => s.CustomFolderName; set { s.CustomFolderName = value; Save(); Raise(); Raise(nameof(DestinationPreview)); } }
    public bool CopySidecar { get => s.CopySidecar; set { s.CopySidecar = value; Save(); Raise(); } }
    public bool CopyProxy { get => s.CopyProxy; set { s.CopyProxy = value; Save(); Raise(); } }
    public bool RenameWithDate { get => s.RenameWithDate; set { s.RenameWithDate = value; Save(); Raise(); Raise(nameof(DestinationPreview)); } }
    public bool RevealAfter { get => s.RevealAfter; set { s.RevealAfter = value; Save(); Raise(); } }
    public bool EjectAfter { get => s.EjectAfter; set { s.EjectAfter = value; Save(); Raise(); } }
    public bool AutoOpen { get => s.AutoOpen; set { s.AutoOpen = value; Save(); Raise(); } }
    public bool DeleteAfter { get => s.DeleteAfter; set { s.DeleteAfter = value; Save(); Raise(); RaiseButtons(); } }
    public bool LaunchAtLogin { get => LoginItem.IsEnabled; set { LoginItem.SetEnabled(value); Raise(); } }
    public Settings RawSettings => s;

    public void ConfigureLoginItemOnFirstRun()
    {
        if (!s.DidConfigureLoginItem) { s.DidConfigureLoginItem = true; Save(); LaunchAtLogin = true; }
        else if (LoginItem.IsEnabled) LoginItem.SetEnabled(true);   // aggiorna il percorso se l'app è stata spostata
    }

    public string SortLabel => Labels.Of(SortKey);
    public IEnumerable<FolderMode> FolderModes => Enum.GetValues<FolderMode>();

    // MARK: Elenco visibile

    public bool IsImported(Clip c) => importedKeys.Contains(c.Key);
    public Flag FlagOf(Clip c) => flags.TryGetValue(c.Key, out var f) ? f : Flag.None;
    public bool IsRejected(Clip c) => FlagOf(c) == Flag.Reject;

    public List<Clip> FilteredClips => clips.Where(MediaFilter.Includes).ToList();
    public List<Clip> NewClips => FilteredClips.Where(c => !IsImported(c)).ToList();

    public List<Clip> VisibleClips
    {
        get
        {
            IEnumerable<Clip> list = FilteredClips;
            if (HideImported) list = list.Where(c => !IsImported(c));
            Func<Clip, IComparable> key = SortKey switch
            {
                SortKey.Name => c => c.Name,
                SortKey.Duration => c => c.Duration ?? 0,
                SortKey.Size => c => c.Size,
                _ => c => c.Date,
            };
            var sorted = SortKey == SortKey.Name
                ? list.OrderBy(c => c.Name, NaturalComparer.Instance)
                : list.OrderBy(key);
            return (Ascending ? sorted : sorted.Reverse()).ToList();
        }
    }

    public List<Clip> SelectedClips => VisibleClips.Where(c => selection.Contains(c.Path)).ToList();
    public int SelectionCount => selection.Count;

    /// <summary>Ricostruisce le sezioni della griglia.</summary>
    public void Rebuild()
    {
        var visible = VisibleClips;
        var result = new List<DaySection>();
        if (SortKey == SortKey.Date)
        {
            foreach (var c in visible)
            {
                var day = c.Date.Date;
                if (result.Count > 0 && result[^1].Day == day) result[^1].Items.Add(Item(c));
                else result.Add(new DaySection(day, new List<ClipItem> { Item(c) }));
            }
        }
        else if (visible.Count > 0) result.Add(new DaySection(null, visible.Select(Item).ToList()));

        Sections.Clear();
        foreach (var sec in result) Sections.Add(sec);
        RefreshItemStates();
        RaiseView();
    }

    ClipItem Item(Clip c)
    {
        if (!items.TryGetValue(c.Path, out var item)) items[c.Path] = item = new ClipItem(c);
        else if (!ReferenceEquals(item.Clip, c)) item.Update(c);
        return item;
    }

    void RefreshItemStates()
    {
        foreach (var sec in Sections)
        {
            foreach (var it in sec.Items)
            {
                it.IsSelected = selection.Contains(it.Clip.Path);
                it.IsImported = IsImported(it.Clip);
                it.Flag = FlagOf(it.Clip);
            }
            sec.AllSelected = sec.Items.Count > 0 && sec.Items.All(i => i.IsSelected);
        }
        RaiseButtons();
        Raise(nameof(StatusText));
    }

    void RaiseView()
    {
        Raise(nameof(ShowScanning)); Raise(nameof(ShowEmpty)); Raise(nameof(ShowFilterEmpty)); Raise(nameof(ShowAllImported));
        Raise(nameof(ShowGrid)); Raise(nameof(StatusText)); Raise(nameof(FilterEmptyTitle)); Raise(nameof(FilterEmptySubtitle));
        Raise(nameof(EmptySubtitle)); Raise(nameof(ScanningText));
        RaiseButtons();
    }

    void RaiseButtons()
    {
        Raise(nameof(ImportButtonTitle)); Raise(nameof(CanImport)); Raise(nameof(WillMove)); Raise(nameof(ImportButtonTooltip));
        Raise(nameof(DestinationPreview)); Raise(nameof(UsingPicks));
    }

    public bool ShowScanning => scanning;
    public bool ShowEmpty => !scanning && clips.Count == 0;
    public bool ShowFilterEmpty => !scanning && clips.Count > 0 && FilteredClips.Count == 0;
    public bool ShowAllImported => !scanning && FilteredClips.Count > 0 && VisibleClips.Count == 0;
    public bool ShowGrid => !scanning && VisibleClips.Count > 0;
    public string ScanningText => IsVolume ? L("Reading the card…") : L("Reading the folder…");
    public string EmptySubtitle => IsVolume ? L("There's nothing to import on this card.")
                                            : L("There are no photos or videos in this folder. Anything you add will show up automatically.");
    public string FilterEmptyTitle => MediaFilter == MediaFilter.Photos ? L("No photos here") : L("No videos here");
    public string FilterEmptySubtitle => MediaFilter == MediaFilter.Photos ? L("There are only videos.") : L("There are only photos.");

    public string SummaryText
    {
        get
        {
            long total = clips.Sum(c => c.ImportSize);
            int fresh = clips.Count(c => !IsImported(c));
            return string.Join(" · ", Fmt.Items(clips), fresh == 1 ? L("1 new") : L("{0} new", fresh), Fmt.Bytes(total));
        }
    }

    /// <summary>Riga sotto il nome della sorgente: con una selezione, ricorda i tasti utili.</summary>
    public string StatusText
    {
        get
        {
            int n = SelectedClips.Count;
            if (n == 0) return SummaryText;
            var sel = n == 1 ? L("1 selected") : L("{0} selected", n);
            return sel + L(" · P pick · X reject · U unflag · Space preview · Del delete");
        }
    }

    /// <summary>Se ci sono clip nuove segnate come scelte, senza selezione il pulsante importa solo quelle.</summary>
    public bool UsingPicks => selection.Count == 0 && NewClips.Any(c => FlagOf(c) == Flag.Pick);

    /// <summary>La selezione, oppure (senza selezione) le nuove scelte se ci sono, altrimenti tutte le nuove. Mai le scartate.</summary>
    public List<Clip> ClipsToImport
    {
        get
        {
            List<Clip> list = selection.Count == 0
                ? (UsingPicks ? NewClips.Where(c => FlagOf(c) == Flag.Pick).ToList() : NewClips)
                : clips.Where(c => selection.Contains(c.Path)).OrderBy(c => c.Date).ToList();
            return list.Where(c => !IsRejected(c)).ToList();
        }
    }

    public bool WillMove => DeleteAfter != AltHeld;
    public string SourcePlace => IsVolume ? L("from the card") : L("from the folder");
    public bool CanImport => progress == null && ClipsToImport.Count > 0;

    public string ImportButtonTitle
    {
        get
        {
            var list = ClipsToImport;
            var size = Fmt.Bytes(list.Sum(c => c.ImportSize));
            bool move = WillMove;
            if (selection.Count == 0)
            {
                if (list.Count == 0) return L("Nothing new to import");
                bool picks = UsingPicks;
                if (list.Count == 1)
                {
                    bool photo = list[0].IsPhoto;
                    return (move, picks, photo) switch
                    {
                        (false, false, false) => L("Import the new clip · {0}", size),
                        (false, false, true) => L("Import the new photo · {0}", size),
                        (false, true, false) => L("Import the picked clip · {0}", size),
                        (false, true, true) => L("Import the picked photo · {0}", size),
                        (true, false, false) => L("Move the new clip · {0}", size),
                        (true, false, true) => L("Move the new photo · {0}", size),
                        (true, true, false) => L("Move the picked clip · {0}", size),
                        _ => L("Move the picked photo · {0}", size),
                    };
                }
                return (move, picks) switch
                {
                    (false, false) => L("Import {0} new · {1}", list.Count, size),
                    (false, true) => L("Import {0} picked · {1}", list.Count, size),
                    (true, false) => L("Move {0} new · {1}", list.Count, size),
                    _ => L("Move {0} picked · {1}", list.Count, size),
                };
            }
            return move ? L("Move {0} · {1}", Fmt.Items(list), size) : L("Import {0} · {1}", Fmt.Items(list), size);
        }
    }

    public string ImportButtonTooltip => UsingPicks
        ? L("Imports the new picked items (rejected ones are never imported)")
        : WillMove ? L("Copies, verifies byte by byte, then deletes the originals {0} (Ctrl+Alt+I)", SourcePlace)
                   : L("With nothing selected, imports everything new (Ctrl+I) · hold Alt to move");

    public string DeleteAfterLabel => L("Delete {0} after copying", SourcePlace);
    public string DeleteAfterTooltip => IsVolume
        ? L("Each file is deleted from the card only after verifying that the copy is identical")
        : L("Originals go to the Recycle Bin only after verifying that the copy is identical");

    public string DestinationDisplay
    {
        get
        {
            var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            return DestinationPath.StartsWith(home, StringComparison.OrdinalIgnoreCase) ? "~" + DestinationPath[home.Length..] : DestinationPath;
        }
    }

    public string DestinationPreview
    {
        get
        {
            var o = CurrentOptions(DeleteMode.Keep);
            var clip = ClipsToImport.FirstOrDefault() ?? clips.FirstOrDefault();
            if (clip == null) return "";
            var folder = Importer.FolderFor(clip, o, DateTime.Now);
            var parts = new List<string> { System.IO.Path.GetFileName(o.DestRoot.TrimEnd('\\')) };
            if (!string.Equals(folder, o.DestRoot, StringComparison.OrdinalIgnoreCase)) parts.Add(System.IO.Path.GetFileName(folder));
            parts.Add(Importer.TargetName(clip, o));
            return string.Join(" › ", parts);
        }
    }

    ImportOptions CurrentOptions(DeleteMode mode) => new()
    {
        DestRoot = DestinationPath, FolderMode = FolderMode, CustomName = CustomFolderName,
        CopySidecar = CopySidecar, CopyProxy = CopyProxy, RenameWithDate = RenameWithDate, DeleteOriginals = mode,
    };

    // MARK: Schede e cartelle

    public IEnumerable<Source> OrderedSources => Sources.Where(x => x.IsVolume).Concat(Sources.Where(x => !x.IsVolume));

    public async void VolumeMounted(string root, bool showWindow)
    {
        bool isCard = await Task.Run(() => CardScanner.IsCameraCard(root));
        if (!isCard) return;
        if (!Sources.Any(x => string.Equals(x.Path, root, StringComparison.OrdinalIgnoreCase)))
            Sources.Add(new Source(root, CardScanner.VolumeName(root), true));
        var source = Sources.First(x => string.Equals(x.Path, root, StringComparison.OrdinalIgnoreCase));
        if (progress == null) Open(source);
        if (showWindow && AutoOpen) WantsWindow?.Invoke();
    }

    public void VolumeUnmounted(string root)
    {
        foreach (var x in Sources.Where(x => x.IsVolume && string.Equals(x.Path, root, StringComparison.OrdinalIgnoreCase)).ToList()) Sources.Remove(x);
        if (current != null && current.IsVolume && string.Equals(current.Path, root, StringComparison.OrdinalIgnoreCase))
        {
            if (progress != null) cancelSource?.Cancel();
            Current = null; clips = new(); selection.Clear(); watcher?.Dispose(); watcher = null;
            Rebuild();
            if (OrderedSources.FirstOrDefault() is { } next) Open(next);
        }
    }

    /// <summary>All'avvio, se non c'è una scheda, riapre l'ultima cartella usata.</summary>
    public void RestoreLastFolder()
    {
        if (current == null && Sources.FirstOrDefault(x => !x.IsVolume) is { } first) Open(first);
    }

    public async void Open(Source source)
    {
        Current = source;
        clips = new(); selection.Clear(); anchor = null; pendingRescan = false;
        Scanning = true;
        Rebuild();
        if (!source.IsVolume) RememberFolder(source.Path);
        // Schede e cartelle sorvegliate: i file nuovi compaiono, quelli spostati via spariscono
        watcher?.Dispose();
        watcher = new FolderWatcher(source.Path, () => ui.BeginInvoke(ScheduleRescan));
        var path = source.Path; bool deep = !source.IsVolume;
        var found = await Task.Run(() => CardScanner.Scan(path, deep));
        if (current?.Path != path) return;
        clips = found;
        Scanning = false;
        Rebuild();
    }

    /// <summary>Rilegge la sorgente attuale senza perdere la selezione.</summary>
    public async void Refresh()
    {
        if (current is not { } source || scanning) return;
        if (progress != null) { pendingRescan = true; return; }
        if (!Directory.Exists(source.Path)) { if (!source.IsVolume) RemoveSource(source); return; }
        var path = source.Path; bool deep = !source.IsVolume;
        var found = await Task.Run(() => CardScanner.Scan(path, deep));
        if (current?.Path != path) return;
        clips = found;
        var ids = new HashSet<string>(found.Select(c => c.Path), StringComparer.OrdinalIgnoreCase);
        selection.IntersectWith(ids);
        if (anchor != null && !ids.Contains(anchor)) anchor = null;
        Rebuild();
    }

    void ScheduleRescan()
    {
        var token = ++rescanToken;
        var t = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1.5) };
        t.Tick += (_, _) => { t.Stop(); if (token == rescanToken) Refresh(); };
        t.Start();
    }

    void RememberFolder(string path)
    {
        var list = s.RecentFolders.Where(p => !string.Equals(p, path, StringComparison.OrdinalIgnoreCase)).ToList();
        list.Insert(0, path);
        s.RecentFolders = list.Take(8).ToList();
        Save();
    }

    /// <summary>Toglie una cartella dall'elenco (non cancella niente dal disco).</summary>
    public void RemoveSource(Source source)
    {
        if (source.IsVolume || progress != null) return;
        foreach (var x in Sources.Where(x => string.Equals(x.Path, source.Path, StringComparison.OrdinalIgnoreCase)).ToList()) Sources.Remove(x);
        s.RecentFolders = s.RecentFolders.Where(p => !string.Equals(p, source.Path, StringComparison.OrdinalIgnoreCase)).ToList();
        Save();
        if (current != null && string.Equals(current.Path, source.Path, StringComparison.OrdinalIgnoreCase))
        {
            Current = null; clips = new(); selection.Clear(); watcher?.Dispose(); watcher = null;
            Rebuild();
            if (OrderedSources.FirstOrDefault() is { } next) Open(next);
        }
    }

    public void ChooseSourceFolder()
    {
        if (progress != null) return;
        var dlg = new OpenFolderDialog { Title = L("Choose a card or a folder that contains video clips or photos") };
        var start = current is { IsVolume: false } c ? c.Path : s.RecentFolders.FirstOrDefault();
        if (start != null && Directory.Exists(start)) dlg.InitialDirectory = start;
        WantsWindow?.Invoke();
        if (dlg.ShowDialog(Application.Current.MainWindow) != true) return;
        var path = dlg.FolderName;
        var root = System.IO.Path.GetPathRoot(path);
        bool isDriveRoot = string.Equals(root, path.TrimEnd('\\') + "\\", StringComparison.OrdinalIgnoreCase);
        var source = Sources.FirstOrDefault(x => string.Equals(x.Path.TrimEnd('\\'), path.TrimEnd('\\'), StringComparison.OrdinalIgnoreCase))
                     ?? (isDriveRoot ? new Source(root!, CardScanner.VolumeName(root!), IsRemovable(root!))
                                     : new Source(path, System.IO.Path.GetFileName(path.TrimEnd('\\')), false));
        if (!Sources.Contains(source)) Sources.Add(source);
        Open(source);
    }

    public static bool IsRemovable(string root)
    {
        try { return new DriveInfo(root).DriveType == DriveType.Removable; } catch { return false; }
    }

    public void RevealCurrent() { if (current != null) ShellActions.Reveal(new[] { current.Path }); }

    public void ChooseDestination()
    {
        var dlg = new OpenFolderDialog { Title = L("Choose where to import your clips") };
        if (Directory.Exists(DestinationPath)) dlg.InitialDirectory = DestinationPath;
        if (dlg.ShowDialog(Application.Current.MainWindow) == true) DestinationPath = dlg.FolderName;
    }

    public async void Eject()
    {
        if (current is not { IsVolume: true } source || progress != null) return;
        var root = source.Path;
        watcher?.Dispose(); watcher = null;
        bool ok = await Task.Run(() => ShellActions.Eject(root));
        if (!ok)
            Dialogs.Alert(L("Couldn't eject “{0}”", source.Name),
                          L("Quit the apps that are using the card and try again."));
    }

    // MARK: Selezione

    /// <summary>Clic sulla miniatura, come in Esplora file: Ctrl aggiunge/toglie, Maiusc seleziona un intervallo,
    /// un clic sull'unica selezionata la deseleziona, doppio clic apre.</summary>
    public void Click(Clip clip, bool ctrl, bool shift, int clickCount)
    {
        if (clickCount >= 2) { ShellActions.Open(clip.Path); return; }
        if (ctrl) Toggle(clip);
        else if (shift && anchor != null)
        {
            var list = VisibleClips;
            int a = list.FindIndex(c => c.Path == anchor), b = list.FindIndex(c => c.Path == clip.Path);
            if (a >= 0 && b >= 0) foreach (var c in list.GetRange(Math.Min(a, b), Math.Abs(a - b) + 1)) selection.Add(c.Path);
            else { selection.Clear(); selection.Add(clip.Path); anchor = clip.Path; }
        }
        else if (selection.Count == 1 && selection.Contains(clip.Path)) { selection.Clear(); anchor = null; }
        else { selection.Clear(); selection.Add(clip.Path); anchor = clip.Path; }
        RefreshItemStates();
    }

    public void Toggle(Clip clip)
    {
        if (!selection.Remove(clip.Path)) selection.Add(clip.Path);
        anchor = clip.Path;
        RefreshItemStates();
    }

    public bool IsSelected(Clip c) => selection.Contains(c.Path);
    public void SelectOnly(Clip c) { selection.Clear(); selection.Add(c.Path); anchor = c.Path; RefreshItemStates(); }
    public void SelectAll() { selection.Clear(); selection.UnionWith(VisibleClips.Select(c => c.Path)); RefreshItemStates(); }
    public void SelectNew() { selection.Clear(); selection.UnionWith(VisibleClips.Where(c => !IsImported(c) && !IsRejected(c)).Select(c => c.Path)); RefreshItemStates(); }
    public void SelectNone() { selection.Clear(); anchor = null; RefreshItemStates(); }
    public void SelectFlagged(Flag f) { selection.Clear(); selection.UnionWith(VisibleClips.Where(c => FlagOf(c) == f).Select(c => c.Path)); anchor = null; RefreshItemStates(); }

    public void ToggleDay(DaySection section)
    {
        var ids = section.Items.Select(i => i.Clip.Path).ToList();
        if (ids.All(selection.Contains)) selection.ExceptWith(ids); else selection.UnionWith(ids);
        RefreshItemStates();
    }

    /// <summary>Frecce ← →: clip precedente/successiva (Maiusc allarga la selezione). Restituisce la clip da mostrare.</summary>
    public Clip? MoveSelection(int step, bool extend)
    {
        var list = VisibleClips;
        if (list.Count == 0) return null;
        int from = anchor != null ? list.FindIndex(c => c.Path == anchor) : -1;
        if (from < 0) from = step > 0 ? list.FindLastIndex(c => selection.Contains(c.Path)) : list.FindIndex(c => selection.Contains(c.Path));
        int target = from >= 0 ? Math.Clamp(from + step, 0, list.Count - 1) : (step > 0 ? 0 : list.Count - 1);
        var clip = list[target];
        if (!extend) selection.Clear();
        selection.Add(clip.Path);
        anchor = clip.Path;
        RefreshItemStates();
        return clip;
    }

    public void SetImported(Clip clip, bool imported)
    {
        if (imported) importedKeys.Add(clip.Key); else importedKeys.Remove(clip.Key);
        ImportedStore.Save(importedKeys);
        RefreshItemStates();
        Raise(nameof(SummaryText));
        if (HideImported) Rebuild();
    }

    // MARK: Etichette (P / X / U, come in Lightroom)

    public void FlagSelection(Flag f)
    {
        var list = SelectedClips;
        if (list.Count == 0) { SystemSounds.Beep.Play(); return; }
        foreach (var c in list)
        {
            // Premere di nuovo lo stesso tasto toglie l'etichetta
            var newFlag = list.Count == 1 && FlagOf(c) == f ? Flag.None : f;
            if (newFlag == Flag.None) flags.Remove(c.Key); else flags[c.Key] = newFlag;
        }
        FlagStore.Save(flags);
        RefreshItemStates();
    }

    /// <summary>Dal segnalibro: se la clip fa parte di una selezione multipla agisce su tutte, altrimenti solo su lei.</summary>
    public void ToggleFlag(Flag f, Clip clip)
    {
        if (selection.Contains(clip.Path) && selection.Count > 1) { FlagSelection(FlagOf(clip) == f ? Flag.None : f); return; }
        if (FlagOf(clip) == f) flags.Remove(clip.Key); else flags[clip.Key] = f;
        FlagStore.Save(flags);
        RefreshItemStates();
    }

    public void SetFlag(Flag f, Clip clip)
    {
        if (selection.Contains(clip.Path) && selection.Count > 1) { FlagSelection(f); return; }
        if (f == Flag.None) flags.Remove(clip.Key); else flags[clip.Key] = f;
        FlagStore.Save(flags);
        RefreshItemStates();
    }

    public int RejectedCount => FilteredClips.Count(IsRejected);

    // MARK: Appunti ed eliminazione

    /// <summary>Ctrl+C: mette i file negli appunti, da incollare in Esplora file (Ctrl+V).</summary>
    public void CopySelection()
    {
        var list = SelectedClips;
        if (list.Count == 0) { SystemSounds.Beep.Play(); return; }
        var files = new StringCollection();
        foreach (var c in list)
        {
            files.Add(c.Path);
            foreach (var x in c.Companions) files.Add(x);
            if (CopySidecar && c.SidecarPath != null) files.Add(c.SidecarPath);
        }
        try { Clipboard.SetFileDropList(files); } catch { }
        ShowBanner(L("{0} copied · paste them in File Explorer with Ctrl+V", Fmt.Items(list)));
    }

    public IEnumerable<string> DragPaths(Clip clip)
    {
        var list = selection.Contains(clip.Path) ? SelectedClips : new List<Clip> { clip };
        return list.SelectMany(c => new[] { c.Path }.Concat(c.Companions));
    }

    /// <summary>Canc: dalla scheda elimina per sempre (con conferma), dalle cartelle sposta nel Cestino.</summary>
    public void DeleteSelection()
    {
        var list = SelectedClips;
        if (list.Count == 0 || progress != null || current is not { } source) { SystemSounds.Beep.Play(); return; }
        if (source.IsVolume)
        {
            int notImported = list.Count(c => !IsImported(c));
            var title = list.Count == 1 ? L("Delete “{0}” from the card?", list[0].Name) : L("Delete {0} from the card?", Fmt.Items(list));
            var info = L("Related files (XML, thumbnail, proxy, RAW) are deleted too. This can't be undone.");
            if (notImported > 0)
            {
                var warn = notImported == list.Count
                    ? (list.Count == 1 ? L("⚠️ It hasn't been imported yet.\n\n") : L("⚠️ None of them has been imported yet.\n\n"))
                    : L("⚠️ {0} haven't been imported yet.\n\n", notImported);
                info = warn + info;
            }
            // Se si perde qualcosa di mai importato, Invio annulla
            var (ok, _) = Dialogs.Confirm(title, info, L("Delete"), destructive: true, cancelIsDefault: notImported > 0);
            if (!ok) return;
        }
        var mode = source.IsVolume ? DeleteMode.Permanent : DeleteMode.RecycleBin;
        var deleted = new List<Clip>();
        var failures = new List<string>();
        var sony = new Dictionary<string, List<string>>(StringComparer.OrdinalIgnoreCase);
        foreach (var c in list)
        {
            try
            {
                Importer.DeleteOriginals(c, mode);
                deleted.Add(c);
                var dir = System.IO.Path.GetDirectoryName(c.Path)!;
                if (System.IO.Path.GetFileName(dir).Equals("CLIP", StringComparison.OrdinalIgnoreCase))
                {
                    var root = System.IO.Path.GetDirectoryName(dir)!;
                    if (!sony.TryGetValue(root, out var l)) sony[root] = l = new List<string>();
                    l.Add(c.Name);
                }
            }
            catch (Exception e) { failures.Add($"• {c.Name}: {e.Message}"); }
        }
        foreach (var (root, names) in sony) SonyIndex.Remove(names, root);
        var gone = new HashSet<string>(deleted.Select(c => c.Path), StringComparer.OrdinalIgnoreCase);
        clips = clips.Where(c => !gone.Contains(c.Path)).ToList();
        selection.ExceptWith(gone);
        Rebuild();
        if (deleted.Count > 0)
        {
            SystemSounds.Asterisk.Play();
            ShowBanner(source.IsVolume ? L("{0} deleted from the card", Fmt.Items(deleted))
                                       : L("{0} moved to the Recycle Bin", Fmt.Items(deleted)));
        }
        if (failures.Count > 0) Dialogs.Alert(L("Some files couldn't be deleted"), string.Join("\n", failures.Take(10)));
    }

    public void DeleteRejected()
    {
        selection.Clear();
        selection.UnionWith(VisibleClips.Where(IsRejected).Select(c => c.Path));
        if (selection.Count == 0) { SystemSounds.Beep.Play(); return; }
        RefreshItemStates();
        DeleteSelection();
    }

    // MARK: Importazione

    public void StartImport() => ImportClips(ClipsToImport, WillMove);
    public void StartMove() => ImportClips(ClipsToImport, true);

    public async void ImportClips(List<Clip> list, bool? move = null)
    {
        if (list.Count == 0 || progress != null) return;
        bool doMove = move ?? DeleteAfter;
        var mode = DeleteMode.Keep;
        if (doMove)
        {
            if (!ConfirmMoveOnce(list)) return;
            // Sulla scheda il Cestino non libera spazio: si cancella. Dalle cartelle del PC, nel Cestino.
            mode = current?.IsVolume ?? false ? DeleteMode.Permanent : DeleteMode.RecycleBin;
        }
        var options = CurrentOptions(mode);

        if (FolderMode == FolderMode.Custom && Importer.Sanitize(CustomFolderName).Length == 0)
        {
            Dialogs.Alert(L("Folder name missing"), L("Type a folder name at the bottom, or pick another option under “Organize”."));
            return;
        }
        long needed = list.Sum(c => c.ImportSize + (CopyProxy ? c.ProxySize : 0));
        if (Importer.FreeSpace(options.DestRoot) is long free && free < needed)
        {
            Dialogs.Alert(L("Not enough space"), L("{0} needed, but the destination only has {1} free.", Fmt.Bytes(needed), Fmt.Bytes(free)));
            return;
        }

        cancelSource = new CancellationTokenSource();
        var token = cancelSource.Token;
        Progress = new ImportProgress { FileCount = list.Count, CurrentName = list[0].Name, BytesTotal = needed, StartedAt = DateTime.Now };
        AltHeld = false;
        RaiseButtons();
        string? volume = current is { IsVolume: true } v ? v.Path : null;
        bool fromVolume = volume != null;

        var result = await Task.Run(() => Importer.Run(list, options, token, p => ui.BeginInvoke(() => { if (Progress != null) Progress = p; })));
        FinishImport(result, volume);
    }

    public void CancelImport() => cancelSource?.Cancel();

    void FinishImport(ImportResult r, string? volume)
    {
        cancelSource = null;
        Progress = null;
        foreach (var c in r.Imported.Concat(r.Skipped)) importedKeys.Add(c.Key);
        ImportedStore.Save(importedKeys);
        selection.ExceptWith(r.Imported.Concat(r.Skipped).Select(c => c.Path));
        if (pendingRescan || r.Deleted.Count > 0) { pendingRescan = false; Refresh(); }
        RefreshItemStates();
        Raise(nameof(SummaryText));
        if (HideImported) Rebuild();

        string message;
        if (r.Cancelled) message = L("Import cancelled · {0} copied", Fmt.Items(r.Imported));
        else
        {
            message = L("Imported: {0}", Fmt.Items(r.Imported));
            if (r.Skipped.Count > 0) message += L(" · {0} were already there", r.Skipped.Count);
        }
        if (r.Deleted.Count > 0)
        {
            long freed = r.Deleted.Sum(c => c.ImportSize + c.ProxySize);
            message += L(" · {0} freed {1}", Fmt.Bytes(freed), SourcePlace);
        }
        ShowBanner(message);
        SystemSounds.Asterisk.Play();

        if (r.Failed.Count > 0)
            Dialogs.Alert(L("Some items weren't imported"), string.Join("\n", r.Failed.Take(10).Select(f => $"• {f.Clip.Name}: {f.Message}")));
        if (r.DeleteFailures.Count > 0)
            Dialogs.Alert(L("Imported, but not deleted {0}", SourcePlace),
                          L("The copies are safe; the originals were left where they were.") + "\n\n" +
                          string.Join("\n", r.DeleteFailures.Take(10).Select(f => $"• {f.Clip.Name}: {f.Message}")));
        if (RevealAfter && !r.Cancelled && r.Files.Count > 0) ShellActions.Reveal(r.Files);
        if (EjectAfter && !r.Cancelled && r.Failed.Count == 0 && volume != null)
        {
            var root = volume;
            watcher?.Dispose(); watcher = null;
            Task.Run(() => ShellActions.Eject(root)).ContinueWith(t =>
            {
                if (!t.Result) ui.BeginInvoke(() => Dialogs.Alert(L("Imported, but the card couldn't be ejected"),
                                                                  L("Quit the apps that are using the card and try again.")));
            });
        }
    }

    /// <summary>La prima volta che si sposta, spiega cosa succede (con "Non chiedere più").</summary>
    bool ConfirmMoveOnce(List<Clip> list)
    {
        if (s.MoveConfirmed) return true;
        bool toBin = !(current?.IsVolume ?? true);
        var note = toBin ? L(" (moved to the Recycle Bin)") : "";
        var (ok, dontAsk) = Dialogs.Confirm(
            L("Move {0} {1}?", Fmt.Items(list), SourcePlace),
            L("Each file is copied, read back from the destination and compared byte by byte with the original. Only if it's identical is the original deleted {0}{1}.\n\nIf anything goes wrong, or you cancel, the original stays where it is.", SourcePlace, note),
            L("Move"), checkbox: L("Don't ask again"));
        if (ok && dontAsk) { s.MoveConfirmed = true; Save(); }
        return ok;
    }

    // MARK: Messaggi

    public void ShowBanner(string text)
    {
        var token = ++bannerToken;
        Banner = text;
        var t = new DispatcherTimer { Interval = TimeSpan.FromSeconds(5) };
        t.Tick += (_, _) => { t.Stop(); if (token == bannerToken) Banner = null; };
        t.Start();
    }

    public bool ConfirmQuit()
    {
        if (progress == null) return true;
        bool stop = Dialogs.Choose(L("An import is in progress"), L("If you quit now, the item being copied won't be saved."),
                                   L("Keep importing"), L("Stop and quit"));
        if (stop) CancelImport();
        return stop;
    }
}

/// <summary>Ordinamento "naturale" dei nomi (C2 prima di C10), come Esplora file.</summary>
public sealed class NaturalComparer : IComparer<string>
{
    public static readonly NaturalComparer Instance = new();
    [System.Runtime.InteropServices.DllImport("shlwapi.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
    static extern int StrCmpLogicalW(string a, string b);
    public int Compare(string? x, string? y)
    {
        try { return StrCmpLogicalW(x ?? "", y ?? ""); }
        catch { return string.Compare(x, y, StringComparison.OrdinalIgnoreCase); }
    }
}
