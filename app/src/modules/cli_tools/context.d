module modules.cli_tools.context;

import modules.cli_tools.model;
import std.process : spawnProcess, tryWait, kill, wait;
import std.stdio : File;
import std.algorithm : canFind;
import core.thread : Thread;
import core.time : msecs, Duration;
import std.datetime.stopwatch : StopWatch, AutoStart;

version (Windows)
    private enum nullDevice = "NUL";
else
    private enum nullDevice = "/dev/null";

/// Time budget for a single host-context probe. Probes run on the UI thread at
/// startup, so a command that never returns (e.g. `npx <pkg>` fetching an
/// uninstalled package) must not be allowed to block the app indefinitely.
private enum Duration detectTimeout = 4000.msecs;

private bool detectCommandWorks(string detectCmd) {
    if (detectCmd.length == 0) return false;

    string[] args;
    version (Windows)
        args = ["cmd", "/c", detectCmd];
    else
        args = ["sh", "-c", detectCmd];

    try {
        // Null stdin keeps interactive prompts (e.g. npx's install confirmation)
        // from stalling the probe; null stdout/stderr discards probe output.
        auto devNullIn = File(nullDevice, "r");
        auto devNullOut = File(nullDevice, "w");
        auto pid = spawnProcess(args, devNullIn, devNullOut, devNullOut);

        auto sw = StopWatch(AutoStart.yes);
        while (true) {
            auto res = tryWait(pid);
            if (res.terminated)
                return res.status == 0;
            if (sw.peek() > detectTimeout) {
                kill(pid);
                wait(pid);
                return false;
            }
            Thread.sleep(50.msecs);
        }
    } catch (Exception) {
        return false;
    }
}

/// Pick the best host context for install resolution (immutable contexts first when preferImmutable).
string detectHostContext(const ref CliToolsCatalog catalog, bool preferImmutable = true) {
    CliToolContext[] matches;
    foreach (c; catalog.contexts) {
        if (c.detect.length == 0) continue;
        if (!detectCommandWorks(c.detect)) continue;
        matches ~= c;
    }

    if (matches.length == 0) {
        foreach (c; catalog.contexts)
            if (c.id == "default/npm-global" && detectCommandWorks("which npm"))
                return c.id;
        return "default/curl-script";
    }

    if (preferImmutable) {
        foreach (c; matches)
            if (!c.mutableInstall) return c.id;
    }

    string[] priority = [
        "windows/winget", "windows/scoop", "macos/homebrew",
        "linux/debian/default", "linux/fedora/default", "linux/arch/default",
        "linux/alpine/default", "linux/homebrew",
    ];
    foreach (pid; priority)
        foreach (c; matches)
            if (c.id == pid) return c.id;

    return matches[0].id;
}

string contextLabel(const ref CliToolsCatalog catalog, string contextId) {
    foreach (c; catalog.contexts)
        if (c.id == contextId) return c.label.length ? c.label : c.id;
    return contextId;
}
