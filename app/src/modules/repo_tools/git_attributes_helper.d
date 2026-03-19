module modules.repo_tools.git_attributes_helper;

import dlangui;
import dlangui;
import dlangui.dialogs.dialog : Dialog, DialogFlag;
import dlangui.core.events : Action;
import std.file;
import std.path;
import std.conv;
import std.process : environment;
import modules.infra.ui : openUrlInBrowser;

/// Show a dialog listing all potential .gitattributes locations according to Git precedence.
void showGitAttributesLocationsDialog(Window parentWindow, string repoRoot)
{
    auto dlg = new Dialog(UIString.fromRaw(".gitattributes Locations"d), parentWindow,
        DialogFlag.Popup | DialogFlag.Resizable);
    dlg.minWidth(500).minHeight(400);

    auto content = new VerticalLayout();
    content.layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT).padding(15);

    auto header = new TextWidget(null, UIString.fromRaw("Attribute file precedence (highest to lowest):"d));
    header.fontSize(12).fontWeight(700).margins(Rect(0, 0, 0, 10));
    content.addChild(header);

    // Build the list of potential locations
    string[] locations;
    
    // 1. Local .gitattributes (this is what the user clicked on)
    locations ~= buildPath(repoRoot, ".gitattributes");
    
    // 2. Parent directories (simplified, just show one level up if applicable)
    auto parentRepo = dirName(repoRoot);
    if (exists(buildPath(parentRepo, ".gitattributes"))) {
        locations ~= buildPath(parentRepo, ".gitattributes");
    }

    // 3. $GIT_DIR/info/attributes
    locations ~= buildPath(repoRoot, ".git", "info", "attributes");

    // 4. Global config (user)
    string userConfig;
    version(Windows) {
        userConfig = buildPath(environment.get("USERPROFILE"), ".config", "git", "attributes");
        if (!exists(userConfig)) {
            userConfig = buildPath(environment.get("USERPROFILE"), ".gitattributes"); // legacy/alternative
        }
    } else {
        userConfig = buildPath(environment.get("HOME"), ".config", "git", "attributes");
    }
    locations ~= userConfig;

    // 5. System config
    version(Windows) {
        locations ~= "C:\\Program Files\\Git\\etc\\gitattributes";
    } else {
        locations ~= "/etc/gitattributes";
    }

    foreach(path; locations) {
        auto row = new HorizontalLayout();
        row.layoutWidth(FILL_PARENT).padding(5).backgroundColor(exists(path) ? 0x2A3A2A : 0x2A2A2A);
        
        auto label = new TextWidget(null, UIString.fromRaw(to!dstring(path)));
        label.fontSize(10).layoutWidth(FILL_PARENT);
        if (!exists(path)) label.textColor(0x888888);
        row.addChild(label);
        
        if (exists(path)) {
            auto btnOpen = new Button(null, UIString.fromRaw("Edit"d));
            btnOpen.click = delegate(Widget w) {
                // TODO: Open in DevCentr editor
                parentWindow.showMessageBox(UIString.fromRaw("Editor"d), UIString.fromRaw("Opening in editor: "d ~ to!dstring(path)));
                return true;
            };
            row.addChild(btnOpen);
        } else {
            auto btnCreate = new Button(null, UIString.fromRaw("Create"d));
            btnCreate.click = delegate(Widget w) {
                try {
                    auto dir = dirName(path);
                    if (!exists(dir)) mkdirRecurse(dir);
                    std.file.write(path, "# .gitattributes\n");
                    dlg.close(new Action(1));
                    showGitAttributesLocationsDialog(parentWindow, repoRoot); // refresh
                } catch (Exception e) {}
                return true;
            };
            row.addChild(btnCreate);
        }
        
        content.addChild(row);
    }

    auto footer = new TextWidget(null, UIString.fromRaw("Attributes in the same directory as the file have the highest priority."d));
    footer.fontSize(9).textColor(0xAAAAAA).margins(Rect(0, 15, 0, 0));
    content.addChild(footer);

    auto btnClose = new Button(null, UIString.fromRaw("Close"d));
    btnClose.alignment(Align.Right).margins(Rect(0, 10, 0, 0));
    btnClose.click = delegate(Widget w) { dlg.close(new Action(1)); return true; };
    content.addChild(btnClose);

    dlg.addChild(content);
    dlg.show();
}
