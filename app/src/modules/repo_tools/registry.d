module modules.repo_tools.registry;

import std.datetime : SysTime, Clock;
import std.path : buildPath;
import std.file : exists, isDir;
import std.json : JSONValue, parseJSON, JSONType;
import std.file : readText, write;
import std.exception : collectException;

enum ToolKind
{
    builtinModule,
    externalApp,
}

struct ToolInstance
{
    string id;
    string repoRoot;
    ToolKind kind;
    string label;
    string icon;
    int pid;
    string executable;
    SysTime startedAt;
    SysTime lastSeenAliveAt;
}

/// Simple in-memory registry with JSON5-compatible persistence.
class RepoToolsRegistry
{
    private ToolInstance[] instances;
    private string storePath;

    this(string dataRoot)
    {
        storePath = buildPath(dataRoot, "repo-tools-registry.json5");
        load();
    }

    ToolInstance[] instancesForRepo(string repoRoot) const
    {
        ToolInstance[] result;
        foreach (inst; instances)
        {
            if (inst.repoRoot == repoRoot)
            {
                result ~= inst;
            }
        }
        return result;
    }

    void registerOrUpdateInstance(ToolInstance instance)
    {
        bool updated;
        foreach (ref existing; instances)
        {
            if (existing.id == instance.id)
            {
                existing = instance;
                updated = true;
                break;
            }
        }
        if (!updated)
        {
            instances ~= instance;
        }
        save();
    }

    void removeInstance(string id)
    {
        ToolInstance[] result;
        foreach (inst; instances)
        {
            if (inst.id != id)
            {
                result ~= inst;
            }
        }
        instances = result;
        save();
    }

    /// Background hook point: reconcile instances with live processes.
    void reconcileWithProcesses()
    {
        // Placeholder implementation. A future revision can:
        // * Enumerate processes.
        // * Drop instances whose pids no longer exist.
        // * Update lastSeenAliveAt for running processes.
    }

    /// Background hook point: discover external tools with open handles under known repos.
    void discoverExternalTools(string[] repoRoots)
    {
        import modules.repo_tools.handle_discovery : discoverExternalToolsForRoots;
        discoverExternalToolsForRoots(this, repoRoots);
    }

private:
    void load()
    {
        if (!exists(storePath))
        {
            instances = [];
            return;
        }

        auto ex = collectException({
            auto text = readText(storePath);
            auto json = parseJSON(text);
            if (json.type != JSONType.array)
            {
                instances = [];
                return;
            }
            ToolInstance[] loaded;
            foreach (item; json.array)
            {
                if (item.type != JSONType.object)
                {
                    continue;
                }
                ToolInstance inst;
                inst.id = item["id"].str;
                inst.repoRoot = item["repoRoot"].str;
                inst.kind = item["kind"].str == "builtinModule" ? ToolKind.builtinModule : ToolKind.externalApp;
                inst.label = item["label"].str;
                inst.icon = item.get("icon", JSONValue("")).str;
                inst.pid = item.get("pid", JSONValue(0)).integer;
                inst.executable = item.get("executable", JSONValue("")).str;
                loaded ~= inst;
            }
            instances = loaded;
        });
        if (ex)
        {
            instances = [];
        }
    }

    void save()
    {
        JSONValue[] arr;
        foreach (inst; instances)
        {
            JSONValue obj;
            obj["id"] = JSONValue(inst.id);
            obj["repoRoot"] = JSONValue(inst.repoRoot);
            obj["kind"] = JSONValue(inst.kind == ToolKind.builtinModule ? "builtinModule" : "externalApp");
            obj["label"] = JSONValue(inst.label);
            obj["icon"] = JSONValue(inst.icon);
            obj["pid"] = JSONValue(inst.pid);
            obj["executable"] = JSONValue(inst.executable);
            arr ~= obj;
        }
        JSONValue root = JSONValue(arr);
        auto text = root.toString();
        write(storePath, text);
    }
}

