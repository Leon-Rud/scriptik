using System.Drawing;
using System.Windows;
using System.Windows.Controls;
using Hardcodet.Wpf.TaskbarNotification;
using Scriptik.Windows.Core;

namespace Scriptik.Windows.UI.TrayIcon;

public class TrayIconManager : IDisposable
{
    private TaskbarIcon? _trayIcon;
    private AppState? _appState;

    public void Initialize(AppState appState)
    {
        _appState = appState;

        _trayIcon = new TaskbarIcon
        {
            ToolTipText = "Scriptik",
            ContextMenu = CreateContextMenu(appState),
        };

        UpdateIcon(TrayIconState.Idle);

        // Update icon on state changes
        appState.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName == nameof(AppState.TrayIcon))
                UpdateIcon(appState.TrayIcon);
        };

        // Double-click opens settings
        _trayIcon.TrayMouseDoubleClick += (_, _) => OpenSettings();
    }

    private ContextMenu CreateContextMenu(AppState appState)
    {
        var menu = new ContextMenu();
        menu.Opened += (_, _) => RebuildMenu(menu, appState);
        RebuildMenu(menu, appState);
        return menu;
    }

    private void RebuildMenu(ContextMenu menu, AppState appState)
    {
        menu.Items.Clear();

        // Status
        var statusItem = new MenuItem { Header = appState.StatusText, IsEnabled = false };
        menu.Items.Add(statusItem);
        menu.Items.Add(new Separator());

        // Toggle recording
        if (appState.Recorder.IsRecording)
        {
            var stopItem = new MenuItem { Header = "Stop Recording" };
            stopItem.Click += (_, _) => appState.Toggle();
            menu.Items.Add(stopItem);

            var cancelItem = new MenuItem { Header = "Cancel Recording" };
            cancelItem.Click += (_, _) => appState.CancelRecording();
            menu.Items.Add(cancelItem);
        }
        else if (appState.Transcriber.IsTranscribing)
        {
            menu.Items.Add(new MenuItem { Header = "Transcribing\u2026", IsEnabled = false });
        }
        else
        {
            var startItem = new MenuItem { Header = "Start Recording" };
            startItem.Click += (_, _) => appState.Toggle();
            menu.Items.Add(startItem);
        }

        if (appState.HasLastResult)
        {
            var copyItem = new MenuItem { Header = "Copy Last Result" };
            copyItem.Click += (_, _) => appState.CopyLastResult();
            menu.Items.Add(copyItem);
        }

        menu.Items.Add(new Separator());

        var settingsItem = new MenuItem { Header = "Settings\u2026" };
        settingsItem.Click += (_, _) => OpenSettings();
        menu.Items.Add(settingsItem);

        var historyItem = new MenuItem { Header = "History\u2026" };
        historyItem.Click += (_, _) => OpenHistory();
        menu.Items.Add(historyItem);

        menu.Items.Add(new Separator());

        var quitItem = new MenuItem { Header = "Quit Scriptik" };
        quitItem.Click += (_, _) => Application.Current.Shutdown();
        menu.Items.Add(quitItem);
    }

    private void UpdateIcon(TrayIconState state)
    {
        if (_trayIcon is null) return;

        // Use embedded resource icons or generate programmatically
        try
        {
            var iconUri = state switch
            {
                TrayIconState.Recording => "pack://application:,,,/Resources/Icons/tray-recording.ico",
                TrayIconState.Transcribing => "pack://application:,,,/Resources/Icons/tray-transcribing.ico",
                _ => "pack://application:,,,/Resources/Icons/tray-idle.ico",
            };

            var stream = Application.GetResourceStream(new Uri(iconUri))?.Stream;
            if (stream is not null)
            {
                var newIcon = new Icon(stream);
                var oldIcon = _trayIcon.Icon;
                _trayIcon.Icon = newIcon;
                if (oldIcon is not null && oldIcon != SystemIcons.Application)
                    oldIcon.Dispose();
                return;
            }
        }
        catch { }

        // Fallback: use system icon
        _trayIcon.Icon = SystemIcons.Application;
    }

    private void OpenSettings()
    {
        if (_appState is null) return;

        foreach (System.Windows.Window w in Application.Current.Windows)
        {
            if (w is Settings.SettingsWindow)
            {
                w.Activate();
                return;
            }
        }

        var settings = new Settings.SettingsWindow(_appState);
        settings.Show();
    }

    private void OpenHistory()
    {
        if (_appState is null) return;

        foreach (System.Windows.Window w in Application.Current.Windows)
        {
            if (w is History.HistoryWindow)
            {
                w.Activate();
                return;
            }
        }

        var history = new History.HistoryWindow(_appState.History);
        history.Show();
    }

    public void Dispose()
    {
        _trayIcon?.Dispose();
        _trayIcon = null;
    }
}
