using System.Media;
using System.Windows;

namespace Scriptik.Windows.Services;

public enum SoundEvent { Begin, End, Cancel }

public class SoundService : IDisposable
{
    private readonly ConfigManager _config;
    private readonly Dictionary<SoundEvent, SoundPlayer?> _players = new();
    private bool _initialized;

    public SoundService(ConfigManager config)
    {
        _config = config;
    }

    public void Play(SoundEvent ev)
    {
        if (!_config.EnableSoundFeedback) return;

        EnsureInitialized();

        try
        {
            if (_players.TryGetValue(ev, out var player) && player is not null)
            {
                player.Play();
            }
            else
            {
                SystemSounds.Beep.Play();
            }
        }
        catch
        {
            try { SystemSounds.Beep.Play(); } catch { }
        }
    }

    private void EnsureInitialized()
    {
        if (_initialized) return;
        _initialized = true;

        LoadPlayer(SoundEvent.Begin, "Resources/Sounds/begin.wav");
        LoadPlayer(SoundEvent.End, "Resources/Sounds/end.wav");
        LoadPlayer(SoundEvent.Cancel, "Resources/Sounds/cancel.wav");
    }

    private void LoadPlayer(SoundEvent ev, string resourcePath)
    {
        try
        {
            var uri = new Uri(resourcePath, UriKind.Relative);
            var streamInfo = Application.GetResourceStream(uri);
            if (streamInfo?.Stream is not null)
            {
                var player = new SoundPlayer(streamInfo.Stream);
                player.Load();
                _players[ev] = player;
            }
        }
        catch
        {
            _players[ev] = null;
        }
    }

    public void Dispose()
    {
        foreach (var player in _players.Values)
            player?.Dispose();
        _players.Clear();
    }
}
