using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Shapes;
using System.Windows.Threading;
using Scriptik.Windows.Core;

namespace Scriptik.Windows.UI.FloatingCircle;

public partial class FloatingCircleWindow : Window
{
    private readonly AppState _appState;
    private DispatcherTimer? _positionSaveTimer;
    private DispatcherTimer? _animationTimer;
    private Storyboard? _pulseStoryboard;
    private bool _isDragging;
    private Point _dragStart;
    private DateTime _animationStart;

    // Smooth bar heights for easing
    private readonly float[] _smoothBarHeights = new float[5];

    // Win32 constants for non-activating window
    private const int WM_MOUSEACTIVATE = 0x0021;
    private const int MA_NOACTIVATE = 0x0003;
    private const int GWL_EXSTYLE = -20;
    private const int WS_EX_NOACTIVATE = 0x08000000;
    private const int WS_EX_TOOLWINDOW = 0x00000080;

    [DllImport("user32.dll")]
    private static extern int GetWindowLong(IntPtr hWnd, int nIndex);

    [DllImport("user32.dll")]
    private static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);

    public FloatingCircleWindow(AppState appState)
    {
        InitializeComponent();
        _appState = appState;

        // Set initial position from config
        if (appState.Config.CirclePositionX >= 0 && appState.Config.CirclePositionY >= 0)
        {
            Left = appState.Config.CirclePositionX;
            Top = appState.Config.CirclePositionY;
        }
        else
        {
            var workArea = SystemParameters.WorkArea;
            Left = workArea.Right - 80 - 16;
            Top = workArea.Bottom - 80 - 16;
        }

        // Subscribe to state changes
        appState.Recorder.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName == nameof(appState.Recorder.IsRecording))
                Dispatcher.InvokeAsync(UpdateVisualState);
        };
        appState.Transcriber.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName == nameof(appState.Transcriber.IsTranscribing))
                Dispatcher.InvokeAsync(UpdateVisualState);
        };
        appState.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName == nameof(appState.ShowCopiedFeedback))
                Dispatcher.InvokeAsync(UpdateVisualState);
        };

        InitPositionSaveTimer();
        LocationChanged += OnLocationChanged;
    }

    protected override void OnSourceInitialized(EventArgs e)
    {
        base.OnSourceInitialized(e);

        var hwnd = new WindowInteropHelper(this).Handle;
        var exStyle = GetWindowLong(hwnd, GWL_EXSTYLE);
        SetWindowLong(hwnd, GWL_EXSTYLE, exStyle | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW);

        var source = HwndSource.FromHwnd(hwnd);
        source?.AddHook(WndProc);
    }

    private IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == WM_MOUSEACTIVATE)
        {
            handled = true;
            return new IntPtr(MA_NOACTIVATE);
        }
        return IntPtr.Zero;
    }

    // MARK: - Visual State

    private void UpdateVisualState()
    {
        var showCopied = _appState.ShowCopiedFeedback &&
                         !_appState.Recorder.IsRecording &&
                         !_appState.Transcriber.IsTranscribing;

        if (showCopied)
        {
            StopAnimationTimer();
            SetState(Color.FromRgb(0x22, 0xC5, 0x5E), shadowColor: Colors.Green, shadowRadius: 5,
                showMic: false, showWaveform: false, showTranscribing: false,
                showCheck: true, showPulse: false, showCancel: false, showElapsed: false);
        }
        else if (_appState.Transcriber.IsTranscribing)
        {
            SetState(Color.FromRgb(0x63, 0x66, 0xF1), shadowColor: Color.FromRgb(0x63, 0x66, 0xF1), shadowRadius: 5,
                showMic: false, showWaveform: false, showTranscribing: true,
                showCheck: false, showPulse: false, showCancel: false, showElapsed: false);
            StartAnimationTimer();
        }
        else if (_appState.Recorder.IsRecording)
        {
            SetState(Color.FromRgb(0xE5, 0x32, 0x2D), shadowColor: Color.FromRgb(0xE5, 0x32, 0x2D), shadowRadius: 6,
                showMic: false, showWaveform: true, showTranscribing: false,
                showCheck: false, showPulse: true, showCancel: true, showElapsed: true);
            _animationStart = DateTime.Now;
            StartAnimationTimer();
        }
        else
        {
            StopAnimationTimer();
            SetState(Color.FromRgb(0x1B, 0x1F, 0x23), shadowColor: Colors.Black, shadowRadius: 4,
                showMic: true, showWaveform: false, showTranscribing: false,
                showCheck: false, showPulse: false, showCancel: false, showElapsed: false);
        }
    }

    private void SetState(Color bg, Color shadowColor, double shadowRadius,
        bool showMic, bool showWaveform, bool showTranscribing,
        bool showCheck, bool showPulse, bool showCancel, bool showElapsed)
    {
        // Semi-transparent background like Mac's ultraThinMaterial
        MainCircle.Background = new SolidColorBrush(Color.FromArgb(0xDD, bg.R, bg.G, bg.B));

        // State-aware shadow like Mac
        CircleShadow.Color = shadowColor;
        CircleShadow.BlurRadius = shadowRadius;
        CircleShadow.Opacity = 0.5;

        MicIcon.Visibility = showMic ? Visibility.Visible : Visibility.Collapsed;
        WaveformPanel.Visibility = showWaveform ? Visibility.Visible : Visibility.Collapsed;
        TranscribingPanel.Visibility = showTranscribing ? Visibility.Visible : Visibility.Collapsed;
        CheckIcon.Visibility = showCheck ? Visibility.Visible : Visibility.Collapsed;
        CancelButton.Visibility = showCancel ? Visibility.Visible : Visibility.Collapsed;
        ElapsedText.Visibility = showElapsed ? Visibility.Visible : Visibility.Collapsed;

        if (showPulse) StartPulseAnimation();
        else StopPulseAnimation();

        PulseRing1.Visibility = showPulse ? Visibility.Visible : Visibility.Collapsed;
        PulseRing2.Visibility = showPulse ? Visibility.Visible : Visibility.Collapsed;
    }

    // MARK: - Pulse Animation (matches Mac easeOut timing)

    private void StartPulseAnimation()
    {
        StopPulseAnimation();

        _pulseStoryboard = new Storyboard();
        AddPulseAnimation(_pulseStoryboard, PulseRing1, TimeSpan.Zero);
        AddPulseAnimation(_pulseStoryboard, PulseRing2, TimeSpan.FromMilliseconds(600));
        _pulseStoryboard.Begin(this, true);
    }

    private static void AddPulseAnimation(Storyboard sb, Ellipse ring, TimeSpan beginTime)
    {
        var ease = new QuadraticEase { EasingMode = EasingMode.EaseOut };
        var duration = TimeSpan.FromMilliseconds(1200);

        var scaleXAnim = new DoubleAnimation(1.0, 1.5, duration)
        {
            RepeatBehavior = RepeatBehavior.Forever,
            BeginTime = beginTime,
            EasingFunction = ease,
        };
        Storyboard.SetTarget(scaleXAnim, ring);
        Storyboard.SetTargetProperty(scaleXAnim, new PropertyPath("RenderTransform.ScaleX"));
        sb.Children.Add(scaleXAnim);

        var scaleYAnim = new DoubleAnimation(1.0, 1.5, duration)
        {
            RepeatBehavior = RepeatBehavior.Forever,
            BeginTime = beginTime,
            EasingFunction = ease,
        };
        Storyboard.SetTarget(scaleYAnim, ring);
        Storyboard.SetTargetProperty(scaleYAnim, new PropertyPath("RenderTransform.ScaleY"));
        sb.Children.Add(scaleYAnim);

        // Mac opacity: 2.0 - scale → starts at 1.0, ends at 0.5
        // Approximate with easeIn so it stays visible longer
        var opacityAnim = new DoubleAnimation(1.0, 0.0, duration)
        {
            RepeatBehavior = RepeatBehavior.Forever,
            BeginTime = beginTime,
            EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseIn },
        };
        Storyboard.SetTarget(opacityAnim, ring);
        Storyboard.SetTargetProperty(opacityAnim, new PropertyPath("Opacity"));
        sb.Children.Add(opacityAnim);
    }

    private void StopPulseAnimation()
    {
        _pulseStoryboard?.Stop(this);
        _pulseStoryboard = null;
    }

    // MARK: - Unified Animation Timer (~60fps for waveform + transcribing)

    private void StartAnimationTimer()
    {
        StopAnimationTimer();
        _animationStart = DateTime.Now;
        // ~60fps for smooth animation like Mac's TimelineView
        _animationTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(16) };
        _animationTimer.Tick += OnAnimationTick;
        _animationTimer.Start();
    }

    private void StopAnimationTimer()
    {
        _animationTimer?.Stop();
        _animationTimer = null;
    }

    private void OnAnimationTick(object? sender, EventArgs e)
    {
        if (_appState.Recorder.IsRecording)
        {
            UpdateRecordingWaveform();
            UpdateElapsedTime();
        }
        else if (_appState.Transcriber.IsTranscribing)
        {
            UpdateTranscribingWaveform();
        }
    }

    private void UpdateRecordingWaveform()
    {
        var levels = _appState.Recorder.Levels;
        if (levels.Length < 5) return;

        var bars = new Rectangle[] { Bar0, Bar1, Bar2, Bar3, Bar4 };
        for (int i = 0; i < 5; i++)
        {
            var level = levels[levels.Length - 5 + i];
            // Mac: minHeight 2, maxHeight 8, mirrored (*2) = 4-16 range
            var targetHeight = Math.Max(4, 4 + level * 12);

            // Smooth easing like Mac's 0.08s easeOut
            _smoothBarHeights[i] += (float)(targetHeight - _smoothBarHeights[i]) * 0.25f;
            bars[i].Height = _smoothBarHeights[i];

            // Opacity varies with level like Mac: 0.4 + 0.6 * normalizedHeight
            var normalizedHeight = (_smoothBarHeights[i] - 4) / 12;
            bars[i].Opacity = 0.4 + 0.6 * normalizedHeight;
        }
    }

    private void UpdateTranscribingWaveform()
    {
        // Mac's procedural sine wave: 0.4 + 0.6 * abs(sin(t * 4 + i * 0.7))
        var t = (DateTime.Now - _animationStart).TotalSeconds;
        var bars = new Rectangle[] { TBar0, TBar1, TBar2, TBar3, TBar4 };

        for (int i = 0; i < 5; i++)
        {
            var wave = 0.4 + 0.6 * Math.Abs(Math.Sin(t * 4 + i * 0.7));
            var height = 4 + wave * 12; // 4-16 range
            bars[i].Height = height;
            bars[i].Opacity = 0.4 + 0.6 * wave;
        }
    }

    private void UpdateElapsedTime()
    {
        var elapsed = _appState.Recorder.ElapsedTime;
        ElapsedText.Text = $"{(int)elapsed.TotalMinutes}:{elapsed.Seconds:D2}";
    }

    // MARK: - Hover effect (like Mac's 1.12x scale)

    protected override void OnMouseEnter(MouseEventArgs e)
    {
        base.OnMouseEnter(e);
        AnimateScale(1.12, TimeSpan.FromMilliseconds(200));
    }

    protected override void OnMouseLeave(MouseEventArgs e)
    {
        base.OnMouseLeave(e);
        AnimateScale(1.0, TimeSpan.FromMilliseconds(200));
    }

    private void AnimateScale(double target, TimeSpan duration)
    {
        var ease = new QuadraticEase { EasingMode = EasingMode.EaseInOut };

        var animX = new DoubleAnimation(target, duration) { EasingFunction = ease };
        var animY = new DoubleAnimation(target, duration) { EasingFunction = ease };

        CircleScale.BeginAnimation(ScaleTransform.ScaleXProperty, animX);
        CircleScale.BeginAnimation(ScaleTransform.ScaleYProperty, animY);
    }

    // MARK: - Drag

    protected override void OnMouseLeftButtonDown(MouseButtonEventArgs e)
    {
        base.OnMouseLeftButtonDown(e);
        _isDragging = true;
        _dragStart = e.GetPosition(this);
        CaptureMouse();
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);
        if (!_isDragging) return;

        var pos = e.GetPosition(this);
        var delta = pos - _dragStart;

        if (Math.Abs(delta.X) > 3 || Math.Abs(delta.Y) > 3)
        {
            Left += delta.X;
            Top += delta.Y;
        }
    }

    protected override void OnMouseLeftButtonUp(MouseButtonEventArgs e)
    {
        base.OnMouseLeftButtonUp(e);

        if (_isDragging)
        {
            var pos = e.GetPosition(this);
            var delta = pos - _dragStart;

            if (Math.Abs(delta.X) <= 3 && Math.Abs(delta.Y) <= 3)
                _appState.Toggle();

            _isDragging = false;
            ReleaseMouseCapture();
        }
    }

    // MARK: - Position persistence (debounced)

    private void InitPositionSaveTimer()
    {
        _positionSaveTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(500) };
        _positionSaveTimer.Tick += (_, _) =>
        {
            _positionSaveTimer!.Stop();
            _appState.Config.CirclePositionX = Left;
            _appState.Config.CirclePositionY = Top;
            _appState.Config.Save();
        };
    }

    private void OnLocationChanged(object? sender, EventArgs e)
    {
        _positionSaveTimer?.Stop();
        _positionSaveTimer?.Start();
    }

    // MARK: - Context menu

    protected override void OnMouseRightButtonDown(MouseButtonEventArgs e)
    {
        base.OnMouseRightButtonDown(e);

        var menu = new System.Windows.Controls.ContextMenu();

        if (_appState.Recorder.IsRecording)
        {
            var cancelItem = new System.Windows.Controls.MenuItem { Header = "Cancel Recording" };
            cancelItem.Click += (_, _) => _appState.CancelRecording();
            menu.Items.Add(cancelItem);
            menu.Items.Add(new System.Windows.Controls.Separator());
        }

        var settingsItem = new System.Windows.Controls.MenuItem { Header = "Settings\u2026" };
        settingsItem.Click += (_, _) =>
        {
            var win = new Settings.SettingsWindow(_appState);
            win.Show();
        };
        menu.Items.Add(settingsItem);

        var historyItem = new System.Windows.Controls.MenuItem { Header = "History\u2026" };
        historyItem.Click += (_, _) =>
        {
            var win = new History.HistoryWindow(_appState.History);
            win.Show();
        };
        menu.Items.Add(historyItem);

        menu.Items.Add(new System.Windows.Controls.Separator());

        var quitItem = new System.Windows.Controls.MenuItem { Header = "Quit Scriptik" };
        quitItem.Click += (_, _) => Application.Current.Shutdown();
        menu.Items.Add(quitItem);

        menu.IsOpen = true;
        e.Handled = true;
    }

    private void CancelButton_Click(object sender, MouseButtonEventArgs e)
    {
        _appState.CancelRecording();
        e.Handled = true;
    }
}
