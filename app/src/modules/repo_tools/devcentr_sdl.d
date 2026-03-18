/// Read and write .devcentr.sdl for per-repo settings such as gitignore suppressions.
module modules.repo_tools.devcentr_sdl;

import std.file : exists, readText, write, mkdirRecurse;
import std.path : buildPath, dirName;
import std.string : strip, endsWith, replace;
import std.algorithm : filter, canFind, countUntil;
import std.array : array;
import sdlang;

/// Load suppressed gitignore patterns from .devcentr.sdl. Returns empty array if file missing.
string[] loadGitignoreSuppressions(string repoRoot)
{
    auto path = buildPath(repoRoot, ".devcentr.sdl");
    if (!exists(path)) return [];
    try
    {
        auto content = readText(path);
        auto root = parseSource(content, path);
        auto gitignoreTag = root.getTag("gitignore");
        if (gitignoreTag is null) return [];
        auto suppressTag = gitignoreTag.getTag("suppressMissing");
        if (suppressTag is null) return [];
        string[] arr;
        foreach (val; suppressTag.values)
            if (val.toString().length > 0) arr ~= val.get!string;
        return arr;
    }
    catch (Exception) { return []; }
}

/// Add or ensure a suppression exists. Writes back to .devcentr.sdl.
void addGitignoreSuppression(string repoRoot, string pattern)
{
    auto path = buildPath(repoRoot, ".devcentr.sdl");
    string[] suppressions = loadGitignoreSuppressions(repoRoot);
    if (suppressions.canFind(pattern)) return;
    suppressions ~= pattern;
    saveGitignoreSuppressions(repoRoot, suppressions);
}

/// Remove a suppression.
void removeGitignoreSuppression(string repoRoot, string pattern)
{
    auto suppressions = loadGitignoreSuppressions(repoRoot).filter!(p => p != pattern).array;
    saveGitignoreSuppressions(repoRoot, suppressions);
}

/// Save suppressions to .devcentr.sdl. Creates file if needed.
void saveGitignoreSuppressions(string repoRoot, string[] suppressions)
{
    auto path = buildPath(repoRoot, ".devcentr.sdl");
    string content;
    if (exists(path))
    {
        content = readText(path);
        if (content.canFind("gitignore"))
        {
            auto root = parseSource(content, path);
            auto gitignoreTag = root.getTag("gitignore");
            if (gitignoreTag !is null)
            {
                auto start = countUntil(content, "gitignore");
                if (start < 0) start = 0;
                string before = content[0 .. start];
                size_t endIdx = content.length;
                size_t depth = 0;
                for (size_t i = start; i < content.length; i++)
                {
                    if (content[i] == '{') depth++;
                    else if (content[i] == '}')
                    {
                        depth--;
                        if (depth == 0) { endIdx = i + 1; break; }
                    }
                }
                string after = content[endIdx .. $];
                content = before ~ buildGitignoreBlock(suppressions) ~ after;
                write(path, content);
                return;
            }
        }
    }
    if (content.length > 0 && !content.strip().endsWith("\n\n"))
        content ~= "\n\n";
    content ~= buildGitignoreBlock(suppressions);
    write(path, content);
}

private string buildGitignoreBlock(string[] suppressions)
{
    if (suppressions.length == 0) return "gitignore { suppressMissing [] }\n";
    string s = "gitignore {\n  suppressMissing [\n";
    foreach (p; suppressions)
        s ~= "    \"" ~ p.replace("\"", "\\\"") ~ "\"\n";
    s ~= "  ]\n}\n";
    return s;
}
