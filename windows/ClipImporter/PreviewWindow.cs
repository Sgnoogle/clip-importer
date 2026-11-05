using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;

namespace ClipImporter;

/// <summary>Anteprima a schermo intero-ish (Spazio): foto o video, frecce per scorrere, Esc/Spazio per chiudere.</summary>
public sealed class PreviewWindow : Window
{
    readonly List<Clip> clips;
    int index;
    readonly Grid host = new() { Background = Brushes.Black };
    readonly TextBlock caption = new() { Foreground = Brushes.White, Margin = new Thickness(14, 8, 14, 10), FontSize = 13 };
    MediaElement? player;

    public PreviewWindow(List<Clip> clips)
    {
        this.clips = clips;
        Title = "Clip Importer";
        Width = 1100; Height = 700;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        Background = Brushes.Black;
        var root = new DockPanel();
        var bar = new Border { Background = new SolidColorBrush(Color.FromRgb(0x1C, 0x1C, 0x1C)), Child = caption };
        DockPanel.SetDock(bar, Dock.Bottom);
        root.Children.Add(bar);
        root.Children.Add(host);
        Content = root;
        SourceInitialized += (_, _) => Dwm.ApplyDarkTitleBar(this, true);
        PreviewKeyDown += OnKey;
        Closed += (_, _) => StopPlayer();
        Show(0);
    }

    void StopPlayer()
    {
        if (player == null) return;
        try { player.Stop(); player.Close(); } catch { }
        player = null;
    }

    void Show(int i)
    {
        index = Math.Clamp(i, 0, clips.Count - 1);
        var clip = clips[index];
        StopPlayer();
        host.Children.Clear();
        if (clip.IsPhoto)
        {
            var src = CardScanner.IsRaw(clip.Path) ? null : Thumbnails.LoadFile(clip.Path, 2400);
            if (src == null) src = Thumbnails.LoadFile(clip.ThumbnailPath ?? clip.Path, 1600);
            host.Children.Add(new Image { Source = src, Stretch = Stretch.Uniform });
        }
        else
        {
            player = new MediaElement { Source = new Uri(clip.Path), LoadedBehavior = MediaState.Manual, UnloadedBehavior = MediaState.Close, Stretch = Stretch.Uniform };
            player.MediaEnded += (_, _) => { player.Position = TimeSpan.Zero; player.Play(); };
            host.Children.Add(player);
            player.Play();
        }
        var counter = clips.Count > 1 ? $"   {L("{0} of {1}", index + 1, clips.Count)}" : "";
        caption.Text = $"{clip.Name} · {Fmt.DateTimeShort(clip.Date)} · {Fmt.Bytes(clip.ImportSize)}{counter}";
        Title = clip.Name;
    }

    void OnKey(object sender, KeyEventArgs e)
    {
        switch (e.Key)
        {
            case Key.Escape: case Key.Space: Close(); e.Handled = true; break;
            case Key.Right: case Key.Down: Show(index + 1); e.Handled = true; break;
            case Key.Left: case Key.Up: Show(index - 1); e.Handled = true; break;
            case Key.Enter: ShellActions.Open(clips[index].Path); e.Handled = true; break;
        }
    }
}
