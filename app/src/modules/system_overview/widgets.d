module modules.system_overview.widgets;

import dlangui;
import modules.system_overview.tool_manager;
import std.conv : to;
import std.array : join;

class ToolCard : HorizontalLayout {
    this(ToolStatus tool) {
        super("tool_card_" ~ tool.name);
        padding(10).margins(5);
        styleId = "LIST_ITEM"; // Use a list-item style for selection look if needed

        // Icon area
        auto iconContainer = new VerticalLayout();
        iconContainer.minWidth(200).minHeight(200).maxWidth(200).maxHeight(200);
        iconContainer.padding(20).backgroundColor(0x333333); // Fixed size background

        auto icon = new ImageWidget(null, tool.icon);
        icon.layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT);
        iconContainer.addChild(icon);
        addChild(iconContainer);

        // Info area
        auto info = new VerticalLayout();
        info.padding(10).layoutWidth(FILL_PARENT);

        auto name = new TextWidget(null, to!dstring(tool.name));
        name.fontSize(16).fontWeight(800).textColor(0x007AFF);
        info.addChild(name);

        auto loc = new TextWidget(null, to!dstring("Location: " ~ (tool.isInstalled ? tool.installLocation : "Not installed")));
        loc.fontSize(10).textColor(0xAAAAAA);
        info.addChild(loc);

        auto pathInfo = new TextWidget(null, to!dstring("PATH Status: " ~ (tool.onPath ? "On PATH" : "Not on PATH")));
        pathInfo.fontSize(10).textColor(tool.onPath ? 0x00FF00 : 0xFF0000);
        info.addChild(pathInfo);

        if (tool.onPath && tool.pathVariables.length > 0) {
            auto pathVars = new TextWidget(null, to!dstring("Recorded in: " ~ tool.pathVariables.join(", ")));
            pathVars.fontSize(9).textColor(0x888888);
            info.addChild(pathVars);
        }

        // Tech stacks (other than the parent one)
        if (tool.techStacks.length > 1) {
            auto stacksLayout = new HorizontalLayout();
            stacksLayout.padding(2);
            auto stacksLabel = new TextWidget(null, to!dstring("Stacks: " ~ tool.techStacks.join(" \u2022 ")));
            stacksLabel.fontSize(9).textColor(0x666666);
            stacksLayout.addChild(stacksLabel);
            info.addChild(stacksLayout);
        }

        addChild(info);
    }
}

class ToolCategoryExpander : VerticalLayout {
    VerticalLayout _content;
    bool _expanded = true;

    this(string title, ToolStatus[] tools) {
        super();
        layoutWidth(FILL_PARENT);

        auto header = new ImageTextButton(null, "arrow_down", to!dstring(title));
        header.layoutWidth(FILL_PARENT).padding(5).backgroundColor(0x222222);
        addChild(header);

        _content = new VerticalLayout();
        _content.layoutWidth(FILL_PARENT).padding(5);
        foreach(tool; tools) {
            _content.addChild(new ToolCard(tool));
        }
        addChild(_content);

        header.click = delegate(Widget w) {
            _expanded = !_expanded;
            _content.visibility = _expanded ? Visibility.Visible : Visibility.Gone;
            (cast(ImageWidget)header.childById("icon")).drawableId = _expanded ? "arrow_down" : "arrow_right";
            return true;
        };
    }
}

class ToolStatusDashboard : ScrollWidget {
    this(ToolManager mgr, bool installedOnly) {
        super();
        layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT);

        auto content = new VerticalLayout();
        content.layoutWidth(FILL_PARENT);

        auto groups = mgr.getGroupedTools(installedOnly);
        foreach(group; groups) {
            content.addChild(new ToolCategoryExpander(group.name, group.tools));
        }

        contentWidget = content;
    }
}
