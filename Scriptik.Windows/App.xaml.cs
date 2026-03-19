using System.Diagnostics;
using System.IO;
using System.Windows;
using Scriptik.Windows.Core;
using Scriptik.Windows.Services;
using Scriptik.Windows.UI.FloatingCircle;
using Scriptik.Windows.UI.TrayIcon;

namespace Scriptik.Windows;

public partial class App : Application
{
    private AppState? _appState;
    private TrayIconManager? _trayIconManager;
    private GlobalHotkeyService? _hotkeyService;
    private FloatingCircleWindow? _floatingCircle;

    // Hidden window for receiving WM_HOTKEY messages
    private Window? _messageWindow;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        _appState = new AppState();
        _trayIconManager = new TrayIconManager();
        _trayIconManager.Initialize(_appState);

        // Create a hidden window for global hotkey messages
        _messageWindow = new Window
        {
            Width = 0,
            Height = 0,
            WindowStyle = WindowStyle.None,
            ShowInTaskbar = false,
            ShowActivated = false,
        };
        _messageWindow.Show();
        _messageWindow.Hide();

        // Register global hotkey
        _hotkeyService = new GlobalHotkeyService();
        _hotkeyService.Initialize(_messageWindow);
        _hotkeyService.HotkeyPressed += (_, fgHwnd) =>
        {
            Dispatcher.InvokeAsync(() => _appState.Toggle(fgHwnd));
        };
        RegisterGlobalHotkey();

        // Show floating circle if enabled
        if (_appState.Config.ShowFloatingCircle)
            ShowFloatingCircle();

        // Watch for floating circle visibility changes
        _appState.Config.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName == nameof(ConfigManager.ShowFloatingCircle))
            {
                if (_appState.Config.ShowFloatingCircle)
                    ShowFloatingCircle();
                else
                    HideFloatingCircle();
            }
        };

        // Open settings on launch (unless --background flag)
        var isBackground = e.Args.Contains("--background");
        if (!isBackground)
        {
            Dispatcher.InvokeAsync(() =>
            {
                // Check if Python/Whisper is set up; prompt if not
                CheckPythonSetup();

                var settings = new UI.Settings.SettingsWindow(_appState);
                settings.Show();
            }, System.Windows.Threading.DispatcherPriority.Loaded);
        }
    }

    private void CheckPythonSetup()
    {
        if (_appState is null) return;

        var pythonPath = _appState.Config.WhisperPythonPath;
        if (File.Exists(pythonPath)) return;

        var setupScript = FindSetupScript();
        var message = "Python/Whisper environment not found. Transcription won't work until it's set up.\n\n";

        if (setupScript is not null)
        {
            message += "Would you like to run the setup now?\n\nThis will:\n" +
                       "  \u2022 Create a Python virtual environment\n" +
                       "  \u2022 Install OpenAI Whisper\n" +
                       "  \u2022 Install PyTorch (with CUDA if NVIDIA GPU detected)\n\n" +
                       "This may take a few minutes.";

            var result = MessageBox.Show(message, "Scriptik Setup",
                MessageBoxButton.YesNo, MessageBoxImage.Information);

            if (result == MessageBoxResult.Yes)
                RunSetupScript(setupScript);
        }
        else
        {
            message += "Run the setup script manually:\n" +
                       "  powershell -File Scriptik.Windows/Scripts/setup.ps1";

            MessageBox.Show(message, "Scriptik Setup",
                MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }

    private static string? FindSetupScript()
    {
        var baseDir = AppContext.BaseDirectory;

        // Check relative to executable
        var path1 = Path.Combine(baseDir, "Scripts", "setup.ps1");
        if (File.Exists(path1)) return path1;

        // Dev fallback
        var path2 = Path.Combine(baseDir, "..", "..", "..", "Scripts", "setup.ps1");
        if (File.Exists(path2)) return Path.GetFullPath(path2);

        return null;
    }

    private void RunSetupScript(string scriptPath)
    {
        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = "powershell.exe",
                Arguments = $"-ExecutionPolicy Bypass -File \"{scriptPath}\"",
                UseShellExecute = true, // Opens in a visible terminal window
            };
            var proc = Process.Start(psi);
            proc?.WaitForExit();

            if (proc?.ExitCode == 0)
            {
                MessageBox.Show("Setup complete! Restarting transcription server...",
                    "Scriptik Setup", MessageBoxButton.OK, MessageBoxImage.Information);

                // Restart the transcription server with the new Python
                _appState?.TranscriptionServer.Stop();
                _appState?.TranscriptionServer.Start(_appState.Config);
            }
            else
            {
                MessageBox.Show("Setup may have encountered errors. Check the terminal output.\n\n" +
                                "You can re-run manually:\n  powershell -File Scripts/setup.ps1",
                    "Scriptik Setup", MessageBoxButton.OK, MessageBoxImage.Warning);
            }
        }
        catch (Exception ex)
        {
            MessageBox.Show($"Failed to run setup: {ex.Message}",
                "Scriptik Setup", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _appState?.TranscriptionServer.Stop();
        _hotkeyService?.Dispose();
        _trayIconManager?.Dispose();
        _messageWindow?.Close();
        base.OnExit(e);
    }

    public void RegisterGlobalHotkey()
    {
        if (_hotkeyService is null || _appState is null) return;
        var config = _appState.Config;
        if (config.HotkeyVirtualKey != 0)
            _hotkeyService.Register(config.HotkeyModifiers, config.HotkeyVirtualKey);
    }

    public void UnregisterGlobalHotkey()
    {
        _hotkeyService?.Unregister();
    }

    private void ShowFloatingCircle()
    {
        if (_floatingCircle is not null) return;
        if (_appState is null) return;

        _floatingCircle = new FloatingCircleWindow(_appState);
        _floatingCircle.Show();
    }

    private void HideFloatingCircle()
    {
        _floatingCircle?.Close();
        _floatingCircle = null;
    }
}
