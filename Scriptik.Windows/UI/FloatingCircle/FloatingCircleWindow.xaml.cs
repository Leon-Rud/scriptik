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
    private DispatcherTimer? _waveformTimer;
    private Storyboard? _pulseStoryboard;
    private bool _isDragging;
    private Point _dragStart;

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
            // Bottom-right of primary screen
            var workArea = SystemParameters.WorkArea;
            Left = workArea.Right - 56 - 16;
            Top = workArea.Bottom - 56 - 16;
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

        // Make non-activating: never steal focus
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
            SetState(new SolidColorBrush(Color.FromRgb(0x22, 0xC5, 0x5E)),  // #22C55E
                showMic: false, showWaveform: false, showTranscribing: false,
                showCheck: true, showPulse: false, showCancel: false);
        }
        else if (_appState.Transcriber.IsTranscribing)
        {
            SetState(new SolidColorBrush(Color.FromRgb(0x00, 0xC8, 0x96)),  // #00C896
                showMic: false, showWaveform: false, showTranscribing: true,
                showCheck: false, showPulse: false, showCancel: false);
        }
        else if (_appState.Recorder.IsRecording)
        {
            SetState(new SolidColorBrush(Color.FromRgb(0xE5, 0x32, 0x2D)),  // #E5322D
                showMic: false, showWaveform: true, showTranscribing: false,
                showCheck: false, showPulse: true, showCancel: true);
            StartWaveformTimer();
        }
        else
        {
            SetState(new SolidColorBrush(Color.FromRgb(0x1B, 0x1F, 0x23)),  // #1B1F23
                showMic: true, showWaveform: false, showTranscribing: false,
                showCheck: false, showPulse: false, showCancel: false);
            StopWaveformTimer();
        }
    }

    private void SetState(SolidColorBrush bg, bool showMic, bool showWaveform,
        bool showTranscribing, bool showCheck, bool showPulse, bool showCancel)
    {
        MainCircle.Background = bg;
        MicIcon.Visibility = showMic ? Visibility.Visible : Visibility.Collapsed;
        WaveformPanel.Visibility = showWaveform ? Visibility.Visible : Visibility.Collapsed;
        TranscribingIcon.Visibility = showTranscribing ? Visibility.Visible : Visibility.Collapsed;
        CheckIcon.Visibility = showCheck ? Visibility.Visible : Visibility.Collapsed;
        CancelButton.Visibility = showCancel ? Visibility.Visible : Visibility.Collapsed;

        if (showPulse) StartPulseAnimation();
        else StopPulseAnimation();

        PulseRing1.Visibility = showPulse ? Visibility.Visible : Visibility.Collapsed;
        PulseRing2.Visibility = showPulse ? Visibility.Visible : Visibility.Collapsed;
    }

    // MARK: - Animations

    private void StartPulseAnimation()
    {
        StopPulseAnimation();

        _pulseStoryboard = new Storyboard();

        AddPulseAnimation(_pulseStoryboard, PulseScale1, PulseRing1, TimeSpan.Zero);
        AddPulseAnimation(_pulseStoryboard, PulseScale2, PulseRing2, TimeSpan.FromMilliseconds(600));

        _pulseStoryboard.Begin(this, true);
    }

    private static void AddPulseAnimation(Storyboard sb, ScaleTransform scale, Ellipse ring, TimeSpan beginTime)
    {
        var scaleXAnim = new DoubleAnimation(1.0, 1.5, TimeSpan.FromMilliseconds(1200))
        {
            RepeatBehavior = RepeatBehavior.Forever,
            BeginTime = beginTime,
        };
        Storyboard.SetTarget(scaleXAnim, ring);
        Storyboard.SetTargetProperty(scaleXAnim,
            new PropertyPath("RenderTransform.ScaleX"));
        sb.Children.Add(scaleXAnim);

        var scaleYAnim = new DoubleAnimation(1.0, 1.5, TimeSpan.FromMilliseconds(1200))
        {
            RepeatBehavior = RepeatBehavior.Forever,
            BeginTime = beginTime,
        };
        Storyboard.SetTarget(scaleYAnim, ring);
        Storyboard.SetTargetProperty(scaleYAnim,
            new PropertyPath("RenderTransform.ScaleY"));
        sb.Children.Add(scaleYAnim);

        var opacityAnim = new DoubleAnimation(1.0, 0.0, TimeSpan.FromMilliseconds(1200))
        {
            RepeatBehavior = RepeatBehavior.Forever,
            BeginTime = beginTime,
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

    private void StartWaveformTimer()
    {
        StopWaveformTimer();
        _waveformTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(50) };
        _waveformTimer.Tick += (_, _) => UpdateWaveformBars();
        _waveformTimer.Start();
    }

    private void StopWaveformTimer()
    {
        _waveformTimer?.Stop();
        _waveformTimer = null;
    }

    private void UpdateWaveformBars()
    {
        var levels = _appState.Recorder.Levels;
        if (levels.Length < 5) return;

        var bars = new Rectangle[] { Bar0, Bar1, Bar2, Bar3, Bar4 };
        for (int i = 0; i < 5; i++)
        {
            var level = levels[levels.Length - 5 + i];
            var height = Math.Max(2, 2 + level * 14); // 2-16px range
            bars[i].Height = height;
        }
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

            // If barely moved, treat as click (toggle recording)
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
