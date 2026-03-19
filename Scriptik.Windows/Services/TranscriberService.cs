using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Runtime.CompilerServices;
using System.Text;

namespace Scriptik.Windows.Services;

public class TranscriberService : INotifyPropertyChanged
{
    private bool _isTranscribing;
    private string? _lastResult;

    public bool IsTranscribing
    {
        get => _isTranscribing;
        private set => SetField(ref _isTranscribing, value);
    }

    public string? LastResult
    {
        get => _lastResult;
        private set => SetField(ref _lastResult, value);
    }

    // Speed factors: estimated transcription time as fraction of recording duration
    private static readonly Dictionary<string, double> SpeedFactors = new()
    {
        ["tiny"] = 0.15,
        ["base"] = 0.25,
        ["small"] = 0.5,
        ["medium"] = 0.8,
        ["large"] = 1.5,
    };

    public static TimeSpan EstimatedDuration(TimeSpan recordingDuration, string model)
    {
        var factor = SpeedFactors.GetValueOrDefault(model, 0.8);
        var seconds = Math.Max(2.0, recordingDuration.TotalSeconds * factor);
        return TimeSpan.FromSeconds(seconds);
    }

    public async Task<string> TranscribeAsync(
        ConfigManager config,
        TranscriptionServerService? server = null,
        CancellationToken ct = default)
    {
        IsTranscribing = true;

        try
        {
            var result = await RunTranscriptionAsync(config, server, ct);
            LastResult = result;
            return result;
        }
        finally
        {
            IsTranscribing = false;
        }
    }

    private async Task<string> RunTranscriptionAsync(
        ConfigManager config,
        TranscriptionServerService? server,
        CancellationToken ct)
    {
        // Try the persistent server first
        if (server is not null &&
            (server.State == ServerState.Ready || server.State == ServerState.Starting))
        {
            try
            {
                var recordingPath = ConfigManager.RecordingFilePath;
                var transcriptionPath = ConfigManager.TranscriptionFilePath;

                try { File.Delete(transcriptionPath); } catch { }

                return await server.TranscribeAsync(
                    recordingPath, transcriptionPath,
                    config.PauseThreshold, config.WhisperModel,
                    config.InitialPrompt, config.Language, ct);
            }
            catch (OperationCanceledException)
            {
                throw; // Don't fall back to one-shot on cancellation
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"Scriptik: server transcription failed, falling back to one-shot: {ex.Message}");
            }
        }

        // One-shot fallback
        return await RunOneShotAsync(config, ct);
    }

    private async Task<string> RunOneShotAsync(ConfigManager config, CancellationToken ct)
    {
        var scriptPath = FindScript()
            ?? throw new FileNotFoundException("Could not find transcribe.py script.");

        var pythonPath = config.WhisperPythonPath;
        if (!File.Exists(pythonPath))
            throw new FileNotFoundException("Whisper Python environment not found. Please run setup.ps1.");

        var recordingPath = ConfigManager.RecordingFilePath;
        var transcriptionPath = ConfigManager.TranscriptionFilePath;

        try { File.Delete(transcriptionPath); } catch { }

        var psi = new ProcessStartInfo
        {
            FileName = pythonPath,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8,
        };
        psi.ArgumentList.Add(scriptPath);
        psi.ArgumentList.Add(recordingPath);
        psi.ArgumentList.Add(transcriptionPath);
        psi.ArgumentList.Add(config.PauseThreshold.ToString());
        psi.ArgumentList.Add(config.WhisperModel);
        psi.ArgumentList.Add(config.InitialPrompt);
        psi.ArgumentList.Add(config.Language);

        psi.Environment["PYTHONUNBUFFERED"] = "1";
        psi.Environment["PYTHONIOENCODING"] = "utf-8";
        psi.Environment["PYTHONUTF8"] = "1";

        using var process = new Process { StartInfo = psi };
        process.Start();

        var stderr = await process.StandardError.ReadToEndAsync(ct);
        await process.WaitForExitAsync(ct);

        if (process.ExitCode != 0)
        {
            var detail = string.IsNullOrWhiteSpace(stderr)
                ? $"Process exited with code {process.ExitCode}"
                : stderr.Trim();
            throw new InvalidOperationException($"Transcription failed: {detail}");
        }

        if (!File.Exists(transcriptionPath))
            throw new InvalidOperationException("Transcription produced no output.");

        var content = File.ReadAllText(transcriptionPath, Encoding.UTF8).Trim();
        if (string.IsNullOrEmpty(content))
            throw new InvalidOperationException("Transcription produced no output.");

        return content;
    }

    private static string? FindScript()
    {
        var baseDir = AppContext.BaseDirectory;

        var path1 = Path.Combine(baseDir, "Python", "transcribe.py");
        if (File.Exists(path1)) return path1;

        var path2 = Path.Combine(baseDir, "transcribe.py");
        if (File.Exists(path2)) return path2;

        var devPath = Path.Combine(baseDir, "..", "..", "..", "Python", "transcribe.py");
        if (File.Exists(devPath)) return Path.GetFullPath(devPath);

        return null;
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    private bool SetField<T>(ref T field, T value, [CallerMemberName] string? name = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value)) return false;
        field = value;
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
        return true;
    }
}
