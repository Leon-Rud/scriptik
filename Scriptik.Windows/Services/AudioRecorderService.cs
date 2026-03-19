using System.ComponentModel;
using System.IO;
using System.Runtime.CompilerServices;
using System.Windows.Threading;
using NAudio.Wave;

namespace Scriptik.Windows.Services;

public class AudioRecorderService : INotifyPropertyChanged
{
    private WaveInEvent? _waveIn;
    private WaveFileWriter? _writer;
    private DispatcherTimer? _levelTimer;
    private DateTime _startTime;

    private bool _isRecording;
    private float _currentLevel;
    private float[] _levels = new float[20];
    private TimeSpan _elapsedTime;

    // Temporary buffer for RMS calculation
    private float _latestRms;
    private readonly object _rmsLock = new();

    public bool IsRecording
    {
        get => _isRecording;
        private set => SetField(ref _isRecording, value);
    }

    public float CurrentLevel
    {
        get => _currentLevel;
        private set => SetField(ref _currentLevel, value);
    }

    public float[] Levels
    {
        get => _levels;
        private set => SetField(ref _levels, value);
    }

    public TimeSpan ElapsedTime
    {
        get => _elapsedTime;
        private set => SetField(ref _elapsedTime, value);
    }

    public void StartRecording()
    {
        if (WaveInEvent.DeviceCount == 0)
            throw new InvalidOperationException("No microphone found. Check your audio settings.");

        // Create temp directory
        Directory.CreateDirectory(ConfigManager.DataDir);

        // Remove old recording
        var recordingPath = ConfigManager.RecordingFilePath;
        if (File.Exists(recordingPath))
            File.Delete(recordingPath);

        // 16kHz mono 16-bit PCM — Whisper-compatible
        var waveFormat = new WaveFormat(16000, 16, 1);

        _waveIn = new WaveInEvent
        {
            WaveFormat = waveFormat,
            BufferMilliseconds = 50
        };

        _writer = new WaveFileWriter(recordingPath, waveFormat);

        _waveIn.DataAvailable += OnDataAvailable;
        _waveIn.RecordingStopped += OnRecordingStopped;
        _waveIn.StartRecording();

        // Write PID file
        try { File.WriteAllText(ConfigManager.PidFilePath, "native"); } catch { }

        _startTime = DateTime.Now;
        IsRecording = true;

        // Level metering timer at ~20fps
        _levelTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(50) };
        _levelTimer.Tick += (_, _) => UpdateLevels();
        _levelTimer.Start();
    }

    public string? StopRecording()
    {
        _levelTimer?.Stop();
        _levelTimer = null;

        // Stop recording first — this triggers RecordingStopped which guarantees
        // no more DataAvailable callbacks, then we safely dispose the writer.
        _waveIn?.StopRecording();

        // Now safe to dispose writer (no more DataAvailable callbacks)
        _writer?.Dispose();
        _writer = null;

        _waveIn?.Dispose();
        _waveIn = null;

        // Remove PID file
        try { File.Delete(ConfigManager.PidFilePath); } catch { }

        IsRecording = false;
        CurrentLevel = 0;
        Levels = new float[20];
        ElapsedTime = TimeSpan.Zero;

        // Verify recording exists and has meaningful content
        var recordingPath = ConfigManager.RecordingFilePath;
        if (!File.Exists(recordingPath)) return null;

        var fileInfo = new FileInfo(recordingPath);
        // WAV header is ~44 bytes; require at least 1KB for usable audio
        return fileInfo.Length > 1024 ? recordingPath : null;
    }

    private void OnDataAvailable(object? sender, WaveInEventArgs e)
    {
        // Write to file
        _writer?.Write(e.Buffer, 0, e.BytesRecorded);

        // Calculate RMS for level metering
        var sampleCount = e.BytesRecorded / 2; // 16-bit = 2 bytes per sample
        if (sampleCount == 0) return;

        double sumSquares = 0;
        for (int i = 0; i < e.BytesRecorded; i += 2)
        {
            var sample = BitConverter.ToInt16(e.Buffer, i);
            var normalized = sample / 32768.0;
            sumSquares += normalized * normalized;
        }

        var rms = Math.Sqrt(sumSquares / sampleCount);
        var dB = rms > 0 ? 20 * Math.Log10(rms) : -100;

        // Same normalization as macOS: dB range (-50...0) to linear (0...1) with power curve
        var linear = Math.Max(0, Math.Min(1, (dB + 50) / 50));
        var normalizedLevel = (float)Math.Pow(linear, 0.4);

        lock (_rmsLock)
        {
            _latestRms = normalizedLevel;
        }
    }

    private void OnRecordingStopped(object? sender, StoppedEventArgs e)
    {
        // Cleanup handled in StopRecording
    }

    private void UpdateLevels()
    {
        float level;
        lock (_rmsLock)
        {
            level = _latestRms;
        }

        CurrentLevel = level;

        // Shift levels array
        var newLevels = new float[20];
        Array.Copy(_levels, 1, newLevels, 0, 19);
        newLevels[19] = level;
        Levels = newLevels;

        ElapsedTime = DateTime.Now - _startTime;
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
