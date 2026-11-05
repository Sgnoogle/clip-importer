using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows.Media;

namespace ClipImporter;

public abstract class Observable : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;
    protected void Raise([CallerMemberName] string? name = null) => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
    protected void RaiseAll() => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(string.Empty));
    protected bool Set<T>(ref T field, T value, [CallerMemberName] string? name = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value)) return false;
        field = value;
        Raise(name);
        return true;
    }
}

/// <summary>Una miniatura nella griglia.</summary>
public sealed class ClipItem : Observable
{
    public ClipItem(Clip clip) { Clip = clip; }

    public Clip Clip { get; private set; }
    public string Name => Clip.Name;
    public bool IsPhoto => Clip.IsPhoto;
    public string? TechLabel => Clip.TechLabel;
    public string TimeSize => $"{Fmt.Time(Clip.Date)} · {Fmt.Bytes(Clip.ImportSize)}";
    public string Tooltip => Fmt.DateTimeShort(Clip.Date);

    /// <summary>Aggiorna i dati dopo una nuova lettura della scheda, tenendo la miniatura già caricata.</summary>
    public void Update(Clip clip) { Clip = clip; RaiseAll(); }

    bool selected;
    public bool IsSelected { get => selected; set { if (Set(ref selected, value)) { Raise(nameof(Dim)); Raise(nameof(ShowSelectCircle)); } } }

    bool imported;
    public bool IsImported { get => imported; set { if (Set(ref imported, value)) Raise(nameof(Dim)); } }

    Flag flag;
    public Flag Flag
    {
        get => flag;
        set
        {
            if (!Set(ref flag, value)) return;
            Raise(nameof(IsPicked)); Raise(nameof(IsRejected)); Raise(nameof(HasFlag)); Raise(nameof(Dim));
            Raise(nameof(DisplayImage)); Raise(nameof(RibbonTooltip));
        }
    }
    public bool IsPicked => flag == Flag.Pick;
    public bool IsRejected => flag == Flag.Reject;
    public bool HasFlag => flag != Flag.None;

    /// <summary>Scartate e già importate si sbiadiscono (il segnalibro no).</summary>
    public double Dim => flag == Flag.Reject ? (selected ? 0.6 : 0.4) : (imported && !selected ? 0.55 : 1.0);

    public bool ShowSelectCircle => selected;

    ImageSource? thumbnail, gray;
    bool thumbLoaded, thumbFailed;
    public ImageSource? DisplayImage => flag == Flag.Reject ? (gray ??= Thumbnails.Gray(thumbnail)) ?? thumbnail : thumbnail;
    public bool ThumbFailed => thumbFailed;
    public bool ThumbLoading => !thumbLoaded;
    public bool IsPortrait => thumbnail is { } t && IsPhoto && t.Height > t.Width;
    /// <summary>Le foto verticali si vedono intere, senza tagliare teste e piedi.</summary>
    public System.Windows.Media.Stretch ImageStretch => IsPortrait ? System.Windows.Media.Stretch.Uniform : System.Windows.Media.Stretch.UniformToFill;

    double? loadedDuration;
    public string? Badge => Clip.IsPhoto ? Clip.Badge : (Clip.Duration ?? loadedDuration) is double d ? Fmt.Duration(d) : null;

    public string RibbonTooltip => flag switch
    {
        Flag.Pick => L("Picked: only picks get imported · click to remove · Alt+click to reject"),
        Flag.Reject => L("Rejected: won't be imported · click to remove"),
        _ => L("Click: pick (P) · Alt+click: reject (X) · right-click: more options"),
    };

    public async void EnsureThumbnail()
    {
        if (thumbLoaded || loading) return;
        loading = true;
        var r = await Thumbnails.LoadAsync(Clip);
        thumbnail = r.Image; gray = null;
        thumbFailed = r.Image == null;
        if (Clip.Duration == null) loadedDuration = r.Duration;
        thumbLoaded = true;
        Raise(nameof(DisplayImage)); Raise(nameof(ThumbFailed)); Raise(nameof(ThumbLoading));
        Raise(nameof(IsPortrait)); Raise(nameof(ImageStretch)); Raise(nameof(Badge));
    }
    bool loading;
}

/// <summary>Un gruppo di miniature (un giorno di ripresa, oppure tutte insieme).</summary>
public sealed class DaySection : Observable
{
    public DaySection(DateTime? day, List<ClipItem> items) { Day = day; Items = items; }
    public DateTime? Day { get; }
    public List<ClipItem> Items { get; }
    public bool HasHeader => Day != null;
    public string Title => Day is DateTime d ? Fmt.Day(d) : "";
    public string Count => Fmt.Items(Items.Select(i => i.Clip));
    bool allSelected;
    public bool AllSelected { get => allSelected; set { if (Set(ref allSelected, value)) Raise(nameof(SelectDayLabel)); } }
    public string SelectDayLabel => allSelected ? L("Deselect day") : L("Select day");
}
