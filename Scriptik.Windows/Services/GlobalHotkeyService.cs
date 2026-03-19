using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;

namespace Scriptik.Windows.Services;

public class GlobalHotkeyService : IDisposable
{
    private const int WM_HOTKEY = 0x0312;
    private const int HOTKEY_ID = 9000;

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    private HwndSource? _source;
    private IntPtr _hwnd;
    private bool _registered;

    /// <summary>
    /// Fired when the global hotkey is pressed. The IntPtr is the HWND of the
    /// window that was in the foreground at the moment the hotkey was pressed.
    /// </summary>
    public event EventHandler<IntPtr>? HotkeyPressed;

    public void Initialize(Window window)
    {
        var helper = new WindowInteropHelper(window);
        helper.EnsureHandle();
        _hwnd = helper.Handle;
        _source = HwndSource.FromHwnd(_hwnd);
        _source?.AddHook(WndProc);
    }

    public void Register(int modifiers, int virtualKey)
    {
        Unregister();
        if (_hwnd == IntPtr.Zero) return;

        _registered = RegisterHotKey(_hwnd, HOTKEY_ID, (uint)modifiers, (uint)virtualKey);
    }

    public void Unregister()
    {
        if (_registered && _hwnd != IntPtr.Zero)
        {
            UnregisterHotKey(_hwnd, HOTKEY_ID);
            _registered = false;
        }
    }

    private IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == WM_HOTKEY && wParam.ToInt32() == HOTKEY_ID)
        {
            // Capture foreground window BEFORE raising the event
            var fgHwnd = GetForegroundWindow();
            handled = true;
            HotkeyPressed?.Invoke(this, fgHwnd);
        }
        return IntPtr.Zero;
    }

    public void Dispose()
    {
        Unregister();
        _source?.RemoveHook(WndProc);
        _source = null;
    }

    // Helper to describe a hotkey combo as a human-readable string
    public static string DescribeHotkey(int modifiers, int virtualKey)
    {
        var parts = new List<string>();
        if ((modifiers & 0x01) != 0) parts.Add("Alt");
        if ((modifiers & 0x02) != 0) parts.Add("Ctrl");
        if ((modifiers & 0x04) != 0) parts.Add("Shift");
        if ((modifiers & 0x08) != 0) parts.Add("Win");

        var keyName = ((System.Windows.Input.Key)System.Windows.Input.KeyInterop.KeyFromVirtualKey(virtualKey)).ToString();
        parts.Add(keyName);

        return string.Join("+", parts);
    }
}
