module app.src.modules.repo_tools.repo_browser;

import std.file : dirEntries, SpanMode, exists, isDir;
import std.path : buildPath, baseName, dirName;
import std.algorithm : sort, filter, canFind;
import std.array : array;
import std.conv : to;
import std.string : toLower;

/// A node in the host / owner / repo hierarchy.
struct RepoNode
{
    string host;
    string owner;
    string name;
    string fullPath; /// Absolute path to the repo root.
    bool isGitRepo;  /// True when a `.git` folder exists inside.
    bool isFork;     /// True when the repo is inside a `.forks` dir.
    bool isClone;    /// True when the repo is inside a `.clones` dir.
}

/// Scan `codeRoot` (e.g. `Z:\code`) and return every repository found under
/// the host/owner/repo schema described in FOLDER_SCHEMA.md.
///
/// The function understands:
///   $ROOT/<host>/<owner>/<repo>
///   $ROOT/<host>/<owner>/.forks/<repo>
///   $ROOT/<host>/.clones/<owner>/<repo>
RepoNode[] scanCodeRoot(string codeRoot)
{
    RepoNode[] nodes;

    if (!exists(codeRoot) || !isDir(codeRoot))
        return nodes;

    // Level 1: hosts (github.com, gitlab.com, …)
    foreach (hostEntry; dirEntries(codeRoot, SpanMode.shallow))
    {
        if (!hostEntry.isDir)
            continue;
        string hostName = baseName(hostEntry.name);
        if (hostName.length == 0 || hostName[0] == '.')
            continue; // skip hidden dirs at host level

        // Level 2: owners / .clones
        foreach (ownerEntry; dirEntries(hostEntry.name, SpanMode.shallow))
        {
            if (!ownerEntry.isDir)
                continue;
            string ownerName = baseName(ownerEntry.name);

            if (ownerName == ".clones")
            {
                // .clones/<real_owner>/<repo>
                foreach (cloneOwnerEntry; dirEntries(ownerEntry.name, SpanMode.shallow))
                {
                    if (!cloneOwnerEntry.isDir)
                        continue;
                    string cloneOwner = baseName(cloneOwnerEntry.name);
                    foreach (repoEntry; dirEntries(cloneOwnerEntry.name, SpanMode.shallow))
                    {
                        if (!repoEntry.isDir)
                            continue;
                        string repoName = baseName(repoEntry.name);
                        bool hasGit = exists(buildPath(repoEntry.name, ".git"));
                        nodes ~= RepoNode(hostName, cloneOwner, repoName, repoEntry.name, hasGit, false, true);
                    }
                }
                continue;
            }

            if (ownerName.length > 0 && ownerName[0] == '.')
                continue; // skip other hidden dirs at owner level

            // Level 3: repos + .forks
            foreach (repoEntry; dirEntries(ownerEntry.name, SpanMode.shallow))
            {
                if (!repoEntry.isDir)
                    continue;
                string repoName = baseName(repoEntry.name);

                if (repoName == ".forks")
                {
                    // .forks/<repo>
                    foreach (forkEntry; dirEntries(repoEntry.name, SpanMode.shallow))
                    {
                        if (!forkEntry.isDir)
                            continue;
                        string forkName = baseName(forkEntry.name);
                        bool hasGit = exists(buildPath(forkEntry.name, ".git"));
                        nodes ~= RepoNode(hostName, ownerName, forkName, forkEntry.name, hasGit, true, false);
                    }
                    continue;
                }

                if (repoName.length > 0 && repoName[0] == '.')
                    continue; // skip other hidden dirs

                bool hasGit = exists(buildPath(repoEntry.name, ".git"));
                nodes ~= RepoNode(hostName, ownerName, repoName, repoEntry.name, hasGit, false, false);
            }
        }
    }

    // Sort: host → owner → name
    nodes.sort!((a, b) {
        if (a.host != b.host) return a.host < b.host;
        if (a.owner != b.owner) return a.owner < b.owner;
        return a.name < b.name;
    });

    return nodes;
}

/// Filter repos by a search query (case-insensitive match against host, owner, or name).
RepoNode[] filterRepos(RepoNode[] repos, string query)
{
    if (query.length == 0)
        return repos;
    string q = query.toLower();
    return repos.filter!(r =>
        r.host.toLower().canFind(q) ||
        r.owner.toLower().canFind(q) ||
        r.name.toLower().canFind(q)
    ).array();
}
