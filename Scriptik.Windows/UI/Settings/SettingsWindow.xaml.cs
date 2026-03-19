using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;
using NAudio.Wave;
using Scriptik.Windows.Core;
using Scriptik.Windows.Services;

namespace Scriptik.Windows.UI.Settings;

public partial class SettingsWindow : Window
{
    private readonly AppState _appState;
    private readonly ConfigManager _config;
    private DispatcherTimer? _statusTimer;
    private bool _isCapturingShortcut;

    public record ModelInfo(string Name, string Size, string Speed, string Accuracy, bool IsRecommended);

    private static readonly ModelInfo[] Models =
    [
        new("Tiny", "75 MB", "~1s", "Basic", false),
        new("Base", "140 MB", "~2s", "Good", false),
        new("Small", "500 MB", "~5s", "Great", false),
        new("Medium", "1.5 GB", "~15s", "Excellent", true),
        new("Large", "3 GB", "~30s", "Best", false),
    ];

    private static readonly Dictionary<string, string> LanguageLabels = new()
    {
        ["auto"] = "Auto-detect",
        ["en"] = "English",
        ["he"] = "Hebrew",
    };

    public SettingsWindow(AppState appState)
    {
        InitializeComponent();
        _appState = appState;
        _config = appState.Config;

        LoadSettings();
        StartStatusRefresh();
    }

    private void LoadSettings()
    {
        // General tab
        LaunchAtLoginCheck.IsChecked = _config.LaunchAtLogin;
        FloatingCircleCheck.IsChecked = _config.ShowFloatingCircle;
        AutoPasteCheck.IsChecked = _config.AutoPaste;
        TimestampsCheck.IsChecked = _config.IncludeTimestamps;
        SoundCheck.IsChecked = _config.EnableSoundFeedback;
        InitialPromptBox.Text = _config.InitialPrompt;
        PauseSlider.Value = _config.PauseThreshold;
        PauseLabel.Text = $"{_config.PauseThreshold:F1}s";

        // Language combo
        LanguageCombo.Items.Clear();
        foreach (var lang in ConfigManager.AvailableLanguages)
        {
            var label = LanguageLabels.GetValueOrDefault(lang, lang);
            LanguageCombo.Items.Add(new ComboBoxItem { Content = label, Tag = lang });
        }
        for (int i = 0; i < LanguageCombo.Items.Count; i++)
        {
            if (((ComboBoxItem)LanguageCombo.Items[i]).Tag?.ToString() == _config.Language)
            {
                LanguageCombo.SelectedIndex = i;
                break;
            }
        }

        // Model list
        ModelList.ItemsSource = Models;
        var selectedIdx = Array.FindIndex(Models, m => m.Name.ToLower() == _config.WhisperModel);
        if (selectedIdx >= 0) ModelList.SelectedIndex = selectedIdx;

        // Shortcut display
        UpdateShortcutDisplay();

        // Version
        var version = Assembly.GetExecutingAssembly().GetName().Version;
        VersionText.Text = $"v{version?.Major}.{version?.Minor}.{version?.Build}";

        // Wire up change handlers
        LaunchAtLoginCheck.Checked += (_, _) => _config.LaunchAtLogin = true;
        LaunchAtLoginCheck.Unchecked += (_, _) => _config.LaunchAtLogin = false;
        FloatingCircleCheck.Checked += (_, _) => _config.ShowFloatingCircle = true;
        FloatingCircleCheck.Unchecked += (_, _) => _config.ShowFloatingCircle = false;
        AutoPasteCheck.Checked += (_, _) => _config.AutoPaste = true;
        AutoPasteCheck.Unchecked += (_, _) => _config.AutoPaste = false;
        TimestampsCheck.Checked += (_, _) => _config.IncludeTimestamps = true;
        TimestampsCheck.Unchecked += (_, _) => _config.IncludeTimestamps = false;
        SoundCheck.Checked += (_, _) => _config.EnableSoundFeedback = true;
        SoundCheck.Unchecked += (_, _) => _config.EnableSoundFeedback = false;
        InitialPromptBox.TextChanged += (_, _) => _config.InitialPrompt = InitialPromptBox.Text;
        PauseSlider.ValueChanged += (_, _) =>
        {
            _config.PauseThreshold = PauseSlider.Value;
            PauseLabel.Text = $"{PauseSlider.Value:F1}s";
        };
        LanguageCombo.SelectionChanged += (_, _) =>
        {
            if (LanguageCombo.SelectedItem is ComboBoxItem item)
                _config.Language = item.Tag?.ToString() ?? "auto";
        };
    }

    private void ModelList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (ModelList.SelectedItem is ModelInfo model)
        {
            _config.WhisperModel = model.Name.ToLower();
            _config.Save();
            _appState.ModelDidChange();
        }
    }

    // MARK: - Shortcut recorder

    private void ShortcutBox_GotFocus(object sender, RoutedEventArgs e)
    {
        _isCapturingShortcut = true;
        ShortcutBox.Text = "Press shortcut\u2026";
    }

    private void ShortcutBox_LostFocus(object sender, RoutedEventArgs e)
    {
        _isCapturingShortcut = false;
        UpdateShortcutDisplay();
    }

    private void ShortcutBox_PreviewKeyDown(object sender, KeyEventArgs e)
    {
        if (!_isCapturingShortcut) return;
        e.Handled = true;

        // Escape cancels
        if (e.Key == Key.Escape)
        {
            _isCapturingShortcut = false;
            UpdateShortcutDisplay();
            Keyboard.ClearFocus();
            return;
        }

        // Gather modifiers
        int modifiers = 0;
        if (Keyboard.IsKeyDown(Key.LeftAlt) || Keyboard.IsKeyDown(Key.RightAlt)) modifiers |= 0x01;
        if (Keyboard.IsKeyDown(Key.LeftCtrl) || Keyboard.IsKeyDown(Key.RightCtrl)) modifiers |= 0x02;
        if (Keyboard.IsKeyDown(Key.LeftShift) || Keyboard.IsKeyDown(Key.RightShift)) modifiers |= 0x04;

        // Ignore modifier-only presses
        var key = e.Key == Key.System ? e.SystemKey : e.Key;
        if (key is Key.LeftCtrl or Key.RightCtrl or Key.LeftAlt or Key.RightAlt
            or Key.LeftShift or Key.RightShift or Key.LWin or Key.RWin)
            return;

        // Require at least one modifier (except F-keys)
        var isFKey = key >= Key.F1 && key <= Key.F24;
        if (modifiers == 0 && !isFKey) return;

        var vkey = KeyInterop.VirtualKeyFromKey(key);

        _config.HotkeyModifiers = modifiers;
        _config.HotkeyVirtualKey = vkey;
        _config.Save();

        // Re-register hotkey
        if (Application.Current is App app)
            app.RegisterGlobalHotkey();

        _isCapturingShortcut = false;
        UpdateShortcutDisplay();
        Keyboard.ClearFocus();
    }

    private void ClearShortcut_Click(object sender, RoutedEventArgs e)
    {
        _config.HotkeyModifiers = 0;
        _config.HotkeyVirtualKey = 0;
        _config.Save();

        if (Application.Current is App app)
            app.UnregisterGlobalHotkey();

        UpdateShortcutDisplay();
    }

    private void UpdateShortcutDisplay()
    {
        if (_config.HotkeyVirtualKey == 0)
        {
            ShortcutBox.Text = "Not set";
            return;
        }
        ShortcutBox.Text = GlobalHotkeyService.DescribeHotkey(
            _config.HotkeyModifiers, _config.HotkeyVirtualKey);
    }

    // MARK: - Status refresh

    private void StartStatusRefresh()
    {
        RefreshStatus();
        _statusTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(2) };
        _statusTimer.Tick += (_, _) => RefreshStatus();
        _statusTimer.Start();
    }

    private void RefreshStatus()
    {
        // Microphone
        var micAvailable = WaveInEvent.DeviceCount > 0;
        SetStatusRow(MicStatusBorder, MicStatusIcon, MicStatusText,
            micAvailable, micAvailable ? "Microphone detected" : "No microphone found");

        // Python
        var pythonExists = File.Exists(_config.WhisperPythonPath);
        SetStatusRow(PythonStatusBorder, PythonStatusIcon, PythonStatusText,
            pythonExists,
            pythonExists ? $"Found at {_config.WhisperPythonPath}" : "Not found \u2014 run setup.ps1");

        // Server
        var serverReady = _appState.TranscriptionServer.State == ServerState.Ready;
        var serverText = _appState.TranscriptionServer.State switch
        {
            ServerState.Ready => "Running",
            ServerState.Starting => "Starting\u2026",
            ServerState.Busy => "Busy (transcribing)",
            _ => "Not running"
        };
        SetStatusRow(ServerStatusBorder, ServerStatusIcon, ServerStatusText,
            serverReady || _appState.TranscriptionServer.State == ServerState.Busy, serverText);
    }

    private static void SetStatusRow(System.Windows.Controls.Border border, System.Windows.Controls.TextBlock icon,
        System.Windows.Controls.TextBlock text, bool ok, string message)
    {
        border.Background = new SolidColorBrush(ok
            ? Color.FromArgb(0x12, 0x22, 0xC5, 0x5E)   // subtle green tint
            : Color.FromArgb(0x12, 0xEF, 0x44, 0x44));  // subtle red tint
        border.BorderBrush = new SolidColorBrush(ok
            ? Color.FromArgb(0x28, 0x22, 0xC5, 0x5E)
            : Color.FromArgb(0x28, 0xEF, 0x44, 0x44));
        icon.Text = ok ? "\uE73E" : "\uE711";
        icon.Foreground = new SolidColorBrush(ok
            ? Color.FromRgb(0x16, 0xA3, 0x4A)   // #16A34A
            : Color.FromRgb(0xDC, 0x26, 0x26));  // #DC2626
        text.Text = message;
    }

    private void OpenSoundSettings_Click(object sender, RoutedEventArgs e)
    {
        try { Process.Start(new ProcessStartInfo("ms-settings:sound") { UseShellExecute = true }); }
        catch { }
    }

    private void GitHubLink_Click(object sender, RoutedEventArgs e)
    {
        try { Process.Start(new ProcessStartInfo("https://github.com/Leon-Rud/scriptik") { UseShellExecute = true }); }
        catch { }
    }

    protected override void OnClosing(System.ComponentModel.CancelEventArgs e)
    {
        _statusTimer?.Stop();
        _config.Save();
        base.OnClosing(e);
    }
}
