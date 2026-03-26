using System.Runtime.InteropServices;
using System.Windows;

namespace Scriptik.Windows.Services;

public static class ClipboardService
{
    public static void SetText(string text)
    {
        Application.Current.Dispatcher.Invoke(() =>
        {
            for (int i = 0; i < 3; i++)
            {
                try
                {
                    Clipboard.SetText(text, TextDataFormat.UnicodeText);
                    return;
                }
                catch (COMException)
                {
                    Thread.Sleep(50);
                }
            }
        });
    }

    public static string? GetText()
    {
        return Application.Current.Dispatcher.Invoke(() =>
        {
            for (int i = 0; i < 3; i++)
            {
                try
                {
                    return Clipboard.ContainsText() ? Clipboard.GetText() : null;
                }
                catch (COMException)
                {
                    Thread.Sleep(50);
                }
            }
            return null;
        });
    }
}
