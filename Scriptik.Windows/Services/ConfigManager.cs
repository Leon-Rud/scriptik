using System.ComponentModel;
using System.Globalization;
using System.IO;
using System.Runtime.CompilerServices;

namespace Scriptik.Windows.Services;

public class ConfigManager : INotifyPropertyChanged
{
    // MARK: - Config values with defaults

    private string _whisperModel = "medium";
    private double _pauseThreshold = 1.5;
    private string _initialPrompt = "";
    private bool _autoPaste = true;
    private bool _includeTimestamps;
    private string _language = "auto";
    private string _whisperVenv;
    private bool _showFloatingCircle = true;
    private bool _enableSoundFeedback = true;
    private double _circlePositionX = -1;
    private double _circlePositionY = -1;
    private bool _launchAtLogin;
    private int _hotkeyModifiers = 0x06; // MOD_CONTROL | MOD_SHIFT
    private int _hotkeyVirtualKey = 0x52; // R

    public string WhisperModel
    {
        get => _whisperModel;
        set => SetField(ref _whisperModel, value);
    }

    public double PauseThreshold
    {
        get => _pauseThreshold;
        set => SetField(ref _pauseThreshold, value);
    }

    public string InitialPrompt
    {
        get => _initialPrompt;
        set => SetField(ref _initialPrompt, value);
    }

    public bool AutoPaste
    {
        get => _autoPaste;
        set => SetField(ref _autoPaste, value);
    }

    public bool IncludeTimestamps
    {
        get => _includeTimestamps;
        set => SetField(ref _includeTimestamps, value);
    }

    public string Language
    {
        get => _language;
        set => SetField(ref _language, value);
    }

    public string WhisperVenv
    {
        get => _whisperVenv;
        set => SetField(ref _whisperVenv, value);
    }

    public bool ShowFloatingCircle
    {
        get => _showFloatingCircle;
        set => SetField(ref _showFloatingCircle, value);
    }

    public bool EnableSoundFeedback
    {
        get => _enableSoundFeedback;
        set => SetField(ref _enableSoundFeedback, value);
    }

    public double CirclePositionX
    {
        get => _circlePositionX;
        set => SetField(ref _circlePositionX, value);
    }

    public double CirclePositionY
    {
        get => _circlePositionY;
        set => SetField(ref _circlePositionY, value);
    }

    public bool LaunchAtLogin
    {
        get => _launchAtLogin;
        set
        {
            if (SetField(ref _launchAtLogin, value))
                LaunchAtLoginService.Set(value);
        }
    }

    public int HotkeyModifiers
    {
        get => _hotkeyModifiers;
        set => SetField(ref _hotkeyModifiers, value);
    }

    public int HotkeyVirtualKey
    {
        get => _hotkeyVirtualKey;
        set => SetField(ref _hotkeyVirtualKey, value);
    }

    // MARK: - Path constants

    public static string ConfigDir =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                     ".config", "scriptik");

    public static string ConfigFilePath => Path.Combine(ConfigDir, "config");
    public static string HistoryDir => Path.Combine(ConfigDir, "history");

    public static string DataDir => Path.Combine(Path.GetTempPath(), "scriptik");
    public static string PidFilePath => Path.Combine(DataDir, "recording.pid");
    public static string RecordingFilePath => Path.Combine(DataDir, "recording.wav");
    public static string TranscriptionFilePath => Path.Combine(DataDir, "transcription.txt");

    // MARK: - Available options

    public static readonly string[] AvailableModels = ["tiny", "base", "small", "medium", "large"];
    public static readonly string[] AvailableLanguages = ["auto", "en", "he"];

    // MARK: - Init

    public ConfigManager()
    {
        _whisperVenv = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "scriptik", "venv");
        Load();
        _launchAtLogin = LaunchAtLoginService.IsEnabled();
    }

    // MARK: - Whisper Python path

    public string WhisperPythonPath
    {
        get
        {
            var venvPython = Path.Combine(WhisperVenv, "Scripts", "python.exe");
            if (File.Exists(venvPython)) return venvPython;

            var fallback = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "scriptik", "venv", "Scripts", "python.exe");
            return fallback;
        }
    }

    // MARK: - Load

    public void Load()
    {
        if (!File.Exists(ConfigFilePath)) return;

        foreach (var line in File.ReadAllLines(ConfigFilePath))
        {
            var trimmed = line.Trim();
            if (string.IsNullOrEmpty(trimmed) || trimmed.StartsWith('#')) continue;

            var eqIndex = trimmed.IndexOf('=');
            if (eqIndex < 0) continue;

            var key = trimmed[..eqIndex].Trim();
            var value = trimmed[(eqIndex + 1)..].Trim();

            // Strip surrounding quotes
            if (value.Length >= 2 &&
                ((value.StartsWith('"') && value.EndsWith('"')) ||
                 (value.StartsWith('\'') && value.EndsWith('\''))))
            {
                value = value[1..^1];
            }

            switch (key)
            {
                case "WHISPER_MODEL": _whisperModel = value; break;
                case "PAUSE_THRESHOLD":
                    if (double.TryParse(value, NumberStyles.Any, CultureInfo.InvariantCulture, out var pt)) _pauseThreshold = pt;
                    break;
                case "INITIAL_PROMPT": _initialPrompt = value; break;
                case "AUTO_PASTE": _autoPaste = value.ToLower() != "false" && value != "0"; break;
                case "INCLUDE_TIMESTAMPS": _includeTimestamps = value.ToLower() != "false" && value != "0"; break;
                case "LANGUAGE": _language = value; break;
                case "WHISPER_VENV":
                    if (!string.IsNullOrEmpty(value)) _whisperVenv = value;
                    break;
                case "SHOW_FLOATING_CIRCLE": _showFloatingCircle = value.ToLower() != "false" && value != "0"; break;
                case "ENABLE_SOUND_FEEDBACK": _enableSoundFeedback = value.ToLower() != "false" && value != "0"; break;
                case "CIRCLE_POSITION_X":
                    if (double.TryParse(value, NumberStyles.Any, CultureInfo.InvariantCulture, out var cx)) _circlePositionX = cx;
                    break;
                case "CIRCLE_POSITION_Y":
                    if (double.TryParse(value, NumberStyles.Any, CultureInfo.InvariantCulture, out var cy)) _circlePositionY = cy;
                    break;
                case "HOTKEY_MODIFIERS":
                    if (int.TryParse(value, out var hm)) _hotkeyModifiers = hm;
                    break;
                case "HOTKEY_VKEY":
                    if (int.TryParse(value, out var hv)) _hotkeyVirtualKey = hv;
                    break;
            }
        }
    }

    // MARK: - Save

    public void Save()
    {
        Directory.CreateDirectory(ConfigDir);

        var lines = new List<string>
        {
            "# Scriptik configuration",
            "# This file is auto-generated. Manual edits are preserved.",
            "",
            $"WHISPER_MODEL=\"{WhisperModel}\"",
            $"PAUSE_THRESHOLD=\"{PauseThreshold.ToString(CultureInfo.InvariantCulture)}\"",
            $"INITIAL_PROMPT=\"{InitialPrompt}\"",
            $"AUTO_PASTE=\"{AutoPaste}\"",
            $"INCLUDE_TIMESTAMPS=\"{IncludeTimestamps}\"",
            $"LANGUAGE=\"{Language}\"",
            $"WHISPER_VENV=\"{WhisperVenv}\"",
            $"SHOW_FLOATING_CIRCLE=\"{ShowFloatingCircle}\"",
            $"ENABLE_SOUND_FEEDBACK=\"{EnableSoundFeedback}\"",
            $"CIRCLE_POSITION_X=\"{CirclePositionX.ToString(CultureInfo.InvariantCulture)}\"",
            $"CIRCLE_POSITION_Y=\"{CirclePositionY.ToString(CultureInfo.InvariantCulture)}\"",
            $"HOTKEY_MODIFIERS=\"{HotkeyModifiers}\"",
            $"HOTKEY_VKEY=\"{HotkeyVirtualKey}\"",
            ""
        };

        File.WriteAllText(ConfigFilePath, string.Join("\n", lines));
    }

    // MARK: - INotifyPropertyChanged

    public event PropertyChangedEventHandler? PropertyChanged;

    private bool SetField<T>(ref T field, T value, [CallerMemberName] string? propertyName = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value)) return false;
        field = value;
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
        return true;
    }
}
