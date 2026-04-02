using System.Diagnostics;
using System.IO;

namespace Scriptik.Windows.Services;

/// <summary>
/// Locates ffmpeg and ensures it is on PATH for Python subprocesses.
/// </summary>
public static class FfmpegHelper
{
    private static string? _cachedDir;

    /// <summary>
    /// Adds the ffmpeg bin directory to the PATH environment variable of the given ProcessStartInfo.
    /// </summary>
    public static void InjectPath(ProcessStartInfo psi)
    {
        var dir = FindFfmpegDir();
        if (dir is null) return;

        var currentPath = psi.Environment.TryGetValue("PATH", out var p) ? p : "";
        if (currentPath is not null && currentPath.Contains(dir, StringComparison.OrdinalIgnoreCase))
            return;

        psi.Environment["PATH"] = dir + ";" + currentPath;
        Debug.WriteLine($"Scriptik: added ffmpeg to PATH: {dir}");
    }

    private static string? FindFfmpegDir()
    {
        if (_cachedDir is not null && Directory.Exists(_cachedDir))
            return _cachedDir;

        // 1. Already on system PATH
        var pathDirs = Environment.GetEnvironmentVariable("PATH") ?? "";
        foreach (var dir in pathDirs.Split(';', StringSplitOptions.RemoveEmptyEntries))
        {
            if (File.Exists(Path.Combine(dir, "ffmpeg.exe")))
                return _cachedDir = dir;
        }

        // 2. Refresh from registry (catches installs made after our process started)
        var registryPath = GetPathFromRegistry();
        foreach (var dir in registryPath.Split(';', StringSplitOptions.RemoveEmptyEntries))
        {
            if (File.Exists(Path.Combine(dir, "ffmpeg.exe")))
                return _cachedDir = dir;
        }

        // 3. WinGet install location
        var wingetBase = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Microsoft", "WinGet", "Packages");
        if (Directory.Exists(wingetBase))
        {
            try
            {
                foreach (var pkg in Directory.GetDirectories(wingetBase, "Gyan.FFmpeg*"))
                {
                    foreach (var bin in Directory.GetDirectories(pkg, "bin", SearchOption.AllDirectories))
                    {
                        if (File.Exists(Path.Combine(bin, "ffmpeg.exe")))
                            return _cachedDir = bin;
                    }
                }
            }
            catch { }
        }

        // 4. Chocolatey
        var chocoDir = @"C:\ProgramData\chocolatey\bin";
        if (File.Exists(Path.Combine(chocoDir, "ffmpeg.exe")))
            return _cachedDir = chocoDir;

        // 5. Scoop
        var scoopDir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            "scoop", "shims");
        if (File.Exists(Path.Combine(scoopDir, "ffmpeg.exe")))
            return _cachedDir = scoopDir;

        Debug.WriteLine("Scriptik: ffmpeg not found");
        return null;
    }

    private static string GetPathFromRegistry()
    {
        try
        {
            // Read both user and machine PATH from registry (freshest source)
            var userPath = Microsoft.Win32.Registry.CurrentUser
                .OpenSubKey(@"Environment")
                ?.GetValue("Path", "") as string ?? "";
            var machinePath = Microsoft.Win32.Registry.LocalMachine
                .OpenSubKey(@"SYSTEM\CurrentControlSet\Control\Session Manager\Environment")
                ?.GetValue("Path", "") as string ?? "";
            return userPath + ";" + machinePath;
        }
        catch
        {
            return "";
        }
    }
}
