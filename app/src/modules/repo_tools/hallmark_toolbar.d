module modules.repo_tools.hallmark_toolbar;

import dlangui;
import std.file : exists, dirEntries, SpanMode;
import std.path : buildPath, extension;
import std.string : endsWith;
import std.conv : to;

import modules.repo_tools.editor_detector;
import modules.repo_tools.repo_init;
import modules.repo_tools.gitignore_viewer_widget;
import modules.template_installer.installer;
import modules.repo_tools.registry;

/// Creates a "Compound Button" layout that splits behavior into multiple discrete click areas.
/// Primary text acts as the label, secondary icon buttons handle targeted actions.
Widget createCompoundButton(string label, void delegate(Widget) onHighlight, void delegate(Widget) onOpenViewer, void delegate(Widget) onInternalEdit, void delegate(Widget) onExternalEdit)
{
    HorizontalLayout hl = new HorizontalLayout();
    hl.layoutWidth(WRAP_CONTENT).layoutHeight(WRAP_CONTENT);
    hl.padding(2);
    hl.margins(5);
    hl.backgroundColor = 0x1A1A1A;
    // hl.border = Border.solid(1, 0x333333); // Simulate a single border around the whole group
    
    // 1. Primary Button (Highlight / Expand file)
    Button btnMain = new Button();
    btnMain.text = UIString.fromRaw(to!dstring(label));
    btnMain.styleId = "BUTTON_TRANSPARENT";
    if (onHighlight) btnMain.click = onHighlight;
    hl.addChild(btnMain);
    
    // Vertical Separator
    TextWidget div1 = new TextWidget(null, UIString.fromRaw("|"d));
    div1.textColor = 0x555555;
    hl.addChild(div1);
    
    // 2. Open Viewer Action (e.g. Markdown / Asciidoc rendering)
    Button btnView = new Button();
    btnView.text = UIString.fromRaw("View"d);
    btnView.styleId = "BUTTON_TRANSPARENT";
    if (onOpenViewer) btnView.click = onOpenViewer;
    hl.addChild(btnView);
    
    TextWidget div2 = new TextWidget(null, UIString.fromRaw("|"d));
    div2.textColor = 0x555555;
    hl.addChild(div2);
    
    // 3. Simple Edit (Internal Editor)
    Button btnEdit = new Button();
    btnEdit.text = UIString.fromRaw("Edit"d);
    btnEdit.styleId = "BUTTON_TRANSPARENT";
    if (onInternalEdit) btnEdit.click = onInternalEdit;
    hl.addChild(btnEdit);
    
    TextWidget div3 = new TextWidget(null, UIString.fromRaw("|"d));
    div3.textColor = 0x555555;
    hl.addChild(div3);
    
    // 4. External Editor / Share
    Button btnExtEdit = new Button();
    btnExtEdit.text = UIString.fromRaw("Open With"d);
    btnExtEdit.styleId = "BUTTON_TRANSPARENT";
    if (onExternalEdit) btnExtEdit.click = onExternalEdit;
    hl.addChild(btnExtEdit);
    
    return hl;
}

/// Discovers all VSCode multi-root workspace files in the repo
string[] findWorkspaceFiles(string repoPath)
{
    string[] wksps;
    foreach(entry; dirEntries(repoPath, SpanMode.shallow))
    {
        if (entry.name.endsWith(".code-workspace")) {
            wksps ~= entry.name;
        }
    }
    return wksps;
}

/// Create the popup menu to choose a specific detected VSCode fork to open the workspace.
void showEditorSelectorDialog(Window parentWindow, string targetPath)
{
    import dlangui.dialogs.dialog;
    
    EditorProfile[] availableEditors = detectInstalledEditors();
    
    if (availableEditors.length == 0) {
         parentWindow.showMessageBox(UIString.fromRaw("Editors"d), UIString.fromRaw("No known editors detected on PATH."d));
         return;
    }
    
    // Create a simple custom list selection dialog or popup menu
    PopupMenu menu = new PopupMenu();
    foreach(i, EditorProfile ed; availableEditors)
    {
        auto item = menu.addMenuItem(new MenuItem(new Action(to!int(100+i), UIString.fromRaw(to!dstring(ed.name)))));
        item.action.bind(this, delegate(Action a) {
            openPathWithEditor(availableEditors[a.id - 100], targetPath);
            return true;
        });
    }
    
    // Add the "Register Fork (+)" option
    menu.addMenuItem(new MenuItem(new Action(999, UIString.fromRaw("Register custom fork..."d))));
    
    // Show near mouse pointer
    menu.popup(parentWindow.mainWidget, 0, 0); 
}

/// Builds the hallmark strip for a specific repository.
/// If onShowGitignoreViewer is set and .gitignore exists, adds a Gitignore compound button.
Widget createRepoToolbar(Window parentWindow, string repoPath, TemplateInstaller installer, RepoToolsRegistry repoTools,
    void delegate(Window, string, TemplateInstaller) onShowGitignoreViewer = null)
{
    HorizontalLayout bar = new HorizontalLayout("RepoToolbar");
    bar.layoutWidth(FILL_PARENT).layoutHeight(WRAP_CONTENT);
    bar.padding(5);
    bar.backgroundColor = 0x242424; // slightly distinct header strip
    
    // README Hallmark
    bool hasReadme = exists(buildPath(repoPath, "README.adoc")) || exists(buildPath(repoPath, "README.md"));
    if (hasReadme) {
        bar.addChild(createCompoundButton("Readme", 
            delegate(Widget w) { parentWindow.showMessageBox(UIString.fromRaw("Action"d), UIString.fromRaw("Highlighting Readme in File Tree..."d)); return true; },
            delegate(Widget w) { parentWindow.showMessageBox(UIString.fromRaw("Action"d), UIString.fromRaw("Opening markdown/asciidoc webview viewer..."d)); return true; },
            delegate(Widget w) { parentWindow.showMessageBox(UIString.fromRaw("Action"d), UIString.fromRaw("Opening fast DevCentr text editor..."d)); return true; },
            delegate(Widget w) { parentWindow.showMessageBox(UIString.fromRaw("Action"d), UIString.fromRaw("Sending to default system text editor..."d)); return true; }
        ));
    }
    
    // GITIGNORE Hallmark
    bool hasGitignore = exists(buildPath(repoPath, ".gitignore"));
    if (hasGitignore) {
        bar.addChild(createCompoundButton("Gitignore",
            delegate(Widget w) { parentWindow.showMessageBox(UIString.fromRaw("Action"d), UIString.fromRaw("Highlighting .gitignore in File Tree..."d)); return true; },
            delegate(Widget w) {
                auto container = parentWindow.mainWidget.childById("repoPreviewContainer");
                if (container) {
                    container.removeAllChildren();
                    import modules.repo_tools.gitignore_viewer_widget;
                    auto viewer = new GitignoreViewerWidget(repoPath, installer);
                    auto toolRow = new HorizontalLayout();
                    toolRow.layoutWidth(FILL_PARENT).padding(5);
                    auto saveBtn = new Button(null, "Save"d);
                    saveBtn.click = delegate(Widget w2) { viewer.save(); return true; };
                    auto closeBtn = new Button(null, "Close"d);
                    closeBtn.click = delegate(Widget w2) {
                        container.removeAllChildren();
                        auto def = new TextWidget(null, "Repository: "d ~ to!dstring(repoPath));
                        def.alignment(Alignment.Center).textColor(0xAAAAAA);
                        container.addChild(def);
                        return true;
                    };
                    toolRow.addChild(saveBtn);
                    toolRow.addChild(closeBtn);
                    container.addChild(toolRow);
                    container.addChild(viewer);
                }
                return true;
            },
            delegate(Widget w) {
                auto container = parentWindow.mainWidget.childById("repoPreviewContainer");
                if (container) {
                    container.removeAllChildren();
                    import modules.repo_tools.gitignore_viewer_widget;
                    auto viewer = new GitignoreViewerWidget(repoPath, installer);
                    auto toolRow = new HorizontalLayout();
                    toolRow.layoutWidth(FILL_PARENT).padding(5);
                    auto saveBtn = new Button(null, "Save"d);
                    saveBtn.click = delegate(Widget w2) { viewer.save(); return true; };
                    auto closeBtn = new Button(null, "Close"d);
                    closeBtn.click = delegate(Widget w2) {
                        container.removeAllChildren();
                        auto def = new TextWidget(null, "Repository: "d ~ to!dstring(repoPath));
                        def.alignment(Alignment.Center).textColor(0xAAAAAA);
                        container.addChild(def);
                        return true;
                    };
                    toolRow.addChild(saveBtn);
                    toolRow.addChild(closeBtn);
                    container.addChild(toolRow);
                    container.addChild(viewer);
                }
                return true;
            },
            delegate(Widget w) { showEditorSelectorDialog(parentWindow, buildPath(repoPath, ".gitignore")); return true; }
        ));
    }

    // CHANGELOG Hallmark
    bool hasChangelog = exists(buildPath(repoPath, "changelog.adoc")) || exists(buildPath(repoPath, "docs", "modules", "ROOT", "pages", "changelog.adoc"));
    if (hasChangelog) {
        bar.addChild(createCompoundButton("Changelog", 
            delegate(Widget w) { parentWindow.showMessageBox(UIString.fromRaw("Action"d), UIString.fromRaw("Highlighting Changelog in File Tree..."d)); return true; },
            delegate(Widget w) { parentWindow.showMessageBox(UIString.fromRaw("Action"d), UIString.fromRaw("Opening changelog webview viewer..."d)); return true; },
            delegate(Widget w) { parentWindow.showMessageBox(UIString.fromRaw("Action"d), UIString.fromRaw("Opening DevCentr AI changelog generation tool..."d)); return true; },
            delegate(Widget w) { parentWindow.showMessageBox(UIString.fromRaw("Action"d), UIString.fromRaw("Sending to default system text editor..."d)); return true; }
        ));
    }

    Spacer spacer = new Spacer();
    spacer.layoutWidth(FILL_PARENT);
    bar.addChild(spacer);
    
    // --- Workspaces & Editor Integration Block ---
    
    VerticalLayout workspaceBlock = new VerticalLayout("WorkspaceBlock");
    workspaceBlock.layoutWidth(WRAP_CONTENT).layoutHeight(WRAP_CONTENT);
    workspaceBlock.padding(5);
    workspaceBlock.backgroundColor = 0x1A1A1A;
    workspaceBlock.margins(Rect(10, 0, 0, 0)); // space out from hallmarks
    
    string[] workspaces = findWorkspaceFiles(repoPath);
    
    // Status text (analogous to permanent toast)
    TextWidget wkspNote = new TextWidget("wkspNote", UIString.fromRaw(workspaces.length > 0 
        ? "Workspaces detected. A workspace organizes IDE-specific settings isolated from global config."d
        : "No workspace detected. IDE configs and root-scoping will default to .vscode/ layout or standard git root."d));
    wkspNote.textColor = 0x888888;
    wkspNote.fontSize = 9;
    
    HorizontalLayout btnsArea = new HorizontalLayout();
    
    if (workspaces.length > 0)
    {
        Button btnLaunchWksp = new Button("btnWksp", UIString.fromRaw("Launch Workspace"d));
        btnLaunchWksp.textColor = 0x00FF88;
        btnLaunchWksp.click = delegate(Widget w) {
            if (workspaces.length == 1) {
                showEditorSelectorDialog(parentWindow, workspaces[0]);
            } else {
                import dlangui.dialogs.dialog;
                PopupMenu menu = new PopupMenu();
                foreach(i, ws; workspaces) {
                    auto item = menu.addMenuItem(new MenuItem(new Action(to!int(200+i), UIString.fromRaw(to!dstring(baseName(ws))))));
                    item.action.bind(btnLaunchWksp, delegate(Action a) {
                        showEditorSelectorDialog(parentWindow, workspaces[a.id - 200]);
                        return true;
                    });
                }
                menu.popup(parentWindow.mainWidget, 0, 0); 
            }
            return true;
        };
        btnsArea.addChild(btnLaunchWksp);
    }
    else
    {
        Button btnNoWksp = new Button("btnWksp", UIString.fromRaw("No Workspace"d));
        btnNoWksp.textColor = 0x555555;
        btnNoWksp.enabled = false;
        btnsArea.addChild(btnNoWksp);
    }
    
    // Vertical Separator
    TextWidget spanDiv = new TextWidget(null, UIString.fromRaw(" | "d));
    spanDiv.textColor = 0x444444;
    btnsArea.addChild(spanDiv);
    
    // Init/Import Compound Control
    Button btnInit = new Button("btnInit", UIString.fromRaw("Init/Import"d));
    btnInit.styleId = "BUTTON_TRANSPARENT";
    btnInit.textColor = 0x00AAFF;
    btnInit.click = delegate(Widget w) {
        showRepoInitDialog(parentWindow, repoPath, installer);
        return true;
    };
    btnsArea.addChild(btnInit);
    
    // Sync Button
    Button btnSync = new Button("btnSync", UIString.fromRaw("Sync Profile"d));
    btnSync.styleId = "BUTTON_TRANSPARENT";
    btnSync.click = delegate(Widget w) {
        parentWindow.showMessageBox(UIString.fromRaw("Sync Provider"d), 
            UIString.fromRaw("Overwrite repo workspace logic by checking remote templates repo or PR changes back if you have write access up-stream."d));
        return true;
    };
    btnsArea.addChild(btnSync);
    
    workspaceBlock.addChild(wkspNote);
    workspaceBlock.addChild(btnsArea);
    bar.addChild(workspaceBlock);
    
    // Open full directory fallback
    Button btnOpenDir = new Button("btnOpenDir", UIString.fromRaw("Open Full Repo"d));
    btnOpenDir.margins(Rect(10, 0, 0, 0));
    btnOpenDir.click = delegate(Widget w) {
        showEditorSelectorDialog(parentWindow, repoPath);
        return true;
    };
    bar.addChild(btnOpenDir);
    
    return bar;
}
