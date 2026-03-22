module modules.vcs.vcs_widget;

import dlangui;
import dlangui.dialogs.dialog : Dialog, DialogFlag;
import std.file : exists, dirEntries, SpanMode, isDir;
import std.path : buildPath, baseName, relativePath;
import std.algorithm : canFind, filter, sort;
import std.array : array;
import std.conv : to;
import std.json : JSONValue, parseJSON;
import modules.infra.ui : openUrlInBrowser;
import modules.repo_tools.git_viewers : isExecutableInstalled;

/// Represents a detected Version Control System instance.
struct VCSInstance
{
    string id;
    string type;      /// git, hg, svn, etc.
    string rootPath;  /// Absolute path to the VCS root.
    string label;     /// Display label.
    bool isTopLevel;  /// True if it's the repository root VCS.
    bool isIgnored;   /// True if the user has ignored this provider.
    string parentId;  /// For modeling hierarchy.
}

/// The Version Control module widget.
class VersionControlWidget : HorizontalLayout
{
    private string _repoPath;
    private VCSInstance[] _instances;
    private ListWidget _vcsList;
    private VerticalLayout _detailsPanel;
    private StringListAdapter _listAdapter;

    this(string repoPath)
    {
        super("vcs_widget");
        _repoPath = repoPath;
        layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT);

        _listAdapter = new StringListAdapter();
        initializeUI();
        refreshVCSList();
    }

    private void initializeUI()
    {
        // Left Panel: VCS List
        VerticalLayout leftPanel = new VerticalLayout();
        leftPanel.layoutWidth(250).layoutHeight(FILL_PARENT).padding(5).backgroundColor(0x1A1A1A);
        
        TextWidget title = new TextWidget(null, "Version Control Systems"d);
        title.fontSize = 12;
        title.fontWeight = 800;
        title.margins(Rect(5,5,5,5));
        leftPanel.addChild(title);

        _vcsList = new ListWidget("vcs_list");
        _vcsList.layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT);
        _vcsList.adapter = _listAdapter;
        _vcsList.itemClick = delegate(Widget source, int itemIndex) {
            if (itemIndex >= 0 && itemIndex < _instances.length) {
                showVCSDetails(_instances[itemIndex]);
            }
            return true;
        };
        
        // Context Menu for "Ignore"
        _vcsList.mouseEvent = delegate(Widget w, MouseEvent event) {
            if (event.action == MouseAction.ButtonDown && event.button == MouseButton.Right) {
                int idx = _vcsList.selectedItemIndex;
                if (idx >= 0 && idx < _instances.length) {
                    showIgnoreMenu(event.x, event.y, _instances[idx]);
                }
                return true;
            }
            return false;
        };

        leftPanel.addChild(_vcsList);
        addChild(leftPanel);

        // Right Panel: Details / Releases
        _detailsPanel = new VerticalLayout();
        _detailsPanel.layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT).padding(20);
        _detailsPanel.addChild(new TextWidget(null, "Select a VCS instance from the list to manage releases and settings."d));
        addChild(_detailsPanel);
    }

    private void refreshVCSList()
    {
        _instances = discoverVCS(_repoPath);
        _listAdapter.clear();
        
        VCSInstance[] topLevel = _instances.filter!(i => i.isTopLevel).array;
        VCSInstance[] nested = _instances.filter!(i => !i.isTopLevel).array;

        foreach (inst; topLevel)
        {
            addInstanceToList(inst);
        }

        if (nested.length > 0)
        {
            // Add space between top-level and libs
            _listAdapter.add(""d);
            _listAdapter.add("--- Dependencies / Nested ---"d);
            foreach (inst; nested)
            {
                addInstanceToList(inst);
            }
        }
    }

    private void addInstanceToList(VCSInstance inst)
    {
        dstring label = to!dstring(inst.label);
        if (inst.isIgnored)
        {
            // DlangUI doesn't support strikethrough directly in ListWidget labels easily
            // unless we use custom drawing. For now, we'll mark it with [IGNORED].
            label = "[IGNORED] "d ~ label;
        }
        _listAdapter.add(label);
    }

    private void showVCSDetails(VCSInstance inst)
    {
        _detailsPanel.removeAllChildren();

        TextWidget title = new TextWidget(null, to!dstring(inst.label));
        title.fontSize = 18;
        title.fontWeight = 800;
        _detailsPanel.addChild(title);

        _detailsPanel.addChild(new TextWidget(null, "Path: "d ~ to!dstring(inst.rootPath)));
        _detailsPanel.addChild(new TextWidget(null, "Type: "d ~ to!dstring(inst.type)));

        if (inst.isIgnored)
        {
            TextWidget ignoreMsg = new TextWidget(null, "This provider is currently ignored."d);
            ignoreMsg.textColor = 0x888888;
            _detailsPanel.addChild(ignoreMsg);
        }

        // Releases Section
        VerticalLayout releasesBox = new VerticalLayout();
        releasesBox.layoutWidth(FILL_PARENT).margins(Rect(0, 20, 0, 0)).padding(10).backgroundColor(0x222222);
        
        TextWidget releaseTitle = new TextWidget(null, "Releases"d);
        releaseTitle.fontSize = 14;
        releaseTitle.fontWeight = 700;
        releasesBox.addChild(releaseTitle);

        TextWidget releaseDesc = new TextWidget(null, "Manage software releases. A release is a specific version of your code marked for distribution."d);
        releaseDesc.textColor = 0xAAAAAA;
        releaseDesc.fontSize = 10;
        releasesBox.addChild(releaseDesc);

        HorizontalLayout btnRow = new HorizontalLayout();
        btnRow.margins(Rect(0, 10, 0, 0));

        Button btnViewReleases = new Button(null, "View Releases"d);
        btnViewReleases.click = delegate(Widget w) {
            // In a real app, this would open the provider's release page or a local list
            window.showMessageBox("Releases"d, "Opening releases list..."d);
            return true;
        };
        btnRow.addChild(btnViewReleases);

        Button btnMarkRelease = new Button(null, "Mark New Release"d);
        btnMarkRelease.click = delegate(Widget w) {
            showMarkReleaseDialog(inst);
            return true;
        };
        btnRow.addChild(btnMarkRelease);

        // Winget Support
        if (inst.type == "git")
        {
            Button btnWinget = new Button(null, "Winget Support"d);
            btnWinget.click = delegate(Widget w) {
                showWingetSupportDialog(inst);
                return true;
            };
            btnRow.addChild(btnWinget);
        }

        releasesBox.addChild(btnRow);
        _detailsPanel.addChild(releasesBox);
    }

    private void showWingetSupportDialog(VCSInstance inst)
    {
        // Check if wingetcreate is installed
        bool wingetInstalled = isExecutableInstalled("wingetcreate");
        
        auto dlg = new Dialog(UIString.fromRaw("Winget Support"d), this.window, DialogFlag.Popup | DialogFlag.Resizable);
        dlg.minWidth(500).minHeight(400);
        
        VerticalLayout content = new VerticalLayout();
        content.layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT).padding(20);
        
        content.addChild(new TextWidget(null, "Registering with Microsoft Winget"d).fontSize(16).fontWeight(800));
        
        content.addChild(new TextWidget(null, "\nWinget is the default Windows Package Manager. Registering your app allows users to install it via 'winget install'."d).maxLines(3).layoutWidth(FILL_PARENT));
        
        VerticalLayout statusBox = new VerticalLayout();
        statusBox.margins(Rect(0, 10, 0, 10)).padding(10).backgroundColor(wingetInstalled ? 0x003300 : 0x330000); // Colors as hex
        statusBox.addChild(new TextWidget(null, wingetInstalled ? 
            "✅ wingetcreate tool detected on your system."d : 
            "❌ wingetcreate tool not found in PATH."d));
        content.addChild(statusBox);

        content.addChild(new TextWidget(null, "Helpful Tips:"d).fontWeight(700));
        content.addChild(new TextWidget(null, "• You need a Classic GitHub PAT with 'repo' scope."d));
        content.addChild(new TextWidget(null, "• Use 'wingetcreate token' to store the token locally."d));
        content.addChild(new TextWidget(null, "• For CI/CD, use a Windows-based GitHub Actions runner."d));

        HorizontalLayout btnRow = new HorizontalLayout();
        btnRow.margins(Rect(0, 20, 0, 0));
        
        Button btnDocs = new Button(null, "Open Winget Guide"d);
        btnDocs.click = delegate(Widget w) {
            openUrlInBrowser("https://docs.devcentr.org/general-knowledge/latest/how-to/winget-registration.html");
            return true;
        };
        btnRow.addChild(btnDocs);

        Button btnClose = new Button(null, "Close"d);
        btnClose.click = delegate(Widget w) {
            dlg.close(new Action(2));
            return true;
        };
        btnRow.addChild(btnClose);
        
        content.addChild(btnRow);
        dlg.addChild(content);
        dlg.show();
    }

    private void showMarkReleaseDialog(VCSInstance inst)
    {
        // Placeholder for a dialog that asks for Tag, Title, and Notes.
        window.showMessageBox("Mark Release"d, "Release marking dialog would appear here, allowing input for Tag, Title, and Notes."d);
    }

    private void showIgnoreMenu(int x, int y, VCSInstance inst)
    {
        import dlangui.widgets.popup : PopupAlign;
        MenuItem menuRoot = new MenuItem();
        
        MenuItem ignoreItem = new MenuItem(new Action(1, "Ignore"d));
        
        // Submenu for "store in..."
        MenuItem subMenuRoot = new MenuItem();
        
        Action storeRepo = new Action(10, "repo settings"d);
        Action storeUser = new Action(11, "user settings"d);

        subMenuRoot.add(storeRepo);
        subMenuRoot.add(storeUser);
        
        ignoreItem.add(subMenuRoot);
        menuRoot.add(ignoreItem);
        
        PopupMenu menu = new PopupMenu(menuRoot);
        menu.menuItemAction = delegate(const Action a) {
            if (a.id == 10) {
                ignoreVCS(inst, "repo");
                return true;
            } else if (a.id == 11) {
                ignoreVCS(inst, "user");
                return true;
            }
            return false;
        };
        
        this.window.showPopup(menu, this, PopupAlign.Point | PopupAlign.Right, x, y);
    }

    private void ignoreVCS(VCSInstance inst, string level)
    {
        // Implementation for ignoring and persisting
        window.showMessageBox("Settings"d, "Storing ignore preference for "d ~ to!dstring(inst.label) ~ " in "d ~ to!dstring(level) ~ " settings."d);
        refreshVCSList();
    }

    /// Recursively discover VCS repositories starting from `path`.
    private VCSInstance[] discoverVCS(string path)
    {
        VCSInstance[] results;
        if (!exists(path) || !isDir(path)) return results;

        void scan(string currentPath, bool isFirst)
        {
            bool foundHere;
            string type;
            if (exists(buildPath(currentPath, ".git"))) { foundHere = true; type = "git"; }
            else if (exists(buildPath(currentPath, ".hg"))) { foundHere = true; type = "hg"; }
            else if (exists(buildPath(currentPath, ".svn"))) { foundHere = true; type = "svn"; }

            if (foundHere)
            {
                VCSInstance inst;
                inst.id = currentPath; // Simplified ID
                inst.type = type;
                inst.rootPath = currentPath;
                inst.label = (isFirst ? "Root (" : "") ~ baseName(currentPath) ~ (isFirst ? ")" : "");
                inst.isTopLevel = isFirst;
                inst.isIgnored = false; // TODO: check settings
                results ~= inst;
            }

            // Continue scanning children, but skip hidden dirs like .git itself
            try {
                foreach (entry; dirEntries(currentPath, SpanMode.shallow))
                {
                    if (entry.isDir)
                    {
                        string name = baseName(entry.name);
                        if (name.length > 0 && name[0] != '.')
                        {
                            scan(entry.name, false);
                        }
                    }
                }
            } catch (Exception) {}
        }

        scan(path, true);
        return results;
    }
}
