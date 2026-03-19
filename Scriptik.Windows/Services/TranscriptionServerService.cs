using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Runtime.CompilerServices;
using System.Text;
using System.Text.Json;

namespace Scriptik.Windows.Services;

public enum ServerState { Stopped, Starting, Ready, Busy }

public class TranscriptionServerService : INotifyPropertyChanged
{
    private ServerState _state = ServerState.Stopped;
    private Process? _process;
    private StreamWriter? _stdinWriter;
    private string? _currentModelName;
    private string? _lastPythonPath; // Remember python path for auto-restart

    private readonly object _completionLock = new();
    private TaskCompletionSource<Dictionary<string, object?>>? _pendingCompletion;
    private TaskCompletionSource<bool>? _readyCompletion;

    public ServerState State
    {
        get => _state;
        private set => SetField(ref _state, value);
    }

    // MARK: - Lifecycle

    public void Start(ConfigManager config) => Start(config.WhisperPythonPath, config.WhisperModel);

    public void Start(string pythonPath, string model)
    {
        if (State != ServerState.Stopped) return;
        State = ServerState.Starting;
        _currentModelName = model;
        _lastPythonPath = pythonPath;

        var scriptPath = FindServerScript();
        if (scriptPath is null)
        {
            Debug.WriteLine("Scriptik: transcribe_server.py not found");
            State = ServerState.Stopped;
            return;
        }

        if (!File.Exists(pythonPath))
        {
            Debug.WriteLine($"Scriptik: Python not found at {pythonPath}");
            State = ServerState.Stopped;
            return;
        }

        var psi = new ProcessStartInfo
        {
            FileName = pythonPath,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8,
        };
        psi.ArgumentList.Add(scriptPath);
        psi.ArgumentList.Add(model);
        psi.Environment["PYTHONUNBUFFERED"] = "1";
        psi.Environment["PYTHONIOENCODING"] = "utf-8";
        psi.Environment["PYTHONUTF8"] = "1";

        var proc = new Process { StartInfo = psi, EnableRaisingEvents = true };
        proc.Exited += (_, _) => OnProcessExited(proc.ExitCode);

        try
        {
            proc.Start();
            _process = proc;
            _stdinWriter = proc.StandardInput;
            _stdinWriter.AutoFlush = true;

            Debug.WriteLine($"Scriptik: server process launched (pid {proc.Id}, model: {model})");

            _ = Task.Run(() => ReadStdoutLoop(proc));
            _ = Task.Run(() => ReadStderrLoop(proc));
            _ = WaitForReadyAsync(TimeSpan.FromSeconds(30));
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Scriptik: failed to launch server: {ex.Message}");
            State = ServerState.Stopped;
        }
    }

    public void Stop()
    {
        var proc = _process;
        _process = null;
        _stdinWriter = null;
        State = ServerState.Stopped;

        lock (_completionLock)
        {
            _readyCompletion?.TrySetCanceled();
            _readyCompletion = null;
            _pendingCompletion?.TrySetCanceled();
            _pendingCompletion = null;
        }

        if (proc is not null && !proc.HasExited)
        {
            try { proc.Kill(); } catch { }
            Debug.WriteLine("Scriptik: server process terminated");
        }
    }

    // MARK: - Transcription

    public async Task<string> TranscribeAsync(
        string recordingPath, string transcriptionPath,
        double pauseThreshold, string model,
        string initialPrompt, string language,
        CancellationToken ct = default)
    {
        if (State != ServerState.Ready && State != ServerState.Starting)
            throw new InvalidOperationException("Transcription server is not ready.");

        if (State == ServerState.Starting)
            await WaitForReadyAsync(TimeSpan.FromSeconds(30));

        State = ServerState.Busy;

        try
        {
            var request = new Dictionary<string, object?>
            {
                ["type"] = "transcribe",
                ["recording_path"] = recordingPath,
                ["transcription_path"] = transcriptionPath,
                ["pause_threshold"] = pauseThreshold,
                ["model"] = model,
                ["initial_prompt"] = initialPrompt,
                ["language"] = language,
            };

            var response = await SendRequestAsync(request, TimeSpan.FromSeconds(120), ct);

            var type = response.GetValueOrDefault("type")?.ToString();
            if (type == "error")
            {
                var msg = response.GetValueOrDefault("message")?.ToString() ?? "Unknown server error";
                throw new InvalidOperationException($"Server error: {msg}");
            }

            if (type != "transcription_done")
                throw new InvalidOperationException("Invalid response from transcription server.");

            var content = File.ReadAllText(transcriptionPath, Encoding.UTF8).Trim();
            if (string.IsNullOrEmpty(content))
                throw new InvalidOperationException("Transcription produced no output.");

            return content;
        }
        finally
        {
            if (State == ServerState.Busy)
                System.Windows.Application.Current?.Dispatcher.Invoke(() => State = ServerState.Ready);
        }
    }

    // MARK: - Model Reload (fire-and-forget but properly async Task)

    public async Task ReloadModelAsync(string model)
    {
        if (State != ServerState.Ready) return;
        _currentModelName = model;
        State = ServerState.Busy;

        try
        {
            var request = new Dictionary<string, object?> { ["type"] = "reload_model", ["model"] = model };
            var response = await SendRequestAsync(request, TimeSpan.FromSeconds(60));
            var type = response.GetValueOrDefault("type")?.ToString();

            if (type == "model_reloaded")
                Debug.WriteLine($"Scriptik: server reloaded model to {model}");
            else if (type == "error")
                Debug.WriteLine($"Scriptik: server reload error: {response.GetValueOrDefault("message")}");
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Scriptik: model reload failed: {ex.Message}");
        }
        finally
        {
            State = ServerState.Ready;
        }
    }

    // MARK: - Private

    private async Task<Dictionary<string, object?>> SendRequestAsync(
        Dictionary<string, object?> request,
        TimeSpan timeout,
        CancellationToken ct = default)
    {
        if (_stdinWriter is null)
            throw new InvalidOperationException("Server not ready.");

        var tcs = new TaskCompletionSource<Dictionary<string, object?>>();
        lock (_completionLock)
        {
            _pendingCompletion = tcs;
        }

        var json = JsonSerializer.Serialize(request);
        await _stdinWriter.WriteLineAsync(json);

        using var cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        cts.CancelAfter(timeout);
        await using var reg = cts.Token.Register(() => tcs.TrySetException(
            new TimeoutException("Transcription server timed out.")));

        return await tcs.Task;
    }

    private async Task WaitForReadyAsync(TimeSpan timeout)
    {
        if (State == ServerState.Ready) return;
        if (State != ServerState.Starting)
            throw new InvalidOperationException("Server is not starting.");

        var tcs = new TaskCompletionSource<bool>();
        lock (_completionLock)
        {
            _readyCompletion = tcs;
        }

        using var cts = new CancellationTokenSource(timeout);
        await using var reg = cts.Token.Register(() => tcs.TrySetException(
            new TimeoutException("Server failed to become ready.")));

        await tcs.Task;
        Debug.WriteLine($"Scriptik: server ready (model: {_currentModelName})");
    }

    private async Task ReadStdoutLoop(Process proc)
    {
        try
        {
            var reader = proc.StandardOutput;
            while (!proc.HasExited)
            {
                var line = await reader.ReadLineAsync();
                if (line is null) break;
                if (string.IsNullOrEmpty(line)) continue;

                HandleOutput(line);
            }
        }
        catch { }
    }

    private async Task ReadStderrLoop(Process proc)
    {
        try
        {
            var reader = proc.StandardError;
            while (!proc.HasExited)
            {
                var line = await reader.ReadLineAsync();
                if (line is null) break;
                if (!string.IsNullOrWhiteSpace(line))
                    Debug.WriteLine($"Scriptik server stderr: {line.Trim()}");
            }
        }
        catch { }
    }

    private void HandleOutput(string line)
    {
        try
        {
            var json = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(line);
            if (json is null || !json.TryGetValue("type", out var typeElem)) return;

            var type = typeElem.GetString();
            var dict = json.ToDictionary(
                kvp => kvp.Key,
                kvp => (object?)kvp.Value.ToString());

            switch (type)
            {
                case "ready":
                    System.Windows.Application.Current?.Dispatcher.InvokeAsync(() =>
                    {
                        State = ServerState.Ready;
                        lock (_completionLock)
                        {
                            _readyCompletion?.TrySetResult(true);
                            _readyCompletion = null;
                        }
                    });
                    break;

                case "pong":
                case "transcription_done":
                case "model_reloaded":
                case "error":
                    // Dispatch to UI thread to ensure State changes are safe
                    System.Windows.Application.Current?.Dispatcher.InvokeAsync(() =>
                    {
                        lock (_completionLock)
                        {
                            _pendingCompletion?.TrySetResult(dict);
                            _pendingCompletion = null;
                        }
                    });
                    break;

                default:
                    Debug.WriteLine($"Scriptik server: unknown response type: {type}");
                    break;
            }
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Scriptik server: unparseable line: {line} ({ex.Message})");
        }
    }

    private void OnProcessExited(int exitCode)
    {
        Debug.WriteLine($"Scriptik: server process terminated with code {exitCode}");

        var wasRunning = State != ServerState.Stopped;
        var modelName = _currentModelName ?? "medium";
        var pythonPath = _lastPythonPath; // Use the configured path, not hardcoded

        lock (_completionLock)
        {
            _readyCompletion?.TrySetException(new InvalidOperationException("Server process terminated."));
            _readyCompletion = null;
            _pendingCompletion?.TrySetException(new InvalidOperationException("Server process terminated."));
            _pendingCompletion = null;
        }

        State = ServerState.Stopped;
        _process = null;
        _stdinWriter = null;

        // Auto-restart if it was running
        if (wasRunning && pythonPath is not null)
        {
            Debug.WriteLine("Scriptik: auto-restarting server in 500ms");
            _ = Task.Run(async () =>
            {
                await Task.Delay(500);
                if (File.Exists(pythonPath))
                {
                    System.Windows.Application.Current?.Dispatcher.InvokeAsync(() =>
                        Start(pythonPath, modelName));
                }
            });
        }
    }

    private static string? FindServerScript()
    {
        var baseDir = AppContext.BaseDirectory;
        var path1 = Path.Combine(baseDir, "Python", "transcribe_server.py");
        if (File.Exists(path1)) return path1;

        var path2 = Path.Combine(baseDir, "transcribe_server.py");
        if (File.Exists(path2)) return path2;

        var devPath = Path.Combine(baseDir, "..", "..", "..", "Python", "transcribe_server.py");
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
