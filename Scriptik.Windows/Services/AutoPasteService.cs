using System.Runtime.InteropServices;

namespace Scriptik.Windows.Services;

public static class AutoPasteService
{
    // Virtual key codes
    private const ushort VK_CONTROL = 0xA2; // Left Ctrl
    private const ushort VK_V = 0x56;

    // SendInput flags
    private const uint KEYEVENTF_KEYUP = 0x0002;
    private const uint INPUT_KEYBOARD = 1;

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    [DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern bool IsWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    public static async Task PasteAsync(IntPtr targetHwnd)
    {
        if (targetHwnd == IntPtr.Zero || !IsWindow(targetHwnd))
            return;

        // Verify clipboard has content
        if (string.IsNullOrEmpty(ClipboardService.GetText()))
            return;

        // Activate target window
        SetForegroundWindow(targetHwnd);

        // Wait for activation
        await Task.Delay(150);

        // Send Ctrl+V
        var inputs = new INPUT[]
        {
            CreateKeyInput(VK_CONTROL, keyUp: false),
            CreateKeyInput(VK_V, keyUp: false),
            CreateKeyInput(VK_V, keyUp: true),
            CreateKeyInput(VK_CONTROL, keyUp: true),
        };

        SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<INPUT>());
    }

    public static IntPtr GetCurrentForegroundWindow() => GetForegroundWindow();

    private static INPUT CreateKeyInput(ushort vk, bool keyUp)
    {
        return new INPUT
        {
            type = INPUT_KEYBOARD,
            union = new INPUT_UNION
            {
                ki = new KEYBDINPUT
                {
                    wVk = vk,
                    wScan = 0,
                    dwFlags = keyUp ? KEYEVENTF_KEYUP : 0,
                    time = 0,
                    dwExtraInfo = IntPtr.Zero,
                }
            }
        };
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct INPUT
    {
        public uint type;
        public INPUT_UNION union;
    }

    [StructLayout(LayoutKind.Explicit)]
    private struct INPUT_UNION
    {
        [FieldOffset(0)] public KEYBDINPUT ki;
        [FieldOffset(0)] public MOUSEINPUT mi; // Ensures union is sized to the largest member
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KEYBDINPUT
    {
        public ushort wVk;
        public ushort wScan;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MOUSEINPUT
    {
        public int dx;
        public int dy;
        public uint mouseData;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }
}
