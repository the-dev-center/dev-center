module modules.template_installer.installer;

import std.file : exists, isDir, dirEntries, SpanMode, mkdirRecurse, copy, readText, write, remove, rmdirRecurse;
import std.path : dirName, buildPath, baseName, absolutePath, relativePath;
import std.datetime : SysTime, Clock, Duration, hours;
import std.process : execute, Config;
import std.json : JSONValue, parseJSON, JSONType;
import std.array : array;
import std.algorithm.iteration : filter, map;
import std.algorithm.searching : canFind;
import std.exception : enforce;

/// Information about an available template.
struct TemplateInfo
{
    string id;
    string name;
    string description;
    string path;
    string[] tags;
    string parent;
}

/// Metadata for the template cache.
struct CacheMetadata
{
    SysTime lastUpdated;
    string remoteUrl;
}

/// Class responsible for managing and installing templates.
class TemplateInstaller
{
    private string cacheRoot;
    private string templatesRepoUrl;

    this(string cacheRoot, string templatesRepoUrl = "https://github.com/the-dev-center/templates.git")
    {
        this.cacheRoot = absolutePath(cacheRoot);
        this.templatesRepoUrl = templatesRepoUrl;
    }

    /// Returns the path to the template cache.
    @property string cachePath() const { return cacheRoot; }

    /// Path to cached github/gitignore repo (sibling of templates cache).
    @property string githubGitIgnorePath() const
    {
        return buildPath(dirName(cacheRoot), "github-gitignore");
    }

    /// Ensures github/gitignore is cloned and up to date. Returns true on success.
    bool ensureGitHubGitIgnoreCache(bool forceful = false)
    {
        auto path = githubGitIgnorePath;
        auto metadataPath = buildPath(path, ".git");
        bool needsSync = forceful || !exists(metadataPath);
        if (!needsSync)
        {
            try
            {
                auto meta = buildPath(dirName(path), "github-gitignore-metadata.json");
                if (exists(meta))
                {
                    auto content = readText(meta);
                    auto json = parseJSON(content);
                    auto lastStr = json["lastUpdated"].str;
                    auto last = SysTime.fromISOExtString(lastStr);
                    if (Clock.currTime() - last > hours(24)) needsSync = true;
                }
                else needsSync = true;
            }
            catch (Exception) { needsSync = true; }
        }
        if (!needsSync) return true;
        mkdirRecurse(dirName(path));
        if (!exists(path))
        {
            auto r = execute(["git", "clone", "--depth", "1", "https://github.com/github/gitignore.git", path]);
            if (r.status != 0) return false;
        }
        else
        {
            auto r = execute(["git", "-C", path, "pull"]);
            if (r.status != 0) return false;
        }
        JSONValue metadata;
        metadata["lastUpdated"] = JSONValue(Clock.currTime().toISOExtString());
        write(buildPath(dirName(path), "github-gitignore-metadata.json"), metadata.toString());
        return true;
    }

    /// Ensures the template cache is up to date.
    /// If forceful is false, only updates if 24 hours have passed since last update.
    bool updateCache(bool forceful = false)
    {
        auto metadataPath = buildPath(cacheRoot, "metadata.json");
        bool needsUpdate = forceful;

        if (!needsUpdate && exists(metadataPath))
        {
            try
            {
                auto content = readText(metadataPath);
                auto json = parseJSON(content);
                auto lastUpdatedStr = json["lastUpdated"].str;
                auto lastUpdated = SysTime.fromISOExtString(lastUpdatedStr);
                
                if (Clock.currTime() - lastUpdated > hours(24))
                {
                    needsUpdate = true;
                }
            }
            catch (Exception)
            {
                needsUpdate = true;
            }
        }
        else if (!exists(metadataPath))
        {
            needsUpdate = true;
        }

        if (needsUpdate)
        {
            return performSync();
        }
        return false;
    }

    private bool performSync()
    {
        auto repoPath = buildPath(cacheRoot, "repo");
        if (!exists(repoPath))
        {
            mkdirRecurse(cacheRoot);
            auto result = execute(["git", "clone", templatesRepoUrl, repoPath]);
            if (result.status != 0) return false;
        }
        else
        {
            auto result = execute(["git", "-C", repoPath, "pull"]);
            if (result.status != 0) return false;
        }

        // Save metadata
        JSONValue metadata;
        metadata["lastUpdated"] = JSONValue(Clock.currTime().toISOExtString());
        metadata["remoteUrl"] = JSONValue(templatesRepoUrl);
        write(buildPath(cacheRoot, "metadata.json"), metadata.toString());
        
        return true;
    }

    /// Discovers templates in the cache.
    TemplateInfo[] listTemplates()
    {
        auto workspacesPath = buildPath(cacheRoot, "repo", "workspaces");
        if (!exists(workspacesPath)) return [];

        TemplateInfo[] templates;
        foreach (entry; dirEntries(workspacesPath, SpanMode.shallow))
        {
            if (entry.isDir && baseName(entry.name)[0] != '.')
            {
                TemplateInfo info;
                info.id = baseName(entry.name);
                info.name = info.id; // Fallback
                info.path = entry.name;
                
                // Try to read more info from README.adoc or a possible manifest
                auto readmePath = buildPath(entry.name, "README.adoc");
                if (exists(readmePath))
                {
                    // Basic parsing of AsciiDoc header
                    auto content = readText(readmePath);
                    // (Simplistic parsing for now)
                    if (content.canFind(":description:")) {
                        // Extract description...
                    }
                }
                
                templates ~= info;
            }
        }
        return templates;
    }

    /// Lists files within a template for review.
    string[] getTemplateFiles(string templateId)
    {
        auto templatePath = buildPath(cacheRoot, "repo", "workspaces", templateId);
        if (!exists(templatePath)) return [];

        string[] files;
        foreach (entry; dirEntries(templatePath, SpanMode.depth))
        {
            if (!entry.isDir)
            {
                files ~= relativePath(entry.name, templatePath);
            }
        }
        return files;
    }

    /// Installs a template into a project.
    void install(string templateId, string projectPath)
    {
        auto templatePath = buildPath(cacheRoot, "repo", "workspaces", templateId);
        enforce(exists(templatePath), "Template " ~ templateId ~ " not found.");
        
        auto absoluteProject = absolutePath(projectPath);
        if (!exists(absoluteProject)) mkdirRecurse(absoluteProject);

        foreach (entry; dirEntries(templatePath, SpanMode.depth))
        {
            auto relPath = relativePath(entry.name, templatePath);
            auto destPath = buildPath(absoluteProject, relPath);

            if (entry.isDir)
            {
                if (!exists(destPath)) mkdirRecurse(destPath);
            }
            else
            {
                // Special handling for .code-workspace files?
                // For now, just copy. 
                // TODO: Merging logic for .code-workspace
                auto destDir = dirName(destPath);
                if (!exists(destDir)) mkdirRecurse(destDir);
                copy(entry.name, destPath);
            }
        }

        recordInstallation(templateId, absoluteProject);
    }

    private void recordInstallation(string templateId, string projectPath)
    {
        auto configDir = buildPath(projectPath, ".dev-center");
        if (!exists(configDir)) mkdirRecurse(configDir);
        
        auto installedPath = buildPath(configDir, "installed-templates.json");
        JSONValue installed;
        if (exists(installedPath))
        {
            installed = parseJSON(readText(installedPath));
        }
        else
        {
            installed = parseJSON("{}");
            installed["templates"] = JSONValue(string[].init);
        }

        bool alreadyInstalled = false;
        foreach (val; installed["templates"].array)
        {
            if (val.str == templateId)
            {
                alreadyInstalled = true;
                break;
            }
        }

        if (!alreadyInstalled)
        {
            installed["templates"].array ~= JSONValue(templateId);
            write(installedPath, installed.toString());
        }
    }
}
