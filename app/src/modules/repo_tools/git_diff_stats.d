module modules.repo_tools.git_diff_stats;

import std.array : array;
import std.algorithm : splitter;
import std.string : strip;
import std.conv : to;
import std.exception : collectException;


/// Aggregated diff statistics for a repository.
struct DiffStats
{
    bool isDirty;
    size_t filesChanged;
    size_t linesAdded;
    size_t linesRemoved;
}

/// Run a git command in the given repository and return stdout as lines.
private string[] runGit(string repoRoot, string[] args, out int status)
{
    import std.process : pipeProcess, Redirect, Config, wait;
    import std.string : splitLines;

    try
    {
        auto pipes = pipeProcess(["git"] ~ args, Redirect.stdout | Redirect.stderr, null, Config.none, repoRoot);
        string output;
        foreach (line; pipes.stdout.byLine)
        {
            output ~= line.idup ~ "\n";
        }
        status = pipes.pid.wait();
        return output.splitLines();
    }
    catch (Exception e)
    {
        status = -1;
        return [];
    }
}


/// Compute aggregated diff stats for the working tree vs HEAD.
DiffStats computeDiffStats(string repoRoot)
{
    DiffStats stats;

    // First, check if the working tree is dirty.
    int status;
    auto statusLines = runGit(repoRoot, ["status", "--porcelain=v1"], status);
    if (status != 0 || statusLines.length == 0)
    {
        stats.isDirty = false;
        return stats;
    }

    stats.isDirty = true;

    // Now compute numstat.
    auto numstatLines = runGit(repoRoot, ["diff", "--numstat"], status);
    if (status != 0)
    {
        return stats;
    }

    foreach (line; numstatLines)
    {
        auto trimmed = line.strip();
        if (trimmed.length == 0)
            continue;

        auto parts = trimmed.splitter('\t').array;
        if (parts.length < 3)
            continue;

        auto addedStr = parts[0];
        auto removedStr = parts[1];

        size_t added = 0;
        size_t removed = 0;

        // Binary files show '-' instead of counts; treat them as 0 lines changed.
        if (addedStr != "-")
        {
            auto exA = collectException({ added = to!size_t(addedStr); });
            if (exA)
                added = 0;
        }
        if (removedStr != "-")
        {
            auto exR = collectException({ removed = to!size_t(removedStr); });
            if (exR)
                removed = 0;
        }

        stats.filesChanged++;
        stats.linesAdded += added;
        stats.linesRemoved += removed;
    }

    return stats;
}

