module app.src.modules.repo_tools.git_gui_dialog;

import dlangui;
import modules.repo_tools.git_viewers;
import modules.repo_tools.registry;
import modules.infra.ui : openUrlInBrowser;
import std.conv : to;
import std.process : spawnProcess;
import std.path : baseName;

/// Show a dialog that lets the user pick from installed Git GUIs.
/// After the user clicks a viewer, it is launched and registered with the
/// RepoToolsRegistry for the given repo.
void showGitGuiSelectorDialog(Window parentWindow, string repoRoot, RepoToolsRegistry repoTools)
{
    auto viewers = detectInstalledViewers();

    auto dlg = new Dialog(UIString.fromRaw("Open Git Viewer"d), parentWindow,
        DialogFlag.Popup | DialogFlag.Resizable);
    dlg.minWidth(420).minHeight(320);

    auto content = new VerticalLayout();
    content.layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT).padding(15);

    // Header
    auto header = new TextWidget(null, UIString.fromRaw("Choose a Git Viewer"d));
    header.fontSize(14).fontWeight(700).margins(Rect(0, 0, 0, 10));
    content.addChild(header);

    auto repoLabel = new TextWidget(null, UIString.fromRaw("Repo: "d ~ to!dstring(baseName(repoRoot))));
    repoLabel.fontSize(10).textColor(0xAAAAAA).margins(Rect(0, 0, 0, 15));
    content.addChild(repoLabel);

    // Grid of viewers — vertical list of buttons with icons
    auto grid = new VerticalLayout();
    grid.layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT);

    foreach (viewer; viewers)
    {
        auto row = new HorizontalLayout();
        row.layoutWidth(FILL_PARENT).padding(8).margins(Rect(0, 2, 0, 2)).backgroundColor(0x252525);

        // Icon placeholder (use tool icon if available)
        auto icon = new TextWidget(null, UIString.fromRaw("⚙"d));
        icon.fontSize(16).minWidth(32).alignment(Alignment.Center);
        row.addChild(icon);

        auto label = new TextWidget(null, UIString.fromRaw(to!dstring(viewer.label)));
        label.fontSize(12).layoutWidth(FILL_PARENT).padding(4);
        row.addChild(label);

        auto btn = new Button(null, UIString.fromRaw("Open"d));

        // Capture viewer by value for the delegate
        auto viewerId = viewer.id;
        auto viewerLabel = viewer.label;
        auto viewerKind = viewer.kind;
        auto viewerExe = viewer.executable;

        btn.click = delegate(Widget w) {
            if (viewerKind == GitViewerType.builtin)
            {
                import modules.repo_tools.git_viewer_widget;
                auto viewer = new GitViewerWindow(repoRoot);
                viewer.show();
            }
            else
            {
                // Launch external viewer
                try
                {
                    auto pid = spawnProcess([viewerExe, repoRoot]);
                    import std.datetime : Clock;

                    // Register with RepoToolsRegistry
                    ToolInstance inst;
                    inst.id = viewerId ~ "-" ~ to!string(pid.processID);
                    inst.repoRoot = repoRoot;
                    inst.kind = ToolKind.externalApp;
                    inst.label = viewerLabel;
                    inst.icon = viewerId;
                    inst.pid = pid.processID;
                    inst.executable = viewerExe;
                    inst.startedAt = Clock.currTime;
                    inst.lastSeenAliveAt = Clock.currTime;
                    repoTools.registerOrUpdateInstance(inst);
                }
                catch (Exception e)
                {
                    parentWindow.showMessageBox(
                        UIString.fromRaw("Error"d),
                        UIString.fromRaw("Failed to launch "d ~ to!dstring(viewerLabel) ~ ": "d ~ to!dstring(e.msg)));
                }
            }
            dlg.close(DialogActions.Accept);
            return true;
        };

        row.addChild(btn);
        grid.addChild(row);
    }

    auto scroll = new ScrollWidget();
    scroll.layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT);
    scroll.contentWidget = grid;
    content.addChild(scroll);

    // Footer link to git-guis.adoc article
    auto linkRow = new HorizontalLayout();
    linkRow.layoutWidth(FILL_PARENT).margins(Rect(0, 10, 0, 0));

    auto linkBtn = new Button(null, UIString.fromRaw("Browse more Git GUIs →"d));
    linkBtn.click = delegate(Widget w) {
        openUrlInBrowser("https://docs.devcentr.org/knowledge-base/latest/reference/git-guis.html");
        return true;
    };
    linkRow.addChild(linkBtn);
    content.addChild(linkRow);

    dlg.addChild(content);
    dlg.show();
}
