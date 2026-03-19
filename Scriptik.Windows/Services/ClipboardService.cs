using System.Windows;

namespace Scriptik.Windows.Services;

public static class ClipboardService
{
    public static void SetText(string text)
    {
        Application.Current.Dispatcher.Invoke(() =>
            Clipboard.SetText(text, TextDataFormat.UnicodeText));
    }

    public static string? GetText()
    {
        return Application.Current.Dispatcher.Invoke(() =>
            Clipboard.ContainsText() ? Clipboard.GetText() : null);
    }
}
