module modules.repo_tools.repo_init;

import dlangui;
import dlangui.dialogs.dialog : Dialog, DialogFlag;
import std.file;
import std.path;
import std.conv;
import std.string;
import std.algorithm;
import modules.template_installer.installer;
import modules.repo_tools.gitignore_template_sources;
import modules.vcs.git_performance_dialog : showGitPerformanceDialog;
import std.process : execute;

/// Flow to initialize a repository with .gitattributes and .gitignore
void showRepoInitDialog(Window parentWindow, string repoRoot, TemplateInstaller installer)
{
    auto dlg = new Dialog(UIString.fromRaw("Initialize Repository"d), parentWindow,
        DialogFlag.Popup | DialogFlag.Resizable);
    dlg.minWidth(700).minHeight(600);

    auto content = new VerticalLayout();
    content.layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT).padding(15);

    // 1. Choose System
    auto systemLabel = new TextWidget(null, UIString.fromRaw("Select Version Control System"d));
    systemLabel.fontSize(12).fontWeight(700).margins(Rect(0, 0, 0, 10));
    content.addChild(systemLabel);

    auto systemRow = new HorizontalLayout();
    auto rbGit = new RadioButton("git", UIString.fromRaw("Git"d));
    rbGit.checked = true;
    systemRow.addChild(rbGit);
    
    auto rbHg = new RadioButton("hg", UIString.fromRaw("Mercurial (Coming Soon)"d));
    rbHg.enabled = false;
    systemRow.addChild(rbHg);
    
    content.addChild(systemRow);

    // 2. Explanation
    auto explanation = new TextWidget(null, UIString.fromRaw(
        "This flow will initialize your repository with sane defaults.\n" ~
        "• .gitattributes: Forces LF line endings and auto-detection of text files.\n" ~
        "• .gitignore: Uses the 'Whitelist Strategy' (*). This keeps your repo root clean\n" ~
        "  by ignoring everything by default and only allowing what is explicitly whitelisted."d));
    explanation.fontSize(9).textColor(0xAAAAAA).margins(Rect(0, 10, 0, 10));
    content.addChild(explanation);

    // 2.5 Performance Check
    auto perfRow = new HorizontalLayout();
    perfRow.layoutWidth(FILL_PARENT).padding(10).backgroundColor(0x1B1B1B).margins(Rect(0, 5, 0, 5));
    
    auto res = execute(["git", "config", "--global", "core.fsmonitor"]);
    bool fsMonitorEnabled = (res.status == 0 && res.output.strip() == "true");
    
    auto perfIcon = new TextWidget(null, UIString.fromRaw(fsMonitorEnabled ? "🚀"d : "⚠️"d));
    perfIcon.fontSize(16).margins(Rect(0, 0, 10, 0));
    perfRow.addChild(perfIcon);
    
    auto perfText = new TextWidget(null, UIString.fromRaw(fsMonitorEnabled ? 
        "Git performance optimization (FSMonitor) is active on this machine."d : 
        "Recommended: Git performance optimization is not enabled globally."d));
    perfText.layoutWidth(FILL_PARENT).fontSize(9).textColor(fsMonitorEnabled ? 0x88CC88 : 0xCCAA66);
    perfRow.addChild(perfText);
    
    auto btnPerf = new Button(null, UIString.fromRaw("Git Global Settings"d));
    btnPerf.click = delegate(Widget w) {
        showGitPerformanceDialog(parentWindow);
        return true;
    };
    perfRow.addChild(btnPerf);
    
    content.addChild(perfRow);

    // 3. Template Source and Selection
    auto sourceLabel = new TextWidget(null, UIString.fromRaw("Template Source"d));
    sourceLabel.fontSize(10).fontWeight(600).margins(Rect(0, 10, 0, 5));
    content.addChild(sourceLabel);

    auto sourceRow = new HorizontalLayout();
    auto rbDevCentr = new RadioButton("src_devcentr", UIString.fromRaw("DevCentr (whitelist + ecosystems)"d));
    rbDevCentr.checked = true;
    sourceRow.addChild(rbDevCentr);
    auto rbGitHub = new RadioButton("src_github", UIString.fromRaw("GitHub (github/gitignore)"d));
    sourceRow.addChild(rbGitHub);
    content.addChild(sourceRow);

    auto ecoLabel = new TextWidget(null, UIString.fromRaw("Merge Ecosystem Templates"d));
    ecoLabel.fontSize(10).fontWeight(600).margins(Rect(0, 10, 0, 5));

    auto ecoList = new HorizontalLayout();
    ecoList.layoutWidth(FILL_PARENT).padding(5);

    string[] ecosystems;
    auto templatesPath = buildPath(installer.cachePath, "repo", "workspaces");
    if (exists(templatesPath)) {
        foreach(entry; dirEntries(templatesPath, SpanMode.shallow)) {
            if (entry.isDir && baseName(entry.name)[0] != '_') {
                ecosystems ~= baseName(entry.name);
            }
        }
    }

    CheckBox[] ecoCheckboxes;
    foreach(eco; ecosystems) {
        auto cb = new CheckBox(to!string(eco), UIString.fromRaw(to!dstring(eco)));
        ecoList.addChild(cb);
        ecoCheckboxes ~= cb;
    }

    auto ecoContainer = new VerticalLayout();
    ecoContainer.layoutWidth(FILL_PARENT);
    ecoContainer.addChild(ecoLabel);
    ecoContainer.addChild(ecoList);

    auto ghLabel = new TextWidget(null, UIString.fromRaw("Select Templates (scroll to see more)"d));
    ghLabel.fontSize(10).fontWeight(600).margins(Rect(0, 10, 0, 5));
    auto ghTemplatesLayout = new VerticalLayout();
    ghTemplatesLayout.layoutWidth(FILL_PARENT).padding(5);
    auto ghScroll = new ScrollWidget();
    ghScroll.layoutWidth(FILL_PARENT).layoutHeight(150);
    ghScroll.contentWidget = ghTemplatesLayout;
    auto ghContainer = new VerticalLayout();
    ghContainer.layoutWidth(FILL_PARENT);
    ghContainer.addChild(ghLabel);
    ghContainer.addChild(ghScroll);
    ghContainer.visibility = Visibility.Gone;

    CheckBox[] ghCheckboxes;
    GitIgnoreTemplate[] ghTemplates;
    bool ghPopulated = false;

    void populateGitHubTemplates() {
        if (ghPopulated) return;
        if (!installer.ensureGitHubGitIgnoreCache()) return;
        ghTemplates = listFromGitHub(installer.githubGitIgnorePath);
        foreach (t; ghTemplates) {
            auto cb = new CheckBox(t.id, UIString.fromRaw(to!dstring(t.category ~ ": " ~ t.name)));
            ghTemplatesLayout.addChild(cb);
            ghCheckboxes ~= cb;
        }
        ghPopulated = true;
    }

    rbDevCentr.click = delegate(Widget w) {
        ecoContainer.visibility = Visibility.Visible;
        ghContainer.visibility = Visibility.Gone;
        return true;
    };
    rbGitHub.click = delegate(Widget w) {
        ecoContainer.visibility = Visibility.Gone;
        ghContainer.visibility = Visibility.Visible;
        populateGitHubTemplates();
        return true;
    };

    content.addChild(ecoContainer);
    content.addChild(ghContainer);

    // 4. Preview / Edit Area
    auto tabs = new TabWidget();
    tabs.layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT);
    
    auto gitAttributesEdit = new EditBox("gitattributes", UIString.fromRaw("* text=auto eol=lf\n"d));
    gitAttributesEdit.layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT);

    auto gitIgnoreEdit = new EditBox("gitignore", UIString.fromRaw("# Whitelist strategy\n*\n!.gitignore\n!README.adoc\n!LICENSE\n"d));
    gitIgnoreEdit.layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT);

    string defaultEditorConfig = "[*]\nend_of_line = lf\ninsert_final_newline = true\n\n[*.bat]\nend_of_line = crlf\n\n[*.cmd]\nend_of_line = crlf\n\n[*.reg]\nend_of_line = crlf\n";
    auto editorConfigEdit = new EditBox("editorconfig", UIString.fromRaw(to!dstring(defaultEditorConfig)));
    editorConfigEdit.layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT);

    tabs.addTab(gitAttributesEdit, ".gitattributes"d);
    tabs.addTab(gitIgnoreEdit, ".gitignore"d);
    tabs.addTab(editorConfigEdit, ".editorconfig"d);
    content.addChild(tabs);

    // Update button to merge templates
    auto btnUpdatePreview = new Button(null, UIString.fromRaw("Refresh from Templates"d));
    btnUpdatePreview.click = delegate(Widget w) {
        string mergedIgnore;
        if (rbDevCentr.checked) {
            mergedIgnore = "# Whitelist strategy\n*\n!.gitignore\n!README.adoc\n!LICENSE\n\n";
            auto commonIgnore = buildPath(templatesPath, "_common", ".gitignore");
            if (exists(commonIgnore)) {
                mergedIgnore ~= "# From _common\n" ~ readText(commonIgnore) ~ "\n";
            }
            foreach(cb; ecoCheckboxes) {
                if (cb.checked) {
                    auto ecoIgnore = buildPath(templatesPath, to!string(cb.id), ".gitignore");
                    if (exists(ecoIgnore)) {
                        mergedIgnore ~= "# From " ~ to!string(cb.id) ~ "\n" ~ readText(ecoIgnore) ~ "\n";
                    }
                }
            }
        } else if (rbGitHub.checked) {
            populateGitHubTemplates();
            if (!installer.ensureGitHubGitIgnoreCache()) {
                parentWindow.showMessageBox(UIString.fromRaw("GitHub Templates"d), UIString.fromRaw("Could not fetch github/gitignore. Check network or try again."d));
                return true;
            }
            mergedIgnore = "# From github/gitignore\n\n";
            foreach(i, cb; ghCheckboxes) {
                if (i < ghTemplates.length && cb.checked) {
                    auto t = ghTemplates[i];
                    auto tmplContent = readTemplateContent(t.path);
                    if (tmplContent.length > 0) {
                        mergedIgnore ~= "# From " ~ t.name ~ " (" ~ t.category ~ ")\n" ~ tmplContent ~ "\n";
                    }
                }
            }
            if (mergedIgnore == "# From github/gitignore\n\n") {
                mergedIgnore = "# Whitelist strategy\n*\n!.gitignore\n!README.adoc\n!LICENSE\n\n# Select GitHub templates above and click Refresh.";
            }
        }
        gitIgnoreEdit.text = UIString.fromRaw(to!dstring(mergedIgnore));
        return true;
    };
    content.addChild(btnUpdatePreview);

    // Footer info
    auto userConfigInfo = new TextWidget(null, UIString.fromRaw("Note: .gitattributes in the repo overrides your global Git config."d));
    userConfigInfo.fontSize(8).textColor(0x888888);
    content.addChild(userConfigInfo);

    // 5. Actions
    auto actionRow = new HorizontalLayout();
    import dlangui.widgets.styles : Align;
    actionRow.layoutWidth(FILL_PARENT).alignment(Align.Right).padding(10);
    
    auto btnCancel = new Button(null, UIString.fromRaw("Cancel"d));
    btnCancel.click = delegate(Widget w) { dlg.close(new Action(2)); return true; };
    actionRow.addChild(btnCancel);
    
    auto btnInit = new Button(null, UIString.fromRaw("Initialize"d));
    btnInit.click = delegate(Widget w) {
        try {
            if (!exists(repoRoot)) mkdirRecurse(repoRoot);
            
            write(buildPath(repoRoot, ".gitattributes"), to!string(gitAttributesEdit.text));
            write(buildPath(repoRoot, ".gitignore"), to!string(gitIgnoreEdit.text));
            write(buildPath(repoRoot, ".editorconfig"), to!string(editorConfigEdit.text));
            
            // Execute git init if .git doesn't exist
            if (!exists(buildPath(repoRoot, ".git"))) {
                import std.process : execute;
                execute(["git", "init", repoRoot]);
            }
            
            parentWindow.showMessageBox(UIString.fromRaw("Success"d), UIString.fromRaw("Repository initialized successfully."d));
            dlg.close(new Action(1));
        } catch (Exception e) {
            parentWindow.showMessageBox(UIString.fromRaw("Error"d), UIString.fromRaw("Failed to initialize: "d ~ to!dstring(e.msg)));
        }
        return true;
    };
    actionRow.addChild(btnInit);
    
    content.addChild(actionRow);

    dlg.addChild(content);
    dlg.show();
}
