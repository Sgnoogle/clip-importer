using System.Windows;
using System.Windows.Interop;
using WF = System.Windows.Forms;

namespace ClipImporter;

/// <summary>Finestre di dialogo native di Windows (TaskDialog).</summary>
public static class Dialogs
{
    static IntPtr Owner()
    {
        var w = Application.Current?.Windows.OfType<Window>().FirstOrDefault(x => x.IsActive)
                ?? Application.Current?.MainWindow;
        return w != null && w.IsVisible ? new WindowInteropHelper(w).Handle : IntPtr.Zero;
    }

    static WF.TaskDialogButton Show(WF.TaskDialogPage page)
    {
        page.Caption = "Clip Importer";
        page.AllowCancel = true;
        var owner = Owner();
        return owner != IntPtr.Zero ? WF.TaskDialog.ShowDialog(owner, page) : WF.TaskDialog.ShowDialog(page);
    }

    public static void Alert(string title, string message, bool warning = true)
    {
        Show(new WF.TaskDialogPage
        {
            Heading = title, Text = message,
            Icon = warning ? WF.TaskDialogIcon.Warning : WF.TaskDialogIcon.Information,
            Buttons = { WF.TaskDialogButton.OK },
        });
    }

    /// <summary>Conferma con un pulsante d'azione; facoltativamente con "Non chiedere più".</summary>
    public static (bool ok, bool dontAskAgain) Confirm(string title, string message, string action,
                                                       bool destructive = false, bool cancelIsDefault = false,
                                                       string? checkbox = null)
    {
        var actionButton = new WF.TaskDialogButton(action);
        var cancel = WF.TaskDialogButton.Cancel;
        var page = new WF.TaskDialogPage
        {
            Heading = title, Text = message,
            Icon = destructive ? WF.TaskDialogIcon.Warning : WF.TaskDialogIcon.Information,
            Buttons = { actionButton, cancel },
            DefaultButton = cancelIsDefault ? cancel : actionButton,
        };
        if (checkbox != null) page.Verification = new WF.TaskDialogVerificationCheckBox(checkbox);
        var result = Show(page);
        return (result == actionButton, page.Verification?.Checked ?? false);
    }

    /// <summary>Due scelte (es. "Continua a importare" / "Interrompi ed esci"); true = seconda.</summary>
    public static bool Choose(string title, string message, string first, string second)
    {
        var a = new WF.TaskDialogButton(first);
        var b = new WF.TaskDialogButton(second);
        var page = new WF.TaskDialogPage { Heading = title, Text = message, Icon = WF.TaskDialogIcon.Warning, Buttons = { a, b }, DefaultButton = a };
        return Show(page) == b;
    }
}
