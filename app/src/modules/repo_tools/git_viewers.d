module modules.repo_tools.git_viewers;

import std.file : exists, isFile;
import std.path : buildPath;
import std.process : environment;
import std.string : splitter;
import std.array : array;

/// Type of Git viewer.
enum GitViewerType
{
    builtin,
    external,
}

/// Git viewer definition.
struct GitViewer
{
    string id;
    string label;
    GitViewerType kind;
    string icon;
    string executable;      /// For external viewers.
    string[] argsTemplate;  /// For external viewers.
}

/// Return true if the given executable appears to be installed on this system.
bool isExecutableInstalled(string exeName)
{
    version(Windows)
    {
        auto path = environment.get("PATH");
        if (path.length == 0)
            return false;
        auto segments = path.splitter(';').array;
        foreach (seg; segments)
        {
            auto candidate = buildPath(seg, exeName);
            if (isFile(candidate))
            {
                return true;
            }
            // On Windows, the shell will also add .exe; try that if not present.
            if (!exeName.endsWith(".exe"))
            {
                auto candidateExe = candidate ~ ".exe";
                if (isFile(candidateExe))
                {
                    return true;
                }
            }
        }
        return false;
    }
    else
    {
        auto path = environment.get("PATH");
        if (path.length == 0)
            return false;
        auto segments = path.splitter(':').array;
        foreach (seg; segments)
        {
            auto candidate = buildPath(seg, exeName);
            if (isFile(candidate))
            {
                return true;
            }
        }
        return false;
    }
}

/// Return the list of Git viewers that are considered installed.
GitViewer[] detectInstalledViewers()
{
    GitViewer[] viewers;

    // Always include the built-in DevCentr Git viewer.
    viewers ~= GitViewer(
        "devcentr-builtin",
        "DevCentr Git Viewer",
        GitViewerType.builtin,
        "builtin-git-viewer",
        "",
        [],
    );

    // Example of external viewers that may be installed.
    GitViewer[] candidates = [
        GitViewer("gitkraken", "GitKraken", GitViewerType.external, "gitkraken", "gitkraken", []),
        GitViewer("sourcetree", "Sourcetree", GitViewerType.external, "sourcetree", "SourceTree", []),
        GitViewer("fork", "Fork", GitViewerType.external, "fork", "fork", []),
    ];

    foreach (c; candidates)
    {
        if (isExecutableInstalled(c.executable))
        {
            viewers ~= c;
        }
    }

    return viewers;
}

