using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Input;
using System.Windows.Media;

namespace ClipImporter;

public partial class MainWindow : Window
{
    readonly AppState state = AppState.Shared;
    Point dragStart;
    ClipItem? pressed;
    bool pressedOnButton;

    public MainWindow()
    {
        InitializeComponent();
        DataContext = state;
        ApplyTexts();
        SourceInitialized += (_, _) => Dwm.ApplyDarkTitleBar(this, Theme.IsDark);
        PreviewKeyDown += OnPreviewKeyDown;
        PreviewKeyUp += (_, _) => UpdateAlt();
        Deactivated += (_, _) => state.AltHeld = false;
        state.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName is nameof(AppState.WillMove) or nameof(AppState.ImportButtonTitle))
                ImportIcon.Text = state.WillMove ? "" : "";   // forbici / scarica
            if (e.PropertyName is nameof(AppState.IsVolume) or nameof(AppState.Current))
                SourceIcon.Text = state.IsVolume ? "" : "";
        };
        foreach (var m in state.FolderModes) FolderModeBox.Items.Add(new ComboBoxItem { Content = Labels.Of(m), Tag = m });
        FolderModeBox.SelectedIndex = (int)state.FolderMode;
    }

    void ApplyTexts()
    {
        ChangeFolderButton.Content = L("Change folder…");
        ChangeFolderButton.ToolTip = L("Choose another folder to import from");
        RefreshButton.ToolTip = L("Re-read the folder (F5) · new clips show up automatically anyway");
        EjectButton.ToolTip = L("Eject the card");
        SizePanel.ToolTip = L("Thumbnail size");
        SelectMenuButton.Content = L("Select");
        HideImportedBox.Content = L("Hide imported");
        SortButton.ToolTip = L("Sorting");
        FilterAll.Content = L("All");
        FilterVideos.Content = L("Videos");
        FilterPhotos.Content = L("Photos");
        FilterBar.ToolTip = L("Show photos and videos, only videos or only photos");
        WelcomeTitle.Text = L("Insert your camera's SD card");
        WelcomeText.Text = L("Clip Importer opens by itself when you insert a card and shows you what to import. You can close this window: it keeps running in the notification area.");
        WelcomeBrowse.Content = L("Browse a folder…");
        EmptyTitle.Text = L("No photos or videos here");
        EmptyBrowse.Content = L("Choose another folder…");
        ShowAllButton.Content = L("Show all");
        AllImportedTitle.Text = L("You've already imported everything");
        AllImportedText.Text = L("Uncheck “Hide imported” to see them again.");
        ImportToLabel.Text = L("IMPORT TO");
        OrganizeLabel.Text = L("ORGANIZE");
        ChangeDestButton.Content = L("Change…");
        OptionsButton.ToolTip = L("Options");
        CancelButton.Content = L("Cancel");
    }

    // MARK: Menu

    static MenuItem Item(string header, Action action, bool isChecked = false, bool enabled = true, string? gesture = null)
    {
        var mi = new MenuItem { Header = header, IsChecked = isChecked, IsEnabled = enabled, InputGestureText = gesture ?? "" };
        mi.Click += (_, _) => action();
        return mi;
    }

    static void Open(FrameworkElement target, ContextMenu menu)
    {
        menu.PlacementTarget = target;
        menu.Placement = System.Windows.Controls.Primitives.PlacementMode.Bottom;
        menu.IsOpen = true;
    }

    void SourceButton_Click(object sender, RoutedEventArgs e)
    {
        var menu = new ContextMenu();
        foreach (var src in state.OrderedSources)
        {
            var s = src;
            menu.Items.Add(Item(s.Name, () => { if (state.Current != s) state.Open(s); }, isChecked: state.Current == s));
        }
        menu.Items.Add(new Separator());
        menu.Items.Add(Item(L("Browse another folder…"), state.ChooseSourceFolder, gesture: "Ctrl+O"));
        menu.Items.Add(Item(L("Refresh"), state.Refresh, gesture: "F5"));
        menu.Items.Add(Item(L("Show in File Explorer"), state.RevealCurrent));
        if (state.Current is { IsVolume: false } cur)
        {
            menu.Items.Add(new Separator());
            menu.Items.Add(Item(L("Remove “{0}” from the list", cur.Name), () => state.RemoveSource(cur)));
        }
        Open((FrameworkElement)sender, menu);
    }

    void Sort_Click(object sender, RoutedEventArgs e)
    {
        var menu = new ContextMenu();
        foreach (var k in Enum.GetValues<SortKey>())
        {
            var key = k;
            menu.Items.Add(Item(Labels.Of(key), () => state.SortKey = key, isChecked: state.SortKey == key));
        }
        menu.Items.Add(new Separator());
        bool date = state.SortKey == SortKey.Date;
        menu.Items.Add(Item(date ? L("Oldest first") : L("Ascending"), () => state.Ascending = true, isChecked: state.Ascending));
        menu.Items.Add(Item(date ? L("Newest first") : L("Descending"), () => state.Ascending = false, isChecked: !state.Ascending));
        Open((FrameworkElement)sender, menu);
    }

    void SelectMenu_Click(object sender, RoutedEventArgs e)
    {
        var menu = new ContextMenu();
        menu.Items.Add(Item(L("Select all"), state.SelectAll, gesture: "Ctrl+A"));
        menu.Items.Add(Item(L("Select only new"), state.SelectNew, gesture: "Ctrl+Shift+A"));
        menu.Items.Add(Item(L("Deselect all"), state.SelectNone, gesture: "Esc"));
        menu.Items.Add(new Separator());
        menu.Items.Add(Item(L("Select picked"), () => state.SelectFlagged(Flag.Pick)));
        menu.Items.Add(Item(L("Select rejected"), () => state.SelectFlagged(Flag.Reject)));
        menu.Items.Add(new Separator());
        menu.Items.Add(Item(state.IsVolume ? L("Delete rejected from card…") : L("Move rejected to the Recycle Bin"),
                            state.DeleteRejected, enabled: state.RejectedCount > 0 && state.NotImporting, gesture: "Ctrl+Shift+Del"));
        Open((FrameworkElement)sender, menu);
    }

    void Options_Click(object sender, RoutedEventArgs e)
    {
        var menu = new ContextMenu();
        menu.Items.Add(Item(L("Also copy Sony XML metadata files"), () => state.CopySidecar = !state.CopySidecar, state.CopySidecar));
        menu.Items.Add(Item(L("Also copy proxies (in a “Proxy” folder, ready for DaVinci Resolve)"), () => state.CopyProxy = !state.CopyProxy, state.CopyProxy));
        menu.Items.Add(Item(L("Add date and time to file names"), () => state.RenameWithDate = !state.RenameWithDate, state.RenameWithDate));
        menu.Items.Add(new Separator());
        menu.Items.Add(Item(L("Show in File Explorer when done"), () => state.RevealAfter = !state.RevealAfter, state.RevealAfter));
        menu.Items.Add(Item(L("Eject the card when done"), () => state.EjectAfter = !state.EjectAfter, state.EjectAfter));
        menu.Items.Add(new Separator());
        menu.Items.Add(Item(L("Open automatically when a card is inserted"), () => state.AutoOpen = !state.AutoOpen, state.AutoOpen));
        menu.Items.Add(Item(L("Start at login"), () => state.LaunchAtLogin = !state.LaunchAtLogin, state.LaunchAtLogin));
        Open((FrameworkElement)sender, menu);
    }

    void ChangeFolder_Click(object sender, RoutedEventArgs e) => state.ChooseSourceFolder();
    void Refresh_Click(object sender, RoutedEventArgs e) => state.Refresh();
    void Eject_Click(object sender, RoutedEventArgs e) => state.Eject();
    void ShowAll_Click(object sender, RoutedEventArgs e) => state.MediaFilter = MediaFilter.All;
    void ChangeDest_Click(object sender, RoutedEventArgs e) => state.ChooseDestination();
    void Import_Click(object sender, RoutedEventArgs e) => state.StartImport();
    void CancelImport_Click(object sender, RoutedEventArgs e) => state.CancelImport();
    void SelectDay_Click(object sender, RoutedEventArgs e) { if ((sender as FrameworkElement)?.DataContext is DaySection d) state.ToggleDay(d); }

    void FolderMode_Changed(object sender, SelectionChangedEventArgs e)
    {
        if (FolderModeBox.SelectedItem is ComboBoxItem { Tag: FolderMode m }) state.FolderMode = m;
    }

    // MARK: Miniature

    void Card_Loaded(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.DataContext is ClipItem item) item.EnsureThumbnail();
    }

    static bool IsInsideButton(DependencyObject? d)
    {
        while (d != null && d is not Border { Name: "Card" })
        {
            if (d is System.Windows.Controls.Primitives.ButtonBase) return true;
            d = d is Visual or System.Windows.Media.Media3D.Visual3D ? VisualTreeHelper.GetParent(d) : LogicalTreeHelper.GetParent(d);
        }
        return false;
    }

    void Card_MouseDown(object sender, MouseButtonEventArgs e)
    {
        pressed = (sender as FrameworkElement)?.DataContext as ClipItem;
        pressedOnButton = IsInsideButton(e.OriginalSource as DependencyObject);
        dragStart = e.GetPosition(this);
        if (pressed != null && !pressedOnButton && e.ClickCount >= 2)
        {
            state.Click(pressed.Clip, false, false, 2);
            pressed = null;
            e.Handled = true;
        }
    }

    void Card_MouseUp(object sender, MouseButtonEventArgs e)
    {
        var item = (sender as FrameworkElement)?.DataContext as ClipItem;
        if (item == null || item != pressed || pressedOnButton) { pressed = null; return; }
        pressed = null;
        var mods = Keyboard.Modifiers;
        state.Click(item.Clip, mods.HasFlag(ModifierKeys.Control), mods.HasFlag(ModifierKeys.Shift), 1);
        e.Handled = true;
    }

    /// <summary>Trascina le clip in Esplora file o in un programma di montaggio.</summary>
    void Card_MouseMove(object sender, MouseEventArgs e)
    {
        if (e.LeftButton != MouseButtonState.Pressed || pressed == null || pressedOnButton) return;
        var p = e.GetPosition(this);
        if (Math.Abs(p.X - dragStart.X) < SystemParameters.MinimumHorizontalDragDistance &&
            Math.Abs(p.Y - dragStart.Y) < SystemParameters.MinimumVerticalDragDistance) return;
        var paths = state.DragPaths(pressed.Clip).ToArray();
        pressed = null;
        var data = new DataObject(DataFormats.FileDrop, paths);
        try { DragDrop.DoDragDrop((DependencyObject)sender, data, DragDropEffects.Copy); } catch { }
    }

    void EmptyArea_Click(object sender, MouseButtonEventArgs e)
    {
        // Clic sullo spazio vuoto: deseleziona
        if (e.Handled) return;
        if (e.OriginalSource is ScrollViewer || e.OriginalSource is ItemsPresenter || e.OriginalSource is WrapPanel || e.OriginalSource is StackPanel)
            state.SelectNone();
    }

    void Ribbon_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.DataContext is not ClipItem item) return;
        // Clic: scelta sì/no · Alt+clic: scartata
        if (Keyboard.Modifiers.HasFlag(ModifierKeys.Alt)) state.ToggleFlag(Flag.Reject, item.Clip);
        else if (item.Flag == Flag.Reject) state.SetFlag(Flag.None, item.Clip);
        else state.ToggleFlag(Flag.Pick, item.Clip);
        e.Handled = true;
    }

    void Ribbon_RightClick(object sender, MouseButtonEventArgs e)
    {
        if ((sender as FrameworkElement)?.DataContext is not ClipItem item) return;
        var menu = new ContextMenu();
        menu.Items.Add(Item(item.Flag == Flag.Pick ? L("Picked ✓ (P)") : L("Pick (P)"), () => state.ToggleFlag(Flag.Pick, item.Clip)));
        menu.Items.Add(Item(item.Flag == Flag.Reject ? L("Rejected ✓ (X)") : L("Reject (X)"), () => state.ToggleFlag(Flag.Reject, item.Clip)));
        if (item.Flag != Flag.None) menu.Items.Add(Item(L("Remove flag (U)"), () => state.SetFlag(Flag.None, item.Clip)));
        Open((FrameworkElement)sender, menu);
        e.Handled = true;
    }

    void SelectCircle_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.DataContext is ClipItem item) state.Toggle(item.Clip);
        e.Handled = true;
    }

    void Card_ContextMenuOpening(object sender, ContextMenuEventArgs e)
    {
        var card = (FrameworkElement)sender;
        if (card.DataContext is not ClipItem item || card.ContextMenu is not ContextMenu menu) return;
        var clip = item.Clip;
        // Il menu agisce sulla selezione se la clip ne fa parte, altrimenti solo su di lei
        void Focus() { if (!state.IsSelected(clip)) state.SelectOnly(clip); }
        menu.Items.Clear();
        menu.Items.Add(Item(clip.IsPhoto ? L("Open") : L("Play"), () => ShellActions.Open(clip.Path)));
        menu.Items.Add(Item(L("Show in File Explorer"), () => ShellActions.Reveal(new[] { clip.Path })));
        menu.Items.Add(Item(L("Copy"), () => { Focus(); state.CopySelection(); }, gesture: "Ctrl+C"));
        menu.Items.Add(new Separator());
        menu.Items.Add(Item(clip.IsPhoto ? L("Import only this photo") : L("Import only this clip"),
                            () => state.ImportClips(new List<Clip> { clip }, false), enabled: state.NotImporting));
        menu.Items.Add(Item(clip.IsPhoto ? L("Move only this photo (delete {0})", state.SourcePlace) : L("Move only this clip (delete {0})", state.SourcePlace),
                            () => state.ImportClips(new List<Clip> { clip }, true), enabled: state.NotImporting));
        menu.Items.Add(new Separator());
        var flag = item.Flag;
        menu.Items.Add(Item(flag == Flag.Pick ? L("Picked ✓ (P)") : L("Mark as picked (P)"), () => { Focus(); if (flag != Flag.Pick || state.SelectionCount > 1) state.FlagSelection(Flag.Pick); }));
        menu.Items.Add(Item(flag == Flag.Reject ? L("Rejected ✓ (X)") : L("Mark as rejected (X)"), () => { Focus(); if (flag != Flag.Reject || state.SelectionCount > 1) state.FlagSelection(Flag.Reject); }));
        if (flag != Flag.None) menu.Items.Add(Item(L("Remove flag (U)"), () => { Focus(); state.FlagSelection(Flag.None); }));
        menu.Items.Add(new Separator());
        bool imported = item.IsImported;
        menu.Items.Add(Item(imported ? L("Mark as not imported") : L("Mark as already imported"), () => state.SetImported(clip, !imported)));
        menu.Items.Add(new Separator());
        menu.Items.Add(Item(state.IsVolume ? L("Delete from card…") : L("Move to the Recycle Bin"),
                            () => { Focus(); state.DeleteSelection(); }, enabled: state.NotImporting, gesture: "Del"));
    }

    // MARK: Tastiera

    void UpdateAlt()
    {
        bool alt = Keyboard.Modifiers.HasFlag(ModifierKeys.Alt);
        if (state.AltHeld != alt) state.AltHeld = alt;
    }

    void OnPreviewKeyDown(object sender, KeyEventArgs e)
    {
        UpdateAlt();
        var key = e.Key == Key.System ? e.SystemKey : e.Key;
        var mods = Keyboard.Modifiers;
        bool ctrl = mods.HasFlag(ModifierKeys.Control), shift = mods.HasFlag(ModifierKeys.Shift), alt = mods.HasFlag(ModifierKeys.Alt);
        bool inText = Keyboard.FocusedElement is TextBox;

        // Scorciatoie con Ctrl (valgono ovunque, tranne quelle di testo nei campi di testo)
        if (ctrl)
        {
            switch (key)
            {
                case Key.O: state.ChooseSourceFolder(); e.Handled = true; return;
                case Key.I when alt: state.StartMove(); e.Handled = true; return;
                case Key.I: if (state.CanImport) state.StartImport(); e.Handled = true; return;
                case Key.E: state.Eject(); e.Handled = true; return;
                case Key.W: Close(); e.Handled = true; return;
                case Key.R: state.Refresh(); e.Handled = true; return;
                case Key.Delete when shift: state.DeleteRejected(); e.Handled = true; return;
            }
            if (!inText)
            {
                switch (key)
                {
                    case Key.A when shift: state.SelectNew(); e.Handled = true; return;
                    case Key.A: state.SelectAll(); e.Handled = true; return;
                    case Key.C: state.CopySelection(); e.Handled = true; return;
                }
            }
            return;
        }
        if (key == Key.F5) { state.Refresh(); e.Handled = true; return; }
        if (inText || alt) return;

        switch (key)
        {
            case Key.P: state.FlagSelection(Flag.Pick); e.Handled = true; break;
            case Key.X: state.FlagSelection(Flag.Reject); e.Handled = true; break;
            case Key.U: state.FlagSelection(Flag.None); e.Handled = true; break;
            case Key.Space: Preview(); e.Handled = true; break;
            case Key.Delete: case Key.Back: state.DeleteSelection(); e.Handled = true; break;
            case Key.Escape: state.SelectNone(); e.Handled = true; break;
            case Key.Enter:
                if (state.SelectedClips.FirstOrDefault() is { } c) ShellActions.Open(c.Path);
                e.Handled = true; break;
            case Key.Left: case Key.Right:
                if (state.MoveSelection(key == Key.Right ? 1 : -1, shift) is { } target) BringIntoView(target);
                e.Handled = true; break;
        }
    }

    void BringIntoView(Clip clip)
    {
        Dispatcher.BeginInvoke(() =>
        {
            foreach (var fe in Descendants<Border>(Scroller))
                if (fe.Name == "Card" && fe.DataContext is ClipItem it && it.Clip == clip) { fe.BringIntoView(); break; }
        }, System.Windows.Threading.DispatcherPriority.Loaded);
    }

    static IEnumerable<T> Descendants<T>(DependencyObject root) where T : DependencyObject
    {
        int n = VisualTreeHelper.GetChildrenCount(root);
        for (int i = 0; i < n; i++)
        {
            var child = VisualTreeHelper.GetChild(root, i);
            if (child is T t) yield return t;
            foreach (var d in Descendants<T>(child)) yield return d;
        }
    }

    /// <summary>Spazio: anteprima delle clip/foto selezionate (come Quick Look sul Mac).</summary>
    void Preview()
    {
        var list = state.SelectedClips;
        if (list.Count == 0) { System.Media.SystemSounds.Beep.Play(); return; }
        var w = new PreviewWindow(list) { Owner = this };
        w.ShowDialog();
    }
}

public sealed class InverseVisibilityConverter : IValueConverter
{
    public object Convert(object value, Type t, object p, CultureInfo c) => value is true ? Visibility.Collapsed : Visibility.Visible;
    public object ConvertBack(object value, Type t, object p, CultureInfo c) => throw new NotSupportedException();
}

public sealed class NullToVisibilityConverter : IValueConverter
{
    public object Convert(object value, Type t, object p, CultureInfo c) =>
        value == null || (value is string s && s.Length == 0) ? Visibility.Collapsed : Visibility.Visible;
    public object ConvertBack(object value, Type t, object p, CultureInfo c) => throw new NotSupportedException();
}

/// <summary>Testi usati direttamente nello XAML.</summary>
public static class Strings
{
    public static string AlreadyImported => L("Already imported");
}
