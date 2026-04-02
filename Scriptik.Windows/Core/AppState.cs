using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Windows.Input;
using System.Windows.Threading;
using Scriptik.Windows.Services;

namespace Scriptik.Windows.Core;

public enum TrayIconState { Idle, Recording, Transcribing }

public class AppState : INotifyPropertyChanged
{
    public ConfigManager Config { get; }
    public HistoryManager History { get; }
    public AudioRecorderService Recorder { get; }
    public TranscriberService Transcriber { get; }
    public TranscriptionServerService TranscriptionServer { get; }
    public SoundService Sound { get; }

    private string _statusText = "Ready";
    private bool _showCopiedFeedback;
    private double _transcriptionProgress;
    private double _transcriptionElapsed;
    private IntPtr _previousHwnd;

    private TimeSpan _lastRecordingDuration;
    private TimeSpan _estimatedTranscriptionDuration;
    private DateTime _transcriptionStartTime;
    private DispatcherTimer? _progressTimer;
    private CancellationTokenSource? _transcriptionCts;

    public string StatusText
    {
        get => _statusText;
        set => SetField(ref _statusText, value);
    }

    public bool ShowCopiedFeedback
    {
        get => _showCopiedFeedback;
        set => SetField(ref _showCopiedFeedback, value);
    }

    public double TranscriptionProgress
    {
        get => _transcriptionProgress;
        set => SetField(ref _transcriptionProgress, value);
    }

    public double TranscriptionElapsed
    {
        get => _transcriptionElapsed;
        set => SetField(ref _transcriptionElapsed, value);
    }

    public TrayIconState TrayIcon
    {
        get
        {
            if (Transcriber.IsTranscribing) return TrayIconState.Transcribing;
            if (Recorder.IsRecording) return TrayIconState.Recording;
            return TrayIconState.Idle;
        }
    }

    public bool HasLastResult => Transcriber.LastResult is not null;

    public string? DisplayResult
    {
        get
        {
            var result = Transcriber.LastResult;
            if (result is null) return null;
            return Config.IncludeTimestamps ? result : StripTimestamps(result);
        }
    }

    public double EstimatedTimeRemaining
    {
        get
        {
            if (_estimatedTranscriptionDuration.TotalSeconds <= 0) return 0;
            return Math.Max(0, _estimatedTranscriptionDuration.TotalSeconds - _transcriptionElapsed);
        }
    }

    // Commands for XAML binding
    public ICommand ToggleCommand { get; }
    public ICommand CancelCommand { get; }
    public ICommand CopyLastResultCommand { get; }
    public ICommand QuitCommand { get; }

    public AppState()
    {
        Config = new ConfigManager();
        History = new HistoryManager();
        Recorder = new AudioRecorderService();
        Transcriber = new TranscriberService();
        TranscriptionServer = new TranscriptionServerService();
        Sound = new SoundService(Config);

        ToggleCommand = new RelayCommand(_ => Toggle());
        CancelCommand = new RelayCommand(_ => CancelRecording());
        CopyLastResultCommand = new RelayCommand(_ => CopyLastResult(), _ => HasLastResult);
        QuitCommand = new RelayCommand(_ => System.Windows.Application.Current.Shutdown());

        // Propagate child property changes to update TrayIcon
        Recorder.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName == nameof(Recorder.IsRecording))
                OnPropertyChanged(nameof(TrayIcon));
        };
        Transcriber.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName == nameof(Transcriber.IsTranscribing))
            {
                OnPropertyChanged(nameof(TrayIcon));
                OnPropertyChanged(nameof(HasLastResult));
                OnPropertyChanged(nameof(DisplayResult));
            }
        };

        TranscriptionServer.Start(Config);
    }

    public void Toggle(IntPtr capturedForegroundHwnd = default)
    {
        if (Recorder.IsRecording)
            StopRecording();
        else if (!Transcriber.IsTranscribing)
            StartRecording(capturedForegroundHwnd);
    }

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    private void StartRecording(IntPtr capturedHwnd = default)
    {
        try
        {
            var fgHwnd = capturedHwnd != IntPtr.Zero
                ? capturedHwnd
                : AutoPasteService.GetCurrentForegroundWindow();

            // Don't store our own window as previous app
            if (fgHwnd != IntPtr.Zero)
            {
                GetWindowThreadProcessId(fgHwnd, out var fgPid);
                var myPid = (uint)Environment.ProcessId;
                if (fgPid != myPid)
                    _previousHwnd = fgHwnd;
            }

            Sound.Play(SoundEvent.Begin);
            Recorder.StartRecording();
            StatusText = "Recording...";
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Scriptik: startRecording error: {ex}");
            StatusText = $"Mic error: {ex.Message}";
        }
    }

    private void StopRecording()
    {
        Sound.Play(SoundEvent.End);

        _lastRecordingDuration = Recorder.ElapsedTime;
        var recordingPath = Recorder.StopRecording();

        if (recordingPath is null)
        {
            StatusText = "Too short";
            return;
        }

        StatusText = "Transcribing...";
        StartProgressTimer();

        _transcriptionCts?.Cancel();
        _transcriptionCts?.Dispose();
        _transcriptionCts = new CancellationTokenSource();
        _ = RunTranscriptionAsync(_transcriptionCts.Token);
    }

    private async Task RunTranscriptionAsync(CancellationToken ct)
    {
        try
        {
            var result = await Transcriber.TranscribeAsync(Config, TranscriptionServer, ct);
            ct.ThrowIfCancellationRequested();
            StopProgressTimer();

            var clipboardText = Config.IncludeTimestamps ? result : StripTimestamps(result);
            ClipboardService.SetText(clipboardText);

            if (Config.AutoPaste)
            {
                await Task.Delay(300, ct);
                await PasteIntoPreviousAppAsync();
            }

            History.Save(result);
            History.Refresh();

            if (!StatusText.Contains("auto-paste"))
                StatusText = "Done \u2014 copied to clipboard";

            TriggerCopiedFeedback();
            OnPropertyChanged(nameof(HasLastResult));
            OnPropertyChanged(nameof(DisplayResult));

            var currentStatus = StatusText;
            await Task.Delay(3000, ct);
            if (StatusText == currentStatus)
                StatusText = "Ready";
        }
        catch (OperationCanceledException)
        {
            StopProgressTimer();
            Debug.WriteLine("Scriptik: transcription cancelled");
        }
        catch (Exception ex)
        {
            StopProgressTimer();
            Debug.WriteLine($"Scriptik: transcription error: {ex}");
            StatusText = $"Error: {ex.Message}";
        }
    }

    public void CancelTranscription()
    {
        _transcriptionCts?.Cancel();
        _transcriptionCts?.Dispose();
        _transcriptionCts = null;
    }

    public void ModelDidChange()
    {
        _ = TranscriptionServer.ReloadModelAsync(Config.WhisperModel);
    }

    public void CancelRecording()
    {
        if (!Recorder.IsRecording) return;
        Sound.Play(SoundEvent.Cancel);
        Recorder.StopRecording();

        try { System.IO.File.Delete(ConfigManager.RecordingFilePath); } catch { }

        StatusText = "Cancelled";
        _ = ResetStatusAfterDelay("Cancelled", 2000);
    }

    public void CopyLastResult()
    {
        var result = Transcriber.LastResult;
        if (result is null) return;

        var text = Config.IncludeTimestamps ? result : StripTimestamps(result);
        ClipboardService.SetText(text);
        StatusText = "Copied";
        TriggerCopiedFeedback();
    }

    // MARK: - Progress Estimation

    private void StartProgressTimer()
    {
        _estimatedTranscriptionDuration = TranscriberService.EstimatedDuration(
            _lastRecordingDuration, Config.WhisperModel);
        _transcriptionStartTime = DateTime.Now;
        TranscriptionProgress = 0;
        TranscriptionElapsed = 0;

        _progressTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(100) };
        _progressTimer.Tick += (_, _) => UpdateProgress();
        _progressTimer.Start();
    }

    private void UpdateProgress()
    {
        var elapsed = (DateTime.Now - _transcriptionStartTime).TotalSeconds;
        TranscriptionElapsed = elapsed;

        var ratio = elapsed / _estimatedTranscriptionDuration.TotalSeconds;
        TranscriptionProgress = 1.0 - Math.Exp(-2.5 * ratio);
    }

    private void StopProgressTimer()
    {
        _progressTimer?.Stop();
        _progressTimer = null;
        TranscriptionProgress = 0;
        TranscriptionElapsed = 0;
        _estimatedTranscriptionDuration = TimeSpan.Zero;
    }

    // MARK: - Auto-Paste

    private async Task PasteIntoPreviousAppAsync()
    {
        if (_previousHwnd == IntPtr.Zero)
        {
            Debug.WriteLine("Scriptik: auto-paste skipped — no previous window");
            return;
        }

        try
        {
            await AutoPasteService.PasteAsync(_previousHwnd);
            Debug.WriteLine("Scriptik: Ctrl+V posted");
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Scriptik: auto-paste failed: {ex.Message}");
            StatusText = "Copied \u2014 auto-paste failed";
        }
    }

    // MARK: - Helpers

    private void TriggerCopiedFeedback()
    {
        ShowCopiedFeedback = true;
        _ = Task.Run(async () =>
        {
            await Task.Delay(1500);
            System.Windows.Application.Current?.Dispatcher.InvokeAsync(() =>
                ShowCopiedFeedback = false);
        });
    }

    private async Task ResetStatusAfterDelay(string expected, int delayMs)
    {
        await Task.Delay(delayMs);
        if (StatusText == expected)
            StatusText = "Ready";
    }

    public static string StripTimestamps(string text)
    {
        var lines = text.Split('\n');
        var result = new List<string>();

        foreach (var line in lines)
        {
            var trimmed = line.Trim();
            if (string.IsNullOrEmpty(trimmed)) continue;
            if (trimmed.Contains("[pause")) continue;

            var closingIdx = trimmed.IndexOf("] ", StringComparison.Ordinal);
            if (closingIdx >= 0)
            {
                var afterBracket = trimmed[(closingIdx + 2)..].Trim();
                if (!string.IsNullOrEmpty(afterBracket))
                    result.Add(afterBracket);
            }
            else
            {
                result.Add(trimmed);
            }
        }

        return string.Join(" ", result);
    }

    // MARK: - INotifyPropertyChanged

    public event PropertyChangedEventHandler? PropertyChanged;

    private bool SetField<T>(ref T field, T value, [CallerMemberName] string? name = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value)) return false;
        field = value;
        OnPropertyChanged(name);
        return true;
    }

    private void OnPropertyChanged([CallerMemberName] string? name = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}

// Simple ICommand implementation
public class RelayCommand : ICommand
{
    private readonly Action<object?> _execute;
    private readonly Predicate<object?>? _canExecute;

    public RelayCommand(Action<object?> execute, Predicate<object?>? canExecute = null)
    {
        _execute = execute;
        _canExecute = canExecute;
    }

    public bool CanExecute(object? parameter) => _canExecute?.Invoke(parameter) ?? true;
    public void Execute(object? parameter) => _execute(parameter);
    public event EventHandler? CanExecuteChanged
    {
        add => CommandManager.RequerySuggested += value;
        remove => CommandManager.RequerySuggested -= value;
    }
}
