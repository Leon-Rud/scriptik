using System.ComponentModel;
using System.IO;
using System.Runtime.CompilerServices;
using System.Windows.Threading;
using NAudio.CoreAudioApi;
using NAudio.Wave;

namespace Scriptik.Windows.Services;

public class AudioRecorderService : INotifyPropertyChanged
{
    private WasapiCapture? _capture;
    private WaveFileWriter? _writer;
    private DispatcherTimer? _levelTimer;
    private DateTime _startTime;
    private readonly ManualResetEventSlim _recordingStoppedEvent = new(false);

    // Resampler state for converting device format → 16kHz mono 16-bit
    private double _resamplePos;

    private bool _isRecording;
    private float _currentLevel;
    private float[] _levels = new float[20];
    private TimeSpan _elapsedTime;

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
        Directory.CreateDirectory(ConfigManager.DataDir);

        var recordingPath = ConfigManager.RecordingFilePath;
        if (File.Exists(recordingPath))
            File.Delete(recordingPath);

        // Use WASAPI to capture from the Windows default recording device
        var enumerator = new MMDeviceEnumerator();
        MMDevice device;
        try
        {
            device = enumerator.GetDefaultAudioEndpoint(DataFlow.Capture, Role.Communications);
        }
        catch
        {
            throw new InvalidOperationException("No microphone found. Check your audio settings.");
        }

        // Let WASAPI use its native format — we'll convert in OnDataAvailable
        _capture = new WasapiCapture(device);
        _resamplePos = 0;

        // Output: 16kHz mono 16-bit (Whisper format)
        _writer = new WaveFileWriter(recordingPath, new WaveFormat(16000, 16, 1));
        _recordingStoppedEvent.Reset();

        _capture.DataAvailable += OnDataAvailable;
        _capture.RecordingStopped += OnRecordingStopped;
        _capture.StartRecording();

        try { File.WriteAllText(ConfigManager.PidFilePath, "native"); } catch { }

        _startTime = DateTime.Now;
        IsRecording = true;

        _levelTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(50) };
        _levelTimer.Tick += (_, _) => UpdateLevels();
        _levelTimer.Start();
    }

    public string? StopRecording()
    {
        _levelTimer?.Stop();
        _levelTimer = null;

        _capture?.StopRecording();
        _recordingStoppedEvent.Wait(TimeSpan.FromSeconds(2));

        _writer?.Dispose();
        _writer = null;

        _capture?.Dispose();
        _capture = null;

        try { File.Delete(ConfigManager.PidFilePath); } catch { }

        IsRecording = false;
        CurrentLevel = 0;
        Levels = new float[20];
        ElapsedTime = TimeSpan.Zero;

        var recordingPath = ConfigManager.RecordingFilePath;
        if (!File.Exists(recordingPath)) return null;
        return new FileInfo(recordingPath).Length > 1024 ? recordingPath : null;
    }

    private void OnDataAvailable(object? sender, WaveInEventArgs e)
    {
        if (_capture is null || _writer is null || e.BytesRecorded == 0) return;

        var fmt = _capture.WaveFormat;
        var channels = fmt.Channels;
        var srcRate = fmt.SampleRate;
        const int dstRate = 16000;

        // Read all source frames as mono float samples
        var srcFrames = ReadMonoSamples(e.Buffer, e.BytesRecorded, fmt);
        if (srcFrames.Length == 0) return;

        // Resample src → 16kHz using linear interpolation
        double step = (double)srcRate / dstRate;
        double sumSq = 0;
        int count = 0;

        while (_resamplePos < srcFrames.Length - 1)
        {
            int idx = (int)_resamplePos;
            double frac = _resamplePos - idx;
            float sample = (float)(srcFrames[idx] * (1 - frac) + srcFrames[Math.Min(idx + 1, srcFrames.Length - 1)] * frac);
            sample = Math.Clamp(sample, -1f, 1f);

            // Write 16-bit PCM sample
            short pcm = (short)(sample * 32767);
            byte lo = (byte)(pcm & 0xFF);
            byte hi = (byte)((pcm >> 8) & 0xFF);
            _writer.Write(new[] { lo, hi }, 0, 2);

            sumSq += sample * sample;
            count++;

            _resamplePos += step;
        }

        // Keep fractional position for next callback (subtract consumed frames)
        _resamplePos -= srcFrames.Length;
        if (_resamplePos < 0) _resamplePos = 0;

        // Update level meter
        if (count > 0)
        {
            var rms = Math.Sqrt(sumSq / count);
            var dB = rms > 0 ? 20 * Math.Log10(rms) : -100;
            var linear = Math.Max(0, Math.Min(1, (dB + 50) / 50));
            lock (_rmsLock) { _latestRms = (float)Math.Pow(linear, 0.4); }
        }
    }

    /// <summary>
    /// Reads raw audio buffer and returns mono float samples in [-1, 1].
    /// </summary>
    private static float[] ReadMonoSamples(byte[] buffer, int bytesRecorded, WaveFormat fmt)
    {
        int channels = fmt.Channels;
        int bitsPerSample = fmt.BitsPerSample;
        int bytesPerSample = bitsPerSample / 8;
        int frameSize = bytesPerSample * channels;
        int frameCount = bytesRecorded / frameSize;

        if (frameCount == 0) return [];

        var mono = new float[frameCount];

        for (int f = 0; f < frameCount; f++)
        {
            int offset = f * frameSize;
            float sum = 0;

            for (int ch = 0; ch < channels; ch++)
            {
                int sampleOffset = offset + ch * bytesPerSample;
                float val;

                if (bitsPerSample == 32 && fmt.Encoding == WaveFormatEncoding.IeeeFloat)
                {
                    val = BitConverter.ToSingle(buffer, sampleOffset);
                }
                else if (bitsPerSample == 16)
                {
                    val = BitConverter.ToInt16(buffer, sampleOffset) / 32768f;
                }
                else if (bitsPerSample == 24)
                {
                    int raw = buffer[sampleOffset]
                            | (buffer[sampleOffset + 1] << 8)
                            | (buffer[sampleOffset + 2] << 16);
                    if ((raw & 0x800000) != 0) raw |= unchecked((int)0xFF000000);
                    val = raw / 8388608f;
                }
                else
                {
                    val = 0;
                }

                sum += val;
            }

            mono[f] = sum / channels;
        }

        return mono;
    }

    private void OnRecordingStopped(object? sender, StoppedEventArgs e)
    {
        _recordingStoppedEvent.Set();
    }

    private void UpdateLevels()
    {
        float level;
        lock (_rmsLock) { level = _latestRms; }

        CurrentLevel = level;

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
