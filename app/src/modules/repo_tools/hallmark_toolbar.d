module app.src.modules.repo_tools.hallmark_toolbar;

import dlangui;
import std.file : exists, dirEntries, SpanMode;
import std.path : buildPath, extension;
import std.string : endsWith;
import std.conv : to;

import app.src.modules.repo_tools.editor_detector;

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

/// Discovers if a VSCode multi-root workspace file exists in the repo
string findWorkspaceFile(string repoPath)
{
    foreach(entry; dirEntries(repoPath, SpanMode.shallow))
    {
        if (entry.name.endsWith(".code-workspace")) {
            return entry.name;
        }
    }
    return "";
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
Widget createRepoToolbar(Window parentWindow, string repoPath)
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
    
    // IDE detection buttons
    string workspaceFile = findWorkspaceFile(repoPath);
    if (workspaceFile.length > 0)
    {
        Button btnWksp = new Button("btnWksp", UIString.fromRaw("Launch Workspace"d));
        btnWksp.textColor = 0x00FF88; // distinctive color
        btnWksp.click = delegate(Widget w) {
            showEditorSelectorDialog(parentWindow, workspaceFile);
            return true;
        };
        bar.addChild(btnWksp);
    }
    
    // Open full directory
    Button btnOpenDir = new Button("btnOpenDir", UIString.fromRaw("Open Full Repo"d));
    btnOpenDir.click = delegate(Widget w) {
        showEditorSelectorDialog(parentWindow, repoPath);
        return true;
    };
    bar.addChild(btnOpenDir);
    
    return bar;
}
