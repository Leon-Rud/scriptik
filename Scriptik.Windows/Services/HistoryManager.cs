using System.ComponentModel;
using System.Globalization;
using System.IO;
using System.Runtime.CompilerServices;

namespace Scriptik.Windows.Services;

public class HistoryManager : INotifyPropertyChanged
{
    public record Entry(string Id, string Filename, DateTime Date, string Content, string Preview);

    private List<Entry> _entries = [];

    public IReadOnlyList<Entry> Entries
    {
        get => _entries;
        private set
        {
            _entries = value.ToList();
            OnPropertyChanged();
        }
    }

    public void Refresh()
    {
        var dirPath = ConfigManager.HistoryDir;
        if (!Directory.Exists(dirPath))
        {
            Entries = [];
            return;
        }

        var result = new List<Entry>();
        var format = "yyyyMMdd_HHmmss";

        foreach (var filePath in Directory.GetFiles(dirPath, "*.txt"))
        {
            var filename = Path.GetFileName(filePath);
            var nameWithoutExt = Path.GetFileNameWithoutExtension(filename);

            if (!DateTime.TryParseExact(nameWithoutExt, format, CultureInfo.InvariantCulture,
                    DateTimeStyles.None, out var date))
                continue;

            var content = "";
            try { content = File.ReadAllText(filePath); } catch { }

            var preview = ExtractPreview(content);
            result.Add(new Entry(nameWithoutExt, filename, date, content, preview));
        }

        result.Sort((a, b) => b.Date.CompareTo(a.Date));
        Entries = result;
    }

    public void Save(string content)
    {
        Directory.CreateDirectory(ConfigManager.HistoryDir);

        var filename = DateTime.Now.ToString("yyyyMMdd_HHmmss", CultureInfo.InvariantCulture) + ".txt";
        var filePath = Path.Combine(ConfigManager.HistoryDir, filename);

        try { File.WriteAllText(filePath, content); } catch { }
    }

    public void Delete(Entry entry)
    {
        var filePath = Path.Combine(ConfigManager.HistoryDir, entry.Filename);
        try { File.Delete(filePath); } catch { }

        var list = _entries.ToList();
        list.RemoveAll(e => e.Id == entry.Id);
        Entries = list;
    }

    public string TotalDuration
    {
        get
        {
            var totalSeconds = _entries.Count * 30;
            var minutes = totalSeconds / 60;
            return minutes < 1 ? $"{totalSeconds} sec" : $"{minutes} min";
        }
    }

    private static string ExtractPreview(string content)
    {
        var lines = content.Split('\n');

        foreach (var line in lines)
        {
            var trimmed = line.Trim();
            if (string.IsNullOrEmpty(trimmed) || trimmed.Contains("[pause")) continue;
            if (!trimmed.Contains("-->")) continue;

            var arrowIdx = trimmed.IndexOf("-->", StringComparison.Ordinal);
            if (arrowIdx < 0) continue;

            var closingIdx = trimmed.IndexOf("] ", arrowIdx, StringComparison.Ordinal);
            if (closingIdx < 0) continue;

            var text = trimmed[(closingIdx + 2)..].Trim();
            if (string.IsNullOrEmpty(text)) continue;

            return text.Length > 80 ? text[..80] + "..." : text;
        }

        foreach (var line in lines)
        {
            var trimmed = line.Trim();
            if (!string.IsNullOrEmpty(trimmed))
                return trimmed.Length > 80 ? trimmed[..80] + "..." : trimmed;
        }

        return "";
    }

    public event PropertyChangedEventHandler? PropertyChanged;
    private void OnPropertyChanged([CallerMemberName] string? name = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}
