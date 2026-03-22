module modules.services.ai_config_dialog;

import dlangui;
import dlangui.dialogs.dialog : Dialog, DialogFlag;
import dlangui.widgets.styles : Align;
import dlangui.graphics.fonts : FontFamily;
import modules.infra.logging : logInfo, logWarning;
import modules.infra.ui : openUrlInBrowser;
import modules.repo_tools.editor_detector : detectInstalledEditors, openPathWithEditor, EditorProfile;
import modules.services.ai_providers : KNOWN_PROVIDERS, getProviderKey, saveProviderKey;
import modules.services.ai_client_profiles;
import std.algorithm : min;
import std.array : split;
import std.conv : to;
import std.file : exists, readText, write, mkdirRecurse;
import std.net.curl : get;
import std.path : buildPath, dirName;
import std.process : spawnProcess, environment;
import std.string : splitLines, strip;

private string fetchTextOrEmpty(string url)
{
    try
    {
        return cast(string)get(url);
    }
    catch (Exception)
    {
        return "";
    }
}

private bool runCommandInExternalTerminal(string command, string workingDir = "")
{
    version (Windows)
    {
        string wrapped = command;
        if (workingDir.length > 0)
            wrapped = "Set-Location \"" ~ workingDir ~ "\"; " ~ command;
        spawnProcess(["cmd", "/c", "start", "\"\"", "powershell", "-NoExit", "-Command", wrapped]);
        return true;
    }
    else version (Posix)
    {
        string wrapped = command;
        if (workingDir.length > 0)
            wrapped = "cd \"" ~ workingDir ~ "\" && " ~ command;
        spawnProcess(["sh", "-lc", wrapped]);
        return true;
    }
    else
    {
        return false;
    }
}

private string providerConfigRoot()
{
    version (Windows)
    {
        auto drive = environment.get("HOMEDRIVE");
        auto path = environment.get("HOMEPATH");
        if (drive && path)
            return buildPath(drive, path, ".dev-center");
        return buildPath(environment.get("USERPROFILE"), ".dev-center");
    }
    else
    {
        return buildPath(environment.get("HOME"), ".dev-center");
    }
}

private string buildIssuePreview(string sourceText, int startLine, int endLine)
{
    if (sourceText.length == 0)
        return "Could not load source preview.";
    auto lines = sourceText.splitLines();
    if (lines.length == 0)
        return "Source is empty.";
    startLine = startLine < 1 ? 1 : startLine;
    endLine = endLine < startLine ? startLine : endLine;
    endLine = min(endLine, cast(int)lines.length);
    string result;
    foreach (i; startLine - 1 .. endLine)
        result ~= to!string(i + 1) ~ ": " ~ to!string(lines[i]) ~ "\n";
    return result;
}

void showContext7IssueReportDialog(Window parentWindow, const AIClientProfile client)
{
    logInfo("Opening Context7 reporting helper for " ~ client.displayName);
    auto dlg = new Dialog(UIString.fromRaw("Context7 Reporting Helper"d), parentWindow,
        DialogFlag.Popup | DialogFlag.Resizable);
    dlg.minWidth(820).minHeight(560);

    auto content = new VerticalLayout();
    content.layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT).padding(12);

    auto heading = new TextWidget(null, "Context7 Reporting Helper"d);
    heading.fontSize(16).fontWeight(700).margins(Rect(0, 0, 0, 8));
    content.addChild(heading);

    auto searchBtn = new Button(null, "Search Existing Issues"d);
    searchBtn.click = delegate(Widget w) {
        openUrlInBrowser(context7IssueSearchUrl);
        return true;
    };
    content.addChild(searchBtn);

    auto note = new TextWidget(null,
        "If you have a bug or an idea, read the contributing guidelines before opening an issue."d);
    note.textColor(0xBBBBBB).margins(Rect(0, 8, 0, 4));
    content.addChild(note);

    auto contributingBtn = new Button(null, "Open Contributing Guidelines"d);
    contributingBtn.click = delegate(Widget w) {
        openUrlInBrowser(context7ContributingGuidelinesUrl);
        return true;
    };
    content.addChild(contributingBtn);

    auto actions = new HorizontalLayout();
    actions.layoutWidth(FILL_PARENT).margins(Rect(0, 12, 0, 8));
    auto chooserBtn = new Button(null, "Open Issue Type Chooser"d);
    chooserBtn.click = delegate(Widget w) {
        openUrlInBrowser(context7IssueChooserUrl);
        return true;
    };
    actions.addChild(chooserBtn);
    auto browserBtn = new Button(null, "Open Source In Browser"d);
    actions.addChild(browserBtn);
    content.addChild(actions);

    auto rangeRow = new HorizontalLayout();
    rangeRow.layoutWidth(FILL_PARENT).margins(Rect(0, 4, 0, 8));
    rangeRow.addChild(new TextWidget(null, "Start line"d));
    auto startEdit = new EditLine("ctx7IssueStart", "10"d);
    startEdit.layoutWidth(80);
    rangeRow.addChild(startEdit);
    rangeRow.addChild(new TextWidget(null, "End line"d));
    auto endEdit = new EditLine("ctx7IssueEnd", "20"d);
    endEdit.layoutWidth(80);
    rangeRow.addChild(endEdit);
    auto loadBtn = new Button(null, "Load Range"d);
    rangeRow.addChild(loadBtn);
    content.addChild(rangeRow);

    auto preview = new EditBox("ctx7IssuePreview", ""d);
    preview.layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT);
    preview.fontFamily(FontFamily.MonoSpace);
    preview.readOnly(true);
    content.addChild(preview);

    string sourceText = fetchTextOrEmpty(client.sourceRawUrl.length > 0 ? client.sourceRawUrl : context7AllClientsSourceRawUrl);

    void updatePreview()
    {
        int startLine = 10;
        int endLine = 20;
        try startLine = to!int(to!string(startEdit.text).strip()); catch (Exception) {}
        try endLine = to!int(to!string(endEdit.text).strip()); catch (Exception) {}
        preview.text = UIString.fromRaw(to!dstring(buildIssuePreview(sourceText, startLine, endLine)));
        string sourceUrl = client.sourcePlainUrl.length > 0 ? client.sourcePlainUrl : context7AllClientsSourcePlainUrl;
        sourceUrl ~= "#L" ~ to!string(startLine) ~ "-L" ~ to!string(endLine);
        browserBtn.click = delegate(Widget w) {
            openUrlInBrowser(sourceUrl);
            return true;
        };
    }

    loadBtn.click = delegate(Widget w) { updatePreview(); return true; };
    updatePreview();

    dlg.addChild(content);
    dlg.show();
}

private class MCPSetupWidget : VerticalLayout
{
    private Window _parentWindow;
    private string _repoRoot;
    private string _configRoot;
    private const(AIClientProfile)[] _clients;
    private size_t _selected;

    private VerticalLayout _clientList;
    private EditBox _snippetBox;
    private EditBox _configEditor;
    private EditBox _docsBox;
    private EditBox _cliBox;
    private EditLine _apiKeyEdit;
    private TextWidget _targetPath;
    private TextWidget _clientTitle;
    private TextWidget _status;

    this(Window parentWindow, string repoRoot)
    {
        super();
        _parentWindow = parentWindow;
        _repoRoot = repoRoot;
        _configRoot = providerConfigRoot();
        _clients = getKnownAIClients();
        layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT);
        buildUI();
        if (_clients.length > 0)
            selectClient(0);
    }

    private void buildUI()
    {
        auto topRow = new HorizontalLayout();
        topRow.layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT);

        auto clientScroll = new ScrollWidget();
        clientScroll.layoutWidth(230).layoutHeight(FILL_PARENT);
        _clientList = new VerticalLayout();
        _clientList.layoutWidth(FILL_PARENT).padding(6);
        clientScroll.contentWidget = _clientList;
        topRow.addChild(clientScroll);

        foreach (i, client; _clients)
        {
            auto card = new VerticalLayout();
            card.layoutWidth(FILL_PARENT).padding(8).margins(Rect(0, 0, 0, 6)).backgroundColor(0x222222);
            card.addChild(new TextWidget(null, to!dstring(client.displayName)).fontSize(12).fontWeight(700));
            string subtitle = client.easySetupSupported ? "Easy setup available" : "Manual MCP setup";
            auto note = new TextWidget(null, to!dstring(subtitle));
            note.fontSize(9).textColor(0xAAAAAA);
            card.addChild(note);
            auto btn = new Button(null, "Open Setup"d);
            btn.click = delegate(Widget w) {
                selectClient(i);
                return true;
            };
            card.addChild(btn);
            _clientList.addChild(card);
        }

        auto detail = new VerticalLayout();
        detail.layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT).padding(8);

        _clientTitle = new TextWidget(null, "Client setup"d);
        _clientTitle.fontSize(16).fontWeight(700).margins(Rect(0, 0, 0, 6));
        detail.addChild(_clientTitle);

        auto infoRow = new HorizontalLayout();
        infoRow.layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT);

        auto leftCol = new VerticalLayout();
        leftCol.layoutWidth(260).layoutHeight(FILL_PARENT).padding(4);
        leftCol.addChild(new TextWidget(null, "Snippet / setup summary"d).fontWeight(700).margins(Rect(0, 0, 0, 4)));
        _snippetBox = new EditBox("ctx7SnippetBox", ""d);
        _snippetBox.layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT);
        _snippetBox.fontFamily(FontFamily.MonoSpace);
        _snippetBox.readOnly(true);
        leftCol.addChild(_snippetBox);
        infoRow.addChild(leftCol);

        auto centerCol = new VerticalLayout();
        centerCol.layoutWidth(320).layoutHeight(FILL_PARENT).padding(4);
        centerCol.addChild(new TextWidget(null, "Config file editor"d).fontWeight(700).margins(Rect(0, 0, 0, 4)));
        _targetPath = new TextWidget(null, ""d);
        _targetPath.textColor(0xAAAAAA).fontSize(9).margins(Rect(0, 0, 0, 4));
        centerCol.addChild(_targetPath);
        _configEditor = new EditBox("ctx7ConfigEditor", ""d);
        _configEditor.layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT);
        _configEditor.fontFamily(FontFamily.MonoSpace);
        centerCol.addChild(_configEditor);
        infoRow.addChild(centerCol);

        auto rightCol = new VerticalLayout();
        rightCol.layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT).padding(4);
        rightCol.addChild(new TextWidget(null, "Context7 docs / source helper"d).fontWeight(700).margins(Rect(0, 0, 0, 4)));
        _docsBox = new EditBox("ctx7DocsBox", ""d);
        _docsBox.layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT);
        _docsBox.readOnly(true);
        rightCol.addChild(_docsBox);
        infoRow.addChild(rightCol);

        detail.addChild(infoRow);

        auto controls = new VerticalLayout();
        controls.layoutWidth(FILL_PARENT).margins(Rect(0, 8, 0, 0));

        auto apiRow = new HorizontalLayout();
        apiRow.layoutWidth(FILL_PARENT);
        apiRow.addChild(new TextWidget(null, "Context7 API key"d));
        _apiKeyEdit = new EditLine("ctx7ApiKey", ""d);
        _apiKeyEdit.layoutWidth(220);
        apiRow.addChild(_apiKeyEdit);
        auto btnInsertRemote = new Button(null, "Insert Remote Snippet"d);
        btnInsertRemote.click = delegate(Widget w) { insertSnippet(true); return true; };
        apiRow.addChild(btnInsertRemote);
        auto btnInsertLocal = new Button(null, "Insert Local Snippet"d);
        btnInsertLocal.click = delegate(Widget w) { insertSnippet(false); return true; };
        apiRow.addChild(btnInsertLocal);
        controls.addChild(apiRow);

        auto actionRow = new HorizontalLayout();
        actionRow.layoutWidth(FILL_PARENT).margins(Rect(0, 6, 0, 4));
        auto btnLoadFile = new Button(null, "Load Config File"d);
        btnLoadFile.click = delegate(Widget w) { loadConfigBuffer(); return true; };
        actionRow.addChild(btnLoadFile);
        auto btnSaveFile = new Button(null, "Save Editor To File"d);
        btnSaveFile.click = delegate(Widget w) { saveConfigBuffer(); return true; };
        actionRow.addChild(btnSaveFile);
        auto btnLaunch = new Button(null, "Launch App"d);
        btnLaunch.click = delegate(Widget w) { launchClient(); return true; };
        actionRow.addChild(btnLaunch);
        auto btnDocs = new Button(null, "Open Docs"d);
        btnDocs.click = delegate(Widget w) {
            auto client = _clients[_selected];
            openUrlInBrowser(client.context7ConfigUrl.length > 0 ? client.context7ConfigUrl : client.context7DocsUrl);
            return true;
        };
        actionRow.addChild(btnDocs);
        auto btnSource = new Button(null, "View Source"d);
        btnSource.click = delegate(Widget w) {
            auto client = _clients[_selected];
            openUrlInBrowser(client.sourcePlainUrl.length > 0 ? client.sourcePlainUrl : context7AllClientsSourcePlainUrl);
            return true;
        };
        actionRow.addChild(btnSource);
        auto btnReport = new Button(null, "Report Issue"d);
        btnReport.click = delegate(Widget w) {
            showContext7IssueReportDialog(_parentWindow, _clients[_selected]);
            return true;
        };
        actionRow.addChild(btnReport);
        controls.addChild(actionRow);

        auto cliLabel = new TextWidget(null, "Manual CLI"d);
        cliLabel.fontWeight(700).margins(Rect(0, 8, 0, 4));
        controls.addChild(cliLabel);
        _cliBox = new EditBox("ctx7CliBox", ""d);
        _cliBox.layoutWidth(FILL_PARENT).layoutHeight(90);
        _cliBox.fontFamily(FontFamily.MonoSpace);
        _cliBox.readOnly(true);
        controls.addChild(_cliBox);

        auto cliButtons = new HorizontalLayout();
        cliButtons.layoutWidth(FILL_PARENT).margins(Rect(0, 6, 0, 0));
        auto btnCopyCli = new Button(null, "Copy CLI"d);
        btnCopyCli.click = delegate(Widget w) {
            Platform.instance.setClipboardText(_cliBox.text);
            updateStatus("Copied CLI to clipboard.");
            return true;
        };
        cliButtons.addChild(btnCopyCli);
        auto btnRunEasy = new Button(null, "Run Easy Setup"d);
        btnRunEasy.click = delegate(Widget w) {
            auto client = _clients[_selected];
            if (client.easySetupSupported && client.easySetupCommand.length > 0) {
                auto _ = runCommandInExternalTerminal(client.easySetupCommand, _repoRoot);
                updateStatus("Opened easy setup command in external terminal.");
            } else {
                updateStatus("No easy setup command for this client.");
            }
            return true;
        };
        cliButtons.addChild(btnRunEasy);
        auto btnRunManual = new Button(null, "Run Manual CLI"d);
        btnRunManual.click = delegate(Widget w) {
            auto _ = runCommandInExternalTerminal(to!string(_cliBox.text), _repoRoot);
            updateStatus("Opened manual CLI in external terminal.");
            return true;
        };
        cliButtons.addChild(btnRunManual);
        controls.addChild(cliButtons);

        _status = new TextWidget(null, ""d);
        _status.textColor(0x88CC88).fontSize(9).margins(Rect(0, 6, 0, 0));
        controls.addChild(_status);

        detail.addChild(controls);
        topRow.addChild(detail);
        addChild(topRow);
    }

    private void updateStatus(string msg)
    {
        _status.text = UIString.fromRaw(to!dstring(msg));
    }

    private void selectClient(size_t index)
    {
        if (index >= _clients.length)
            return;
        _selected = index;
        auto client = _clients[index];
        _clientTitle.text = UIString.fromRaw(to!dstring(client.displayName ~ " MCP setup"));

        string summary = "Client: " ~ client.displayName ~ "\n";
        summary ~= "Category: " ~ client.category ~ "\n";
        summary ~= "Preferred docs page:\n" ~ client.context7ConfigUrl ~ "\n\n";
        if (client.easySetupSupported)
            summary ~= "Easy setup:\n" ~ client.easySetupCommand ~ "\n\n";
        summary ~= "Manual strategy: " ~ client.manualConfigStrategy ~ "\n";
        if (client.userConfigFiles.length > 0)
            summary ~= "User config: " ~ client.userConfigFiles[0] ~ "\n";
        if (client.projectConfigFiles.length > 0)
            summary ~= "Project config: " ~ client.projectConfigFiles[0] ~ "\n";
        _snippetBox.text = UIString.fromRaw(to!dstring(summary ~ "\nSuggested remote snippet:\n" ~ makeContext7Snippet(client, "", true)));

        string docsText = "Context7 docs URL:\n" ~ client.context7DocsUrl ~ "\n\n";
        docsText ~= "Config section URL:\n" ~ client.context7ConfigUrl ~ "\n\n";
        docsText ~= "Config docs:\n" ~ client.manualConfigDocsUrl ~ "\n\n";
        docsText ~= "Context7 skills browser:\n" ~ context7SkillsBrowserUrl ~ "\n\n";
        docsText ~= "Source reference:\n" ~ client.sourcePlainUrl ~ "\n";
        foreach (note; client.skillNotes)
            docsText ~= "\n- " ~ note;
        _docsBox.text = UIString.fromRaw(to!dstring(docsText));

        _cliBox.text = UIString.fromRaw(to!dstring(client.easySetupSupported && client.easySetupCommand.length > 0
            ? client.easySetupCommand ~ "\n\n" ~ defaultManualCommand(client, "")
            : defaultManualCommand(client, "")));

        loadConfigBuffer();
    }

    private void loadConfigBuffer()
    {
        auto client = _clients[_selected];
        string target = resolvePreferredConfigPath(client, _repoRoot);
        if (target.length > 0)
            _targetPath.text = UIString.fromRaw("Target file: "d ~ to!dstring(target));
        else
            _targetPath.text = UIString.fromRaw("Target file: determine manually from client docs"d);

        if (target.length > 0 && exists(target))
            _configEditor.text = UIString.fromRaw(to!dstring(readText(target)));
        else
            _configEditor.text = UIString.fromRaw(to!dstring(makeContext7Snippet(client, "", true)));
    }

    private void insertSnippet(bool remote)
    {
        auto client = _clients[_selected];
        string apiKey = to!string(_apiKeyEdit.text).strip();
        if (client.apiKeyRequired && apiKey.length == 0 && !client.easySetupSupported)
        {
            updateStatus("Enter an API key before inserting a manual snippet.");
            return;
        }
        _configEditor.text = UIString.fromRaw(to!dstring(makeContext7Snippet(client, apiKey, remote)));
        _cliBox.text = UIString.fromRaw(to!dstring(defaultManualCommand(client, apiKey)));
        updateStatus(remote ? "Inserted remote snippet into editor." : "Inserted local snippet into editor.");
    }

    private void saveConfigBuffer()
    {
        auto client = _clients[_selected];
        string target = resolvePreferredConfigPath(client, _repoRoot);
        if (target.length == 0)
        {
            updateStatus("No concrete config path is known for this client. Use the docs link.");
            return;
        }
        try
        {
            auto dir = dirName(target);
            if (dir.length > 0 && !exists(dir))
                mkdirRecurse(dir);
            write(target, to!string(_configEditor.text));
            updateStatus("Saved editor contents to " ~ target);
        }
        catch (Exception e)
        {
            updateStatus("Save failed: " ~ e.msg);
        }
    }

    private void launchClient()
    {
        auto client = _clients[_selected];
        if (client.launchCommand.length == 0)
        {
            updateStatus("This client has no launch command profile.");
            return;
        }
        try
        {
            spawnProcess([client.launchCommand]);
            updateStatus("Tried to launch " ~ client.displayName ~ ".");
        }
        catch (Exception e)
        {
            updateStatus("Launch failed: " ~ e.msg);
        }
    }
}

private class SkillsWidget : VerticalLayout
{
    this()
    {
        super();
        layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT).padding(10);

        auto heading = new TextWidget(null, "Skills and rules"d);
        heading.fontSize(15).fontWeight(700).margins(Rect(0, 0, 0, 8));
        addChild(heading);

        auto intro = new TextWidget(null,
            "Skills, rules, and MCP are all ways to expand what an AI client can do. Use the skills browser and the client notes below to decide where to wire Context7 into each tool."d);
        intro.textColor(0xBBBBBB);
        addChild(intro);

        auto btnRow = new HorizontalLayout();
        btnRow.layoutWidth(FILL_PARENT).margins(Rect(0, 10, 0, 10));
        auto openSkills = new Button(null, "Open Context7 Skills Browser"d);
        openSkills.click = delegate(Widget w) { openUrlInBrowser(context7SkillsBrowserUrl); return true; };
        btnRow.addChild(openSkills);
        auto openAllClients = new Button(null, "Open All Clients Docs"d);
        openAllClients.click = delegate(Widget w) { openUrlInBrowser(context7AllClientsDocsUrl); return true; };
        btnRow.addChild(openAllClients);
        addChild(btnRow);

        auto scroll = new ScrollWidget();
        scroll.layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT);
        auto content = new VerticalLayout();
        content.layoutWidth(FILL_PARENT).padding(4);

        foreach (client; getKnownAIClients())
        {
            auto box = new VerticalLayout();
            box.layoutWidth(FILL_PARENT).padding(8).margins(Rect(0, 0, 0, 6)).backgroundColor(0x222222);
            box.addChild(new TextWidget(null, to!dstring(client.displayName)).fontWeight(700));
            foreach (note; client.skillNotes)
            {
                auto line = new TextWidget(null, to!dstring("- " ~ note));
                line.textColor(0xBBBBBB).fontSize(9);
                box.addChild(line);
            }
            auto btn = new Button(null, "Open Client Context7 Docs"d);
            auto url = client.context7DocsUrl;
            btn.click = delegate(Widget w) { openUrlInBrowser(url); return true; };
            box.addChild(btn);
            content.addChild(box);
        }

        scroll.contentWidget = content;
        addChild(scroll);
    }
}

void showAIConfigDialog(Window parentWindow, string repoRoot = "")
{
    logInfo("Opening AI Config dialog.");
    auto dlg = new Dialog(UIString.fromRaw("AI Config"d), parentWindow,
        DialogFlag.Popup | DialogFlag.Resizable);
    dlg.minWidth(1200).minHeight(760);

    auto outer = new VerticalLayout();
    outer.layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT).padding(10);

    auto heading = new TextWidget(null, "AI Config"d);
    heading.fontSize(18).fontWeight(800).margins(Rect(0, 0, 0, 8));
    outer.addChild(heading);

    auto tabBarNote = new TextWidget(null, "Providers, MCP Setup, and Skills live together here because they all affect what AI tools can do."d);
    tabBarNote.textColor(0xAAAAAA).fontSize(10).margins(Rect(0, 0, 0, 8));
    outer.addChild(tabBarNote);

    auto tabs = new TabWidget();
    tabs.layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT);

    auto providersTab = new ScrollWidget();
    providersTab.layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT);
    auto providersContent = new VerticalLayout();
    providersContent.layoutWidth(FILL_PARENT).padding(10);

    string cfgRoot = providerConfigRoot();
    foreach (provider; KNOWN_PROVIDERS)
    {
        auto row = new VerticalLayout();
        row.layoutWidth(FILL_PARENT).padding(8).margins(Rect(0, 0, 0, 6)).backgroundColor(0x222222);
        row.addChild(new TextWidget(null, to!dstring(provider.name)).fontWeight(700));

        string saved = getProviderKey(cfgRoot, provider.id).strip();
        string state = saved.length > 0 ? "Saved key detected" : "No saved key";
        auto stateW = new TextWidget(null, to!dstring(state));
        stateW.textColor(saved.length > 0 ? 0x88CC88 : 0xCCAA66).fontSize(9);
        row.addChild(stateW);

        auto edit = new EditLine(provider.id ~ "_key", to!dstring(saved));
        edit.layoutWidth(360);
        row.addChild(edit);

        auto btns = new HorizontalLayout();
        btns.layoutWidth(FILL_PARENT).margins(Rect(0, 6, 0, 0));
        auto saveBtn = new Button(null, "Save Key"d);
        auto providerId = provider.id;
        saveBtn.click = delegate(Widget w) {
            saveProviderKey(cfgRoot, providerId, to!string(edit.text).strip());
            parentWindow.showMessageBox(UIString.fromRaw("AI Provider"d), UIString.fromRaw("Saved key for "d ~ to!dstring(provider.name)));
            return true;
        };
        btns.addChild(saveBtn);
        auto openBtn = new Button(null, "Open Provider Site"d);
        auto siteUrl = provider.websiteUrl;
        openBtn.click = delegate(Widget w) { openUrlInBrowser(siteUrl); return true; };
        btns.addChild(openBtn);
        row.addChild(btns);
        providersContent.addChild(row);
    }
    providersTab.contentWidget = providersContent;

    auto mcpTab = new MCPSetupWidget(parentWindow, repoRoot);
    auto skillsTab = new SkillsWidget();

    tabs.addTab(providersTab, "Providers"d);
    tabs.addTab(mcpTab, "MCP Setup"d);
    tabs.addTab(skillsTab, "Skills"d);

    outer.addChild(tabs);
    dlg.addChild(outer);
    dlg.show();
}
