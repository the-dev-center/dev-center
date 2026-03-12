module app.src.modules.repo_tools.handle_discovery;

import modules.repo_tools.registry;
import std.conv : to;
import std.string : toLower, strip;
import std.algorithm : canFind, splitter;
import std.array : array;
import std.path : baseName;
import std.datetime : Clock;

/// Per-platform discovery of external applications that have files open
/// inside repositories.  On Windows, we use `handle.exe` from Sysinternals
/// or PowerShell `Get-Process`; on Linux/macOS, `lsof`.
///
/// This is intentionally best-effort: if the required tools are missing
/// or the user lacks permissions, the function silently returns without
/// modifying the registry.

void discoverExternalToolsForRoots(RepoToolsRegistry registry, string[] repoRoots)
{
    version (Windows)
    {
        discoverWindows(registry, repoRoots);
    }
    else version (linux)
    {
        discoverLinux(registry, repoRoots);
    }
    else version (OSX)
    {
        discoverLinux(registry, repoRoots); // lsof works on macOS too
    }
}

// ---------------------------------------------------------------------------
// Windows: Use PowerShell to enumerate processes that have modules loaded
// from files under any of the repo roots.  This approach doesn't need
// Sysinternals and works on stock Windows 10/11.
// ---------------------------------------------------------------------------
private void discoverWindows(RepoToolsRegistry registry, string[] repoRoots)
{
    import std.process : pipeProcess, Redirect;

    // Build a PowerShell one-liner that checks each process's main module path.
    // For each match, emit "PID|ProcessName|MainModulePath".
    // We compare against repo roots to find processes with working dirs or
    // executables under a known repo.
    //
    // Limitation: this finds processes whose executable lives under a repo,
    // not processes that have arbitrary file handles open.  Full handle
    // enumeration requires the Sysinternals `handle64.exe` tool.

    string psScript =
        "Get-Process | ForEach-Object { " ~
        "  try { " ~
        "    $p = $_; $m = $p.MainModule.FileName; " ~
        "    if ($m) { Write-Output ('{0}|{1}|{2}' -f $p.Id, $p.ProcessName, $m) } " ~
        "  } catch {} " ~
        "}";

    try
    {
        auto pipes = pipeProcess(
            ["powershell", "-NoProfile", "-Command", psScript],
            Redirect.stdout | Redirect.stderr);

        foreach (rawLine; pipes.stdout.byLine)
        {
            string line = rawLine.idup.strip();
            if (line.length == 0)
                continue;

            auto parts = line.splitter('|').array;
            if (parts.length < 3)
                continue;

            int pid;
            try { pid = to!int(parts[0]); } catch (Exception) { continue; }
            string procName = parts[1];
            string exePath = parts[2];

            string exeLower = exePath.toLower();

            // Check if this process's executable lives under any known repo.
            foreach (root; repoRoots)
            {
                if (exeLower.canFind(root.toLower()))
                {
                    string id = procName ~ "-" ~ to!string(pid);
                    ToolInstance inst;
                    inst.id = id;
                    inst.repoRoot = root;
                    inst.kind = ToolKind.externalApp;
                    inst.label = procName;
                    inst.icon = "";
                    inst.pid = pid;
                    inst.executable = exePath;
                    inst.startedAt = Clock.currTime;
                    inst.lastSeenAliveAt = Clock.currTime;
                    registry.registerOrUpdateInstance(inst);
                    break;
                }
            }
        }

        pipes.pid.wait();
    }
    catch (Exception)
    {
        // Silently ignore — user may not have PowerShell available (unlikely)
    }
}

// ---------------------------------------------------------------------------
// Linux / macOS: Use `lsof` to find open files under repo roots.
// ---------------------------------------------------------------------------
private void discoverLinux(RepoToolsRegistry registry, string[] repoRoots)
{
    import std.process : pipeProcess, Redirect;

    foreach (root; repoRoots)
    {
        try
        {
            auto pipes = pipeProcess(
                ["lsof", "+D", root, "-t"],
                Redirect.stdout | Redirect.stderr);

            foreach (rawLine; pipes.stdout.byLine)
            {
                string line = rawLine.idup.strip();
                if (line.length == 0)
                    continue;

                int pid;
                try { pid = to!int(line); } catch (Exception) { continue; }

                string id = "lsof-" ~ to!string(pid);
                ToolInstance inst;
                inst.id = id;
                inst.repoRoot = root;
                inst.kind = ToolKind.externalApp;
                inst.label = "PID " ~ to!string(pid);
                inst.icon = "";
                inst.pid = pid;
                inst.executable = "";
                inst.startedAt = Clock.currTime;
                inst.lastSeenAliveAt = Clock.currTime;
                registry.registerOrUpdateInstance(inst);
            }

            pipes.pid.wait();
        }
        catch (Exception)
        {
            // lsof not installed or permissions insufficient — skip
        }
    }
}
