module modules.workflow_templates_store.store;

import std.process : pipeProcess, wait;
import std.path : buildPath;
import std.file : exists, mkdirRecurse, write;
import std.json : JSONValue, parseJSON, JSONType;
import std.array : array;
import modules.workflow_templates_store.browser : getWorkflowTemplatesStoreURL;

/// One workflow template from the API list.
struct WorkflowTemplateRef
{
    string id;
    string name;
    string source;
}

/// Full template with content for install.
struct WorkflowTemplateContent
{
    string id;
    string name;
    string filename;  /// e.g. "docs.yml"
    string content;   /// YAML body
}

/// Fetch URL body via curl. Returns empty string on failure.
string fetchUrl(string url)
{
    try
    {
        auto p = pipeProcess(["curl", "-sL", url]);
        scope (exit) wait(p.pid);
        string result;
        foreach (line; p.stdout.byLine())
            result ~= line.idup ~ "\n";
        return result;
    }
    catch (Exception)
    {
        return "";
    }
}

/// Parse list from GET /api/templates JSON.
WorkflowTemplateRef[] fetchTemplatesList(string baseUrl)
{
    string url = baseUrl ~ (baseUrl.endsWith("/") ? "" : "/") ~ "api/templates";
    string body = fetchUrl(url);
    if (body.length == 0)
        return [];

    try
    {
        auto json = parseJSON(body);
        if (json.type != JSONType.array)
            return [];
        WorkflowTemplateRef[] list;
        foreach (item; json.array)
        {
            WorkflowTemplateRef r;
            r.id = item["id"].str;
            r.name = item["name"].str;
            r.source = item["source"].str;
            list ~= r;
        }
        return list;
    }
    catch (Exception)
    {
        return [];
    }
}

/// Parse content from GET /api/templates/{id} JSON. Returns null if missing/failed.
WorkflowTemplateContent* fetchTemplateContent(string baseUrl, string id)
{
    string url = baseUrl ~ (baseUrl.endsWith("/") ? "" : "/") ~ "api/templates/" ~ id;
    string body = fetchUrl(url);
    if (body.length == 0)
        return null;

    try
    {
        auto json = parseJSON(body);
        auto c = new WorkflowTemplateContent;
        c.id = json["id"].str;
        c.name = json["name"].str;
        c.filename = json["filename"].str;
        c.content = json["content"].str;
        return c;
    }
    catch (Exception)
    {
        return null;
    }
}

/// Install workflow YAML into repo. Creates .github/workflows if needed.
/// repoRoot: path to repo root (e.g. getcwd()).
/// filename: e.g. "docs.yml"
/// content: full YAML.
/// Returns (true, "") on success, (false, errorMessage) on failure.
bool installTemplateIntoRepo(string repoRoot, string filename, string content, ref string errMsg)
{
    errMsg = "";
    string dir = buildPath(repoRoot, ".github", "workflows");
    try
    {
        if (!exists(dir))
            mkdirRecurse(dir);
        string path = buildPath(dir, filename);
        write(path, content);
        return true;
    }
    catch (Exception e)
    {
        errMsg = e.msg;
        return false;
    }
}
