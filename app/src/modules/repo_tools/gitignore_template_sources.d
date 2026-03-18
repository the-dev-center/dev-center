module modules.repo_tools.gitignore_template_sources;

import std.file : exists, isDir, dirEntries, SpanMode, readText;
import std.path : buildPath, baseName, dirName, relativePath;
import std.algorithm : endsWith;

/// Template source for .gitignore files.
enum GitIgnoreSource
{
    DevCentr,  /// DevCentr templates repo (whitelist + ecosystems)
    GitHub,    /// github/gitignore (root, Global, community)
    Local,     /// Local folder
}

/// A single gitignore template (name + path or identifier).
struct GitIgnoreTemplate
{
    string id;       /// e.g. "Node", "VisualStudioCode", "d"
    string name;     /// Display name
    string path;     /// Full path (DevCentr/Local) or relative path (GitHub)
    string category; /// "root" | "Global" | "community" | "ecosystem"
}

/// Lists gitignore templates from DevCentr cache.
GitIgnoreTemplate[] listFromDevCentr(string cachePath)
{
    GitIgnoreTemplate[] result;
    auto workspacesPath = buildPath(cachePath, "repo", "workspaces");
    if (!exists(workspacesPath)) return result;

    foreach (entry; dirEntries(workspacesPath, SpanMode.shallow))
    {
        if (entry.isDir && baseName(entry.name)[0] != '_')
        {
            GitIgnoreTemplate t;
            t.id = baseName(entry.name);
            t.name = t.id;
            t.path = buildPath(entry.name, ".gitignore");
            t.category = "ecosystem";
            if (exists(t.path)) result ~= t;
        }
    }
    return result;
}

/// Lists gitignore templates from GitHub gitignore cache (cloned repo).
/// Structure: root/*.gitignore, Global/*.gitignore, community/**/*.gitignore
GitIgnoreTemplate[] listFromGitHub(string cachePath)
{
    GitIgnoreTemplate[] result;
    if (!exists(cachePath)) return result;

    // Root: *.gitignore files
    foreach (entry; dirEntries(cachePath, SpanMode.shallow))
    {
        if (!entry.isDir && endsWith(entry.name, ".gitignore"))
        {
            GitIgnoreTemplate t;
            t.id = baseName(entry.name);
            t.name = t.id[0 .. $-9]; // strip .gitignore
            t.path = entry.name;
            t.category = "root";
            result ~= t;
        }
    }

    // Global/
    auto globalPath = buildPath(cachePath, "Global");
    if (exists(globalPath))
    {
        foreach (entry; dirEntries(globalPath, SpanMode.shallow))
        {
            if (!entry.isDir && endsWith(entry.name, ".gitignore"))
            {
                GitIgnoreTemplate t;
                t.id = "Global/" ~ baseName(entry.name);
                t.name = baseName(entry.name)[0 .. $-9];
                t.path = entry.name;
                t.category = "Global";
                result ~= t;
            }
        }
    }

    // community/**/*.gitignore
    auto communityPath = buildPath(cachePath, "community");
    if (exists(communityPath))
    {
        foreach (entry; dirEntries(communityPath, SpanMode.depth))
        {
            if (!entry.isDir && endsWith(entry.name, ".gitignore"))
            {
                auto rel = entry.name.length > cachePath.length
                    ? entry.name[cachePath.length + 1 .. $]
                    : baseName(entry.name);
                GitIgnoreTemplate t;
                t.id = rel;
                t.name = baseName(entry.name)[0 .. $-9];
                t.path = entry.name;
                t.category = "community";
                result ~= t;
            }
        }
    }
    return result;
}

/// Lists gitignore templates from a local folder (flat or nested).
GitIgnoreTemplate[] listFromLocal(string folderPath)
{
    GitIgnoreTemplate[] result;
    if (!exists(folderPath) || !isDir(folderPath)) return result;

    foreach (entry; dirEntries(folderPath, SpanMode.depth))
    {
        if (!entry.isDir && endsWith(entry.name, ".gitignore"))
        {
            GitIgnoreTemplate t;
            t.id = baseName(entry.name);
            t.name = baseName(entry.name)[0 .. $-9];
            t.path = entry.name;
            t.category = "local";
            result ~= t;
        }
    }
    return result;
}

/// Reads template content from path. Returns empty string on failure.
string readTemplateContent(string path)
{
    if (!exists(path)) return "";
    return readText(path);
}
