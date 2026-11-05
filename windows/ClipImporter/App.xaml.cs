using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;
using Microsoft.Win32;
using WF = System.Windows.Forms;

namespace ClipImporter;

public static class Program
{
    [STAThread]
    public static int Main(string[] args)
    {
        // Modalità di prova per GitHub Actions: nessuna finestra
        int st = Array.IndexOf(args, "--selftest");
        if (st >= 0) return SelfTest.Run(st + 1 < args.Length ? args[st + 1] : System.IO.Path.GetTempPath());

        // Una sola istanza: la seconda chiede alla prima di mostrare la finestra ed esce
        using var mutex = new Mutex(true, @"Local\ClipImporter.SingleInstance", out bool first);
        using var showEvent = new EventWaitHandle(false, EventResetMode.AutoReset, @"Local\ClipImporter.Show");
        if (!first) { showEvent.Set(); return 0; }

        var app = new App { Background = args.Contains("--background") };
        app.InitializeComponent();
        var listener = new Thread(() =>
        {
            while (true)
            {
                showEvent.WaitOne();
                app.Dispatcher.BeginInvoke(() => app.ShowMainWindow());
            }
        }) { IsBackground = true };
        listener.Start();
        return app.Run();
    }
}

public partial class App : Application
{
    public bool Background { get; init; }
    MainWindow? window;
    WF.NotifyIcon? tray;
    readonly HashSet<string> knownDrives = new(StringComparer.OrdinalIgnoreCase);
    AppState state = null!;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        Theme.Apply(this);
        SystemEvents.UserPreferenceChanged += (_, _) => Dispatcher.BeginInvoke(() => Theme.Apply(this));

        state = AppState.Shared;
        state.ConfigureLoginItemOnFirstRun();
        state.WantsWindow = ShowMainWindow;
        BuildTray();

        // Schede già inserite all'avvio, poi controllo periodico (inserimento/rimozione)
        foreach (var root in CandidateDrives())
        {
            knownDrives.Add(root);
            state.VolumeMounted(root, showWindow: true);
        }
        state.RestoreLastFolder();
        var timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1.5) };
        timer.Tick += (_, _) => PollDrives();
        timer.Start();

        if (!Background) ShowMainWindow();
    }

    static IEnumerable<string> CandidateDrives()
    {
        var system = System.IO.Path.GetPathRoot(Environment.GetFolderPath(Environment.SpecialFolder.Windows)) ?? "C:\\";
        foreach (var d in DriveInfo.GetDrives())
        {
            bool ok;
            try { ok = d.IsReady && (d.DriveType == DriveType.Removable || d.DriveType == DriveType.Fixed); } catch { ok = false; }
            if (ok && !d.Name.Equals(system, StringComparison.OrdinalIgnoreCase)) yield return d.Name;
        }
    }

    void PollDrives()
    {
        var now = new HashSet<string>(CandidateDrives(), StringComparer.OrdinalIgnoreCase);
        foreach (var added in now.Except(knownDrives).ToList()) { knownDrives.Add(added); state.VolumeMounted(added, showWindow: true); }
        foreach (var removed in knownDrives.Except(now).ToList()) { knownDrives.Remove(removed); state.VolumeUnmounted(removed); }
    }

    public void ShowMainWindow()
    {
        if (window == null)
        {
            window = new MainWindow();
            MainWindow = window;
            window.Closing += (_, e) =>
            {
                if (quitting) return;
                // Chiudendo la finestra l'app resta nell'area di notifica
                e.Cancel = true;
                window.Hide();
                if (!state.RawSettings.TrayHintShown && tray != null)
                {
                    state.RawSettings.TrayHintShown = true;
                    state.RawSettings.Save();
                    tray.ShowBalloonTip(5000, "Clip Importer", L("Clip Importer keeps running in the notification area and opens by itself when you insert a card."), WF.ToolTipIcon.Info);
                }
            };
        }
        if (!window.IsVisible) window.Show();
        if (window.WindowState == WindowState.Minimized) window.WindowState = WindowState.Normal;
        window.Activate();
        window.Topmost = true; window.Topmost = false;   // porta davanti anche se un'altra app ha il focus
        window.Focus();
    }

    bool quitting;
    public void Quit()
    {
        if (!state.ConfirmQuit()) return;
        quitting = true;
        if (tray != null) { tray.Visible = false; tray.Dispose(); }
        window?.Close();
        Shutdown();
    }

    // MARK: Icona nell'area di notifica (come l'icona nella barra dei menu del Mac)

    void BuildTray()
    {
        System.Drawing.Icon icon;
        try
        {
            using var s = typeof(App).Assembly.GetManifestResourceStream("AppIcon.ico")!;
            icon = new System.Drawing.Icon(s, WF.SystemInformation.SmallIconSize);
        }
        catch { icon = System.Drawing.SystemIcons.Application; }
        tray = new WF.NotifyIcon { Icon = icon, Text = "Clip Importer", Visible = true, ContextMenuStrip = new WF.ContextMenuStrip() };
        tray.ContextMenuStrip.Opening += (_, _) => RebuildTrayMenu(tray.ContextMenuStrip);
        tray.MouseClick += (_, e) => { if (e.Button == WF.MouseButtons.Left) ShowMainWindow(); };
    }

    void RebuildTrayMenu(WF.ContextMenuStrip menu)
    {
        menu.Items.Clear();
        WF.ToolStripMenuItem Add(string title, Action action)
        {
            var item = new WF.ToolStripMenuItem(title);
            item.Click += (_, _) => Dispatcher.BeginInvoke(action);
            menu.Items.Add(item);
            return item;
        }
        var open = Add(L("Open Clip Importer"), ShowMainWindow);
        open.Font = new System.Drawing.Font(open.Font, System.Drawing.FontStyle.Bold);
        if (state.Progress is { } p) menu.Items.Add(new WF.ToolStripMenuItem(L("Importing: {0}%", (int)(p.Fraction * 100))) { Enabled = false });
        menu.Items.Add(new WF.ToolStripSeparator());

        var cards = state.Sources.Where(x => x.IsVolume).ToList();
        if (cards.Count == 0) menu.Items.Add(new WF.ToolStripMenuItem(L("No card inserted")) { Enabled = false });
        foreach (var src in cards.Concat(state.Sources.Where(x => !x.IsVolume)))
        {
            var s = src;
            var item = Add(L("Show items on “{0}”", s.Name), () => { if (state.Progress == null) state.Open(s); ShowMainWindow(); });
            item.Checked = state.Current == s;
            item.ToolTipText = s.Path;
        }
        Add(state.Sources.Any(x => !x.IsVolume) ? L("Browse another folder…") : L("Browse a folder…"), () => { ShowMainWindow(); state.ChooseSourceFolder(); });
        menu.Items.Add(new WF.ToolStripSeparator());
        Add(L("Open when a card is inserted"), () => state.AutoOpen = !state.AutoOpen).Checked = state.AutoOpen;
        Add(L("Start at login"), () => state.LaunchAtLogin = !state.LaunchAtLogin).Checked = state.LaunchAtLogin;
        menu.Items.Add(new WF.ToolStripSeparator());
        Add(L("Quit Clip Importer"), Quit);
    }
}

/// <summary>Colori chiaro/scuro (segue il tema di Windows) e colore d'accento di sistema.</summary>
public static class Theme
{
    public static bool IsDark
    {
        get
        {
            try
            {
                using var k = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
                return k?.GetValue("AppsUseLightTheme") is int v && v == 0;
            }
            catch { return false; }
        }
    }

    static Color Accent
    {
        get
        {
            try
            {
                using var k = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\DWM");
                if (k?.GetValue("AccentColor") is int abgr)
                    return Color.FromRgb((byte)(abgr & 0xFF), (byte)((abgr >> 8) & 0xFF), (byte)((abgr >> 16) & 0xFF));
            }
            catch { }
            return Color.FromRgb(0x00, 0x67, 0xC0);
        }
    }

    static SolidColorBrush B(Color c) { var b = new SolidColorBrush(c); b.Freeze(); return b; }
    static SolidColorBrush B(byte a, byte r, byte g, byte bl) => B(Color.FromArgb(a, r, g, bl));

    public static void Apply(Application app)
    {
        bool dark = IsDark;
        var accent = Accent;
        // Testo leggibile sull'accento
        double lum = (0.299 * accent.R + 0.587 * accent.G + 0.114 * accent.B) / 255;
        var r = app.Resources;
        r["AccentBrush"] = B(accent);
        r["AccentTextBrush"] = B(lum > 0.6 ? Colors.Black : Colors.White);
        r["AccentSoftBrush"] = B(Color.FromArgb(dark ? (byte)70 : (byte)45, accent.R, accent.G, accent.B));
        r["WindowBrush"] = dark ? B(255, 0x20, 0x20, 0x20) : B(255, 0xF3, 0xF3, 0xF3);
        r["BarBrush"] = dark ? B(255, 0x2B, 0x2B, 0x2B) : B(255, 0xFB, 0xFB, 0xFB);
        r["HeaderBrush"] = dark ? B(235, 0x2B, 0x2B, 0x2B) : B(235, 0xFB, 0xFB, 0xFB);
        r["TextBrush"] = dark ? B(255, 0xFF, 0xFF, 0xFF) : B(255, 0x1A, 0x1A, 0x1A);
        r["TextSecondaryBrush"] = dark ? B(200, 0xFF, 0xFF, 0xFF) : B(160, 0, 0, 0);
        r["TextTertiaryBrush"] = dark ? B(130, 0xFF, 0xFF, 0xFF) : B(110, 0, 0, 0);
        r["ControlBrush"] = dark ? B(255, 0x37, 0x37, 0x37) : B(255, 0xFF, 0xFF, 0xFF);
        r["ControlHoverBrush"] = dark ? B(255, 0x42, 0x42, 0x42) : B(255, 0xF0, 0xF0, 0xF0);
        r["ControlBorderBrush"] = dark ? B(40, 0xFF, 0xFF, 0xFF) : B(30, 0, 0, 0);
        r["DividerBrush"] = dark ? B(30, 0xFF, 0xFF, 0xFF) : B(22, 0, 0, 0);
        r["SegmentBackBrush"] = dark ? B(255, 0x1C, 0x1C, 0x1C) : B(255, 0xE6, 0xE6, 0xE6);
        r["SegmentOnBrush"] = dark ? B(255, 0x45, 0x45, 0x45) : B(255, 0xFF, 0xFF, 0xFF);
        r["CardHoverBrush"] = dark ? B(18, 0xFF, 0xFF, 0xFF) : B(12, 0, 0, 0);
        r["PickBrush"] = B(Color.FromRgb(0x33, 0xB3, 0x54));
        r["RejectBrush"] = B(Color.FromRgb(0xE6, 0x38, 0x36));
        foreach (Window w in app.Windows) Dwm.ApplyDarkTitleBar(w, dark);
    }
}

static class Dwm
{
    [DllImport("dwmapi.dll")]
    static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);

    public static void ApplyDarkTitleBar(Window w, bool dark)
    {
        try
        {
            var hwnd = new WindowInteropHelper(w).Handle;
            if (hwnd == IntPtr.Zero) return;
            int v = dark ? 1 : 0;
            DwmSetWindowAttribute(hwnd, 20, ref v, sizeof(int));   // DWMWA_USE_IMMERSIVE_DARK_MODE
            int corner = 2;
            DwmSetWindowAttribute(hwnd, 33, ref corner, sizeof(int)); // angoli arrotondati (Windows 11)
        }
        catch { }
    }
}
