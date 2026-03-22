module modules.services.ai_client_profiles;

import std.path : buildPath;
import std.process : execute, environment;
import std.string : replace, indexOf;

struct AIClientProfile
{
    string id;
    string displayName;
    string category;
    string launchCommand;
    string context7DocsUrl;
    string context7ConfigUrl;
    string sourcePlainUrl;
    string sourceRawUrl;
    string[] userConfigFiles;
    string[] projectConfigFiles;
    bool easySetupSupported;
    string easySetupCommand;
    bool easySetupProvisionsApiKey;
    bool easySetupInstallsSkill;
    string manualConfigDocsUrl;
    string manualConfigStrategy;
    bool apiKeyRequired;
    string[] skillNotes;
}

enum context7SkillsBrowserUrl = "https://context7.com/skills/";
enum context7AllClientsDocsUrl = "https://context7.com/docs/resources/all-clients";
enum context7AllClientsSourceRawUrl = "https://raw.githubusercontent.com/upstash/context7/refs/heads/master/docs/resources/all-clients.mdx";
enum context7AllClientsSourcePlainUrl = "https://github.com/upstash/context7/blob/master/docs/resources/all-clients.mdx?plain=1";
enum context7IssueSearchUrl = "https://github.com/upstash/context7/issues?q=is%3Aissue%20state%3Aopen";
enum context7IssueChooserUrl = "https://github.com/upstash/context7/issues/new/choose";
enum context7ContributingGuidelinesUrl = "https://opensource.guide/";

private string[] arr(string[] values...)
{
    return values.dup;
}

static immutable AIClientProfile[] KNOWN_AI_CLIENTS = [
    AIClientProfile(
        "cursor",
        "Cursor",
        "editor",
        "cursor",
        "https://context7.com/docs/clients/cursor",
        "https://context7.com/docs/resources/all-clients#cursor",
        context7AllClientsSourcePlainUrl,
        context7AllClientsSourceRawUrl,
        arr("~/.cursor/mcp.json"),
        arr(".cursor/mcp.json"),
        true,
        "npx ctx7 setup --cursor",
        true,
        true,
        "https://docs.cursor.com/context/model-context-protocol",
        "json-file",
        true,
        arr(
            "Context7 setup command can install the skill automatically.",
            "Cursor rules can force Context7 use for library docs and API requests."
        )
    ),
    AIClientProfile(
        "claude-code",
        "Claude Code",
        "coding-agent-cli",
        "claude",
        "https://context7.com/docs/clients/claude-code",
        "https://context7.com/docs/resources/all-clients#claude-code",
        context7AllClientsSourcePlainUrl,
        context7AllClientsSourceRawUrl,
        arr(),
        arr(),
        true,
        "npx ctx7 setup --claude",
        true,
        true,
        "https://docs.anthropic.com/en/docs/claude-code/mcp",
        "command-or-remote-http",
        true,
        arr(
            "Context7 plugin can add skills, agents, and commands.",
            "Plugin commands: /plugin marketplace add upstash/context7 and /plugin install context7-plugin@context7-marketplace"
        )
    ),
    AIClientProfile(
        "opencode",
        "OpenCode",
        "coding-agent-cli",
        "opencode",
        "https://context7.com/docs/clients/opencode",
        "https://context7.com/docs/resources/all-clients#opencode",
        context7AllClientsSourcePlainUrl,
        context7AllClientsSourceRawUrl,
        arr(),
        arr("opencode.json"),
        true,
        "npx ctx7 setup --opencode",
        true,
        true,
        "https://opencode.ai/docs/mcp-servers/",
        "json-file",
        true,
        arr("You can also add Context7 usage instructions to AGENTS.md.")
    ),
    AIClientProfile(
        "vs-code",
        "VS Code",
        "editor",
        "code",
        "https://context7.com/docs/resources/all-clients#vs-code",
        "https://context7.com/docs/resources/all-clients#vs-code",
        context7AllClientsSourcePlainUrl,
        context7AllClientsSourceRawUrl,
        arr("VS Code MCP config file"),
        arr(),
        false,
        "",
        false,
        false,
        "https://code.visualstudio.com/docs/copilot/chat/mcp-servers",
        "json-file",
        true,
        arr("VS Code MCP setup is manual unless a deeplink/install flow is used.")
    ),
    AIClientProfile(
        "windsurf",
        "Windsurf",
        "editor",
        "windsurf",
        "https://context7.com/docs/resources/all-clients#windsurf",
        "https://context7.com/docs/resources/all-clients#windsurf",
        context7AllClientsSourcePlainUrl,
        context7AllClientsSourceRawUrl,
        arr("Windsurf MCP config file"),
        arr(),
        false,
        "",
        false,
        false,
        "https://docs.windsurf.com/windsurf/cascade/mcp",
        "json-file",
        true,
        arr()
    ),
    AIClientProfile(
        "claude-desktop",
        "Claude Desktop",
        "desktop-ai-client",
        "claude",
        "https://context7.com/docs/resources/all-clients#claude-desktop",
        "https://context7.com/docs/resources/all-clients#claude-desktop",
        context7AllClientsSourcePlainUrl,
        context7AllClientsSourceRawUrl,
        arr("claude_desktop_config.json"),
        arr(),
        false,
        "",
        false,
        false,
        "https://modelcontextprotocol.io/quickstart/user",
        "ui-or-json-file",
        true,
        arr()
    ),
    AIClientProfile(
        "gemini-cli",
        "Gemini CLI",
        "coding-agent-cli",
        "gemini",
        "https://context7.com/docs/resources/all-clients#gemini-cli",
        "https://context7.com/docs/resources/all-clients#gemini-cli",
        context7AllClientsSourcePlainUrl,
        context7AllClientsSourceRawUrl,
        arr("~/.gemini/settings.json"),
        arr(),
        false,
        "",
        false,
        false,
        "https://google-gemini.github.io/gemini-cli/docs/tools/mcp-server.html",
        "json-file",
        true,
        arr("Gemini CLI requires an Accept header for the remote MCP example.")
    ),
    AIClientProfile(
        "github-copilot",
        "GitHub Copilot",
        "coding-agent-cli",
        "copilot",
        "https://context7.com/docs/resources/all-clients#github-copilot",
        "https://context7.com/docs/resources/all-clients#github-copilot",
        context7AllClientsSourcePlainUrl,
        context7AllClientsSourceRawUrl,
        arr("~/.copilot/mcp-config.json"),
        arr("Repository Settings -> Copilot -> Coding agent -> MCP configuration"),
        false,
        "",
        false,
        false,
        "https://docs.github.com/en/enterprise-cloud@latest/copilot/how-tos/agents/copilot-coding-agent/extending-copilot-coding-agent-with-mcp",
        "json-file-or-repo-settings",
        true,
        arr("GitHub Copilot also supports repo-level MCP configuration in repository settings.")
    ),
    AIClientProfile(
        "zed",
        "Zed",
        "editor",
        "zed",
        "https://context7.com/docs/resources/all-clients#zed",
        "https://context7.com/docs/resources/all-clients#zed",
        context7AllClientsSourcePlainUrl,
        context7AllClientsSourceRawUrl,
        arr("Zed settings.json"),
        arr(),
        false,
        "",
        false,
        false,
        "https://zed.dev/docs/assistant/context-servers",
        "json-file",
        true,
        arr("Zed may also offer a Context7 extension path.")
    ),
    AIClientProfile(
        "qwen-code",
        "Qwen Code",
        "coding-agent-cli",
        "qwen",
        "https://context7.com/docs/resources/all-clients#qwen-code",
        "https://context7.com/docs/resources/all-clients#qwen-code",
        context7AllClientsSourcePlainUrl,
        context7AllClientsSourceRawUrl,
        arr("~/.qwen/settings.json"),
        arr(".qwen/settings.json"),
        false,
        "",
        false,
        false,
        "https://qwenlm.github.io/qwen-code-docs/en/users/features/mcp/",
        "cli-or-json-file",
        true,
        arr("Qwen Code supports a CLI `mcp add` flow in addition to JSON config.")
    ),
    AIClientProfile(
        "google-antigravity",
        "Google Antigravity",
        "editor",
        "antigravity",
        "https://context7.com/docs/resources/all-clients#google-antigravity",
        "https://context7.com/docs/resources/all-clients#google-antigravity",
        context7AllClientsSourcePlainUrl,
        context7AllClientsSourceRawUrl,
        arr("Antigravity MCP config file"),
        arr(),
        false,
        "",
        false,
        false,
        "https://antigravity.google/docs/mcp",
        "json-file",
        true,
        arr()
    ),
];

const(AIClientProfile)[] getKnownAIClients()
{
    return KNOWN_AI_CLIENTS;
}

AIClientProfile getAIClientProfile(string id)
{
    foreach (client; KNOWN_AI_CLIENTS)
    {
        if (client.id == id)
            return AIClientProfile(
                client.id, client.displayName, client.category, client.launchCommand,
                client.context7DocsUrl, client.context7ConfigUrl, client.sourcePlainUrl, client.sourceRawUrl,
                client.userConfigFiles.dup, client.projectConfigFiles.dup,
                client.easySetupSupported, client.easySetupCommand,
                client.easySetupProvisionsApiKey, client.easySetupInstallsSkill,
                client.manualConfigDocsUrl, client.manualConfigStrategy, client.apiKeyRequired,
                client.skillNotes.dup
            );
    }
    return AIClientProfile.init;
}

bool isClientInstalled(AIClientProfile client)
{
    if (client.launchCommand.length == 0)
        return false;
    version (Windows)
        enum probe = "where";
    else
        enum probe = "which";
    try
    {
        auto result = execute([probe, client.launchCommand]);
        return result.status == 0 && result.output.length > 0;
    }
    catch (Exception)
    {
        return false;
    }
}

string expandClientPath(string pathValue, string repoRoot = "")
{
    if (pathValue.length == 0)
        return "";
    if (pathValue.length >= 2 && pathValue[0 .. 2] == "~/")
    {
        version (Windows)
            return buildPath(getHomeDir(), pathValue[2 .. $].replace("/", "\\"));
        else
            return buildPath(getHomeDir(), pathValue[2 .. $]);
    }
    if (pathValue.length > 0 && pathValue[0] == '.')
    {
        if (repoRoot.length == 0)
            return "";
        version (Windows)
            return buildPath(repoRoot, pathValue.replace("/", "\\"));
        else
            return buildPath(repoRoot, pathValue);
    }
    if (pathValue.indexOf("->") >= 0 || pathValue.indexOf("config file") >= 0 || pathValue.indexOf("Settings") >= 0)
        return "";
    return pathValue;
}

string resolvePreferredConfigPath(const AIClientProfile client, string repoRoot = "")
{
    foreach (pathValue; client.userConfigFiles)
    {
        auto expanded = expandClientPath(pathValue, repoRoot);
        if (expanded.length > 0)
            return expanded;
    }
    foreach (pathValue; client.projectConfigFiles)
    {
        auto expanded = expandClientPath(pathValue, repoRoot);
        if (expanded.length > 0)
            return expanded;
    }
    return "";
}

string defaultManualCommand(const AIClientProfile client, string apiKey)
{
    string key = apiKey.length > 0 ? apiKey : "YOUR_API_KEY";
    final switch (client.id)
    {
        case "cursor":
        case "vs-code":
        case "windsurf":
        case "claude-desktop":
        case "zed":
        case "google-antigravity":
            return "npx -y @upstash/context7-mcp --api-key " ~ key;
        case "claude-code":
            return "claude mcp add --scope user context7 -- npx -y @upstash/context7-mcp --api-key " ~ key;
        case "opencode":
            return "npx -y @upstash/context7-mcp --api-key " ~ key;
        case "gemini-cli":
            return "npx -y @upstash/context7-mcp --api-key " ~ key;
        case "github-copilot":
            return "npx -y @upstash/context7-mcp --api-key " ~ key;
        case "qwen-code":
            return "qwen mcp add context7 npx -y @upstash/context7-mcp --api-key " ~ key;
    }
    return "";
}

string makeContext7Snippet(const AIClientProfile client, string apiKey, bool remote = true)
{
    string key = apiKey.length > 0 ? apiKey : "YOUR_API_KEY";
    final switch (client.id)
    {
        case "cursor":
            return remote
                ? "{\n  \"mcpServers\": {\n    \"context7\": {\n      \"url\": \"https://mcp.context7.com/mcp\",\n      \"headers\": {\n        \"CONTEXT7_API_KEY\": \"" ~ key ~ "\"\n      }\n    }\n  }\n}\n"
                : "{\n  \"mcpServers\": {\n    \"context7\": {\n      \"command\": \"npx\",\n      \"args\": [\"-y\", \"@upstash/context7-mcp\", \"--api-key\", \"" ~ key ~ "\"]\n    }\n  }\n}\n";
        case "vs-code":
            return remote
                ? "{\n  \"mcp\": {\n    \"servers\": {\n      \"context7\": {\n        \"type\": \"http\",\n        \"url\": \"https://mcp.context7.com/mcp\",\n        \"headers\": {\n          \"CONTEXT7_API_KEY\": \"" ~ key ~ "\"\n        }\n      }\n    }\n  }\n}\n"
                : "{\n  \"mcp\": {\n    \"servers\": {\n      \"context7\": {\n        \"type\": \"stdio\",\n        \"command\": \"npx\",\n        \"args\": [\"-y\", \"@upstash/context7-mcp\", \"--api-key\", \"" ~ key ~ "\"]\n      }\n    }\n  }\n}\n";
        case "windsurf":
        case "google-antigravity":
            return remote
                ? "{\n  \"mcpServers\": {\n    \"context7\": {\n      \"serverUrl\": \"https://mcp.context7.com/mcp\",\n      \"headers\": {\n        \"CONTEXT7_API_KEY\": \"" ~ key ~ "\"\n      }\n    }\n  }\n}\n"
                : "{\n  \"mcpServers\": {\n    \"context7\": {\n      \"command\": \"npx\",\n      \"args\": [\"-y\", \"@upstash/context7-mcp\", \"--api-key\", \"" ~ key ~ "\"]\n    }\n  }\n}\n";
        case "claude-code":
            return remote
                ? "claude mcp add --scope user --header \"CONTEXT7_API_KEY: " ~ key ~ "\" --transport http context7 https://mcp.context7.com/mcp\n"
                : "claude mcp add --scope user context7 -- npx -y @upstash/context7-mcp --api-key " ~ key ~ "\n";
        case "opencode":
            return remote
                ? "{\n  \"mcp\": {\n    \"context7\": {\n      \"type\": \"remote\",\n      \"url\": \"https://mcp.context7.com/mcp\",\n      \"headers\": {\n        \"CONTEXT7_API_KEY\": \"" ~ key ~ "\"\n      },\n      \"enabled\": true\n    }\n  }\n}\n"
                : "{\n  \"mcp\": {\n    \"context7\": {\n      \"type\": \"local\",\n      \"command\": [\"npx\", \"-y\", \"@upstash/context7-mcp\", \"--api-key\", \"" ~ key ~ "\"],\n      \"enabled\": true\n    }\n  }\n}\n";
        case "claude-desktop":
            return "{\n  \"mcpServers\": {\n    \"context7\": {\n      \"command\": \"npx\",\n      \"args\": [\"-y\", \"@upstash/context7-mcp\", \"--api-key\", \"" ~ key ~ "\"]\n    }\n  }\n}\n";
        case "gemini-cli":
            return remote
                ? "{\n  \"mcpServers\": {\n    \"context7\": {\n      \"httpUrl\": \"https://mcp.context7.com/mcp\",\n      \"headers\": {\n        \"CONTEXT7_API_KEY\": \"" ~ key ~ "\",\n        \"Accept\": \"application/json, text/event-stream\"\n      }\n    }\n  }\n}\n"
                : "{\n  \"mcpServers\": {\n    \"context7\": {\n      \"command\": \"npx\",\n      \"args\": [\"-y\", \"@upstash/context7-mcp\", \"--api-key\", \"" ~ key ~ "\"]\n    }\n  }\n}\n";
        case "github-copilot":
            return remote
                ? "{\n  \"mcpServers\": {\n    \"context7\": {\n      \"type\": \"http\",\n      \"url\": \"https://mcp.context7.com/mcp\",\n      \"headers\": {\n        \"CONTEXT7_API_KEY\": \"" ~ key ~ "\"\n      },\n      \"tools\": [\"query-docs\", \"resolve-library-id\"]\n    }\n  }\n}\n"
                : "{\n  \"mcpServers\": {\n    \"context7\": {\n      \"type\": \"local\",\n      \"command\": \"npx\",\n      \"tools\": [\"query-docs\", \"resolve-library-id\"],\n      \"args\": [\"-y\", \"@upstash/context7-mcp\", \"--api-key\", \"" ~ key ~ "\"]\n    }\n  }\n}\n";
        case "zed":
            return "{\n  \"context_servers\": {\n    \"Context7\": {\n      \"source\": \"custom\",\n      \"command\": \"npx\",\n      \"args\": [\"-y\", \"@upstash/context7-mcp\", \"--api-key\", \"" ~ key ~ "\"]\n    }\n  }\n}\n";
        case "qwen-code":
            return remote
                ? "{\n  \"mcpServers\": {\n    \"context7\": {\n      \"httpUrl\": \"https://mcp.context7.com/mcp\",\n      \"headers\": {\n        \"CONTEXT7_API_KEY\": \"" ~ key ~ "\",\n        \"Accept\": \"application/json, text/event-stream\"\n      }\n    }\n  }\n}\n"
                : "{\n  \"mcpServers\": {\n    \"context7\": {\n      \"command\": \"npx\",\n      \"args\": [\"-y\", \"@upstash/context7-mcp\", \"--api-key\", \"" ~ key ~ "\"]\n    }\n  }\n}\n";
    }
    return "";
}

private string getHomeDir()
{
    version (Windows)
    {
        string drive = environment.get("HOMEDRIVE");
        string path = environment.get("HOMEPATH");
        if (drive && path)
            return buildPath(drive, path);
        return environment.get("USERPROFILE");
    }
    else
    {
        return environment.get("HOME");
    }
}
