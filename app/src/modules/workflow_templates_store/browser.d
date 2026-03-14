module modules.workflow_templates_store.browser;

import std.process;
import std.path : buildPath;
import std.file : exists, readText;
import std.string : strip;

/// Default URL for the workflow templates store. Replace when the site is live.
enum defaultStoreURL = "https://workflow-templates.devcentr.org";

string getHomeDir()
{
    version (Windows)
    {
        string drive = environment.get("HOMEDRIVE");
        string path = environment.get("HOMEPATH");
        return drive.length && path.length ? buildPath(drive, path) : environment.get("USERPROFILE");
    }
    else
        return environment.get("HOME");
}

/// Returns the URL to open. Reads from .dev-center/workflow-templates-url if present.
string getWorkflowTemplatesStoreURL()
{
    string home = getHomeDir();
    string configPath = buildPath(home, ".dev-center", "workflow-templates-url");
    if (exists(configPath))
    {
        string content = readText(configPath).strip();
        if (content.length > 0)
            return content;
    }
    return defaultStoreURL;
}

/// Opens the workflow templates store in the user's default browser.
/// Returns true if the open command was run (no guarantee the browser actually opened).
bool openWorkflowTemplatesStore()
{
    string url = getWorkflowTemplatesStoreURL();
    version (Windows)
    {
        return spawnProcess("cmd", ["/c", "start", "\"\"", url]).wait() == 0;
    }
    else version (Posix)
    {
        version (OSX)
            return spawnProcess("open", [url]).wait() == 0;
        else
            return spawnProcess("xdg-open", [url]).wait() == 0;
    }
    else
        return false;
}
