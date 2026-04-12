module modules.vcs.git_performance_dialog;

import dlangui;
import dlangui.dialogs.dialog : Dialog, DialogFlag;
import std.process : execute, Config;
import std.string : strip;
import std.conv : to;
import modules.infra.ui : openUrlInBrowser;

/// Show a dialog focused on Git performance settings (FSMonitor).
void showGitPerformanceDialog(Window parentWindow)
{
    auto dlg = new Dialog(UIString.fromRaw("Git Performance Settings"d), parentWindow,
        DialogFlag.Popup | DialogFlag.Resizable);
    dlg.minWidth(600).minHeight(500);

    auto content = new VerticalLayout();
    content.layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT).padding(20);

    // Header
    auto head = new TextWidget(null, "Built-in Filesystem Monitor"d);
    head.fontSize(16).fontWeight(700).margins(Rect(0, 0, 0, 10));
    content.addChild(head);

    auto desc = new TextWidget(null, "Git can use a background daemon to monitor the filesystem for changes, which dramatically speeds up status checks in large repositories."d);
    desc.maxLines(3).layoutWidth(FILL_PARENT).margins(Rect(0, 0, 0, 15));
    content.addChild(desc);

    // Status Section
    auto statusBox = new VerticalLayout();
    statusBox.layoutWidth(FILL_PARENT).padding(10).backgroundColor(0x1B1B1B);
    
    auto checkGlobalStatus() {
        auto res = execute(["git", "config", "--global", "core.fsmonitor"]);
        return res.status == 0 && res.output.strip == "true";
    }

    bool isEnabled = checkGlobalStatus();

    auto statusText = new TextWidget("fsmonitor_status", UIString.fromRaw(isEnabled ? "✅ Global FSMonitor is ENABLED"d : "❌ Global FSMonitor is NOT enabled"d));
    statusText.textColor(isEnabled ? 0x88CC88 : 0xCCAA66).fontWeight(700);
    statusBox.addChild(statusText);
    content.addChild(statusBox);

    // Warnings
    auto warnHeader = new TextWidget(null, "\nTechnical & Security Considerations:"d);
    warnHeader.fontWeight(700).margins(Rect(0, 10, 0, 5));
    content.addChild(warnHeader);

    auto warnings = new TextWidget(null, "• Spawns background processes (git-fsmonitor--daemon).\n"d ~
                                  "• May hang or fail on Network/Shared drives.\n"d ~
                                  "• Rare security risk in maliciously crafted repositories.\n"d ~
                                  "• Cleanup: Old Git versions may leave orphaned processes on Windows."d);
    warnings.fontSize(10).textColor(0xBBBBBB).layoutWidth(FILL_PARENT);
    content.addChild(warnings);

    // Actions
    HorizontalLayout btnRow = new HorizontalLayout();
    btnRow.margins(Rect(0, 20, 0, 0));

    auto btnToggle = new Button(null, UIString.fromRaw(isEnabled ? "Disable Globally"d : "Enable Globally"d));
    btnToggle.click = delegate(Widget w) {
        if (!isEnabled) {
            execute(["git", "config", "--global", "core.fsmonitor", "true"]);
            execute(["git", "config", "--global", "--unset-all", "core.useBuiltinFSMonitor"]);
        } else {
            execute(["git", "config", "--global", "--unset-all", "core.fsmonitor"]);
        }
        dlg.close(new Action(1));
        showGitPerformanceDialog(parentWindow); // Refresh
        return true;
    };
    btnRow.addChild(btnToggle);

    auto btnDocs = new Button(null, "Read Full Guide →"d);
    btnDocs.click = delegate(Widget w) {
        openUrlInBrowser("https://docs.devcentr.org/general-knowledge/latest/reference/git-performance.html");
        return true;
    };
    btnRow.addChild(btnDocs);

    auto btnClose = new Button(null, "Close"d);
    btnClose.click = delegate(Widget w) { dlg.close(new Action(2)); return true; };
    btnRow.addChild(btnClose);

    content.addChild(btnRow);
    dlg.addChild(content);
    dlg.show();
}
