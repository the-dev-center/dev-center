module modules.infra.ui;

import dlangui;
import modules.infra.discovery;
import std.conv : to;
import std.array : array, join;
import std.string : indexOf, replace;
import std.path : buildPath;
import std.file : exists, mkdirRecurse, write;

/// DevCentr docs base URL; IaC section path appended for "Open DevCentr docs".
enum devcentrDocsIacPath = "knowledge-base/latest/explanation/infrastructure/iac.html";
enum devcentrDocsBase = "https://docs.devcentr.org/";

/// Opens a URL in the default browser. Returns true if spawn succeeded.
bool openUrlInBrowser(string url)
{
    import std.process : spawnProcess;
    version (Windows)
    {
        return spawnProcess("cmd", ["/c", "start", "\"\"", url]).wait() == 0;
    }
    else version (Posix)
    {
        version (OSX)
            return spawnProcess("open", [url]).wait() == 0;
        else
            return spawnProcess("xdg-open", [url]).wait() == 0;
    }
    else
        return false;
}

/// One list row in the infra tree/list.
enum InfraListItemKind { base, upstream, etc, service }
struct InfraListItem
{
    string label;
    InfraListItemKind kind;
    size_t index;  /// node index for base/upstream/etc, service index for service
}

/// Build flattened list of tree items + services for the left panel.
void buildInfraList(InfraDiscoverySummary summary, ref string[] labels, ref InfraListItem[] items)
{
    labels = [];
    items = [];
    IacScopedNode[] nodes;
    foreach (ref root; summary.scopedIacRoots)
    {
        void addNode(ref IacScopedNode n, int depth)
        {
            nodes ~= n;
            string prefix = depth == 0 ? "Base: " : "  Upstream: ";
            labels ~= prefix ~ n.displayName;
            items ~= InfraListItem(prefix ~ n.displayName, depth == 0 ? InfraListItemKind.base : InfraListItemKind.upstream, nodes.length - 1);
            foreach (ref up; n.upstream)
                addNode(up, depth + 1);
            labels ~= "  [Other services]";
            items ~= InfraListItem("  [Other services]", InfraListItemKind.etc, nodes.length - 1);
        }
        addNode(root, 0);
    }
    foreach (i, svc; summary.services)
    {
        labels ~= "Service: " ~ svc.name;
        items ~= InfraListItem("Service: " ~ svc.name, InfraListItemKind.service, i);
    }
}

/// Right-hand detail panel: service info or etc block or base info.
class InfraDetailPanel : ScrollWidget
{
    VerticalLayout _content;
    InfraDiscoverySummary _summary;
    InfraListItem[] _items;
    size_t _selectedIndex = size_t.max;

    this(InfraDiscoverySummary summary, InfraListItem[] items)
    {
        super();
        layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT);
        _summary = summary;
        _items = items;
        _content = new VerticalLayout();
        _content.layoutWidth(FILL_PARENT).padding(10);
        contentWidget = _content;
        showPlaceholder();
    }

    void showPlaceholder()
    {
        _content.removeAllChildren();
        auto t = new TextWidget(null, to!dstring("Select an item from the list."));
        t.textColor(0x888888);
        _content.addChild(t);
    }

    void showSelection(size_t itemIndex)
    {
        if (itemIndex >= _items.length) { showPlaceholder(); return; }
        _selectedIndex = itemIndex;
        auto item = _items[itemIndex];
        _content.removeAllChildren();

        final switch (item.kind)
        {
            case InfraListItemKind.base:
            case InfraListItemKind.upstream:
                showNodeDetail(item.index);
                break;
            case InfraListItemKind.etc:
                showEtcDetail(item.index);
                break;
            case InfraListItemKind.service:
                showServiceDetail(item.index);
                break;
        }
    }

    private void showNodeDetail(size_t nodeIndex)
    {
        size_t idx = 0;
        foreach (ref root; _summary.scopedIacRoots)
        {
            bool found;
            IacScopedNode* n = findNodeByFlatIndex(root, nodeIndex, idx, found);
            if (found && n !is null)
            {
                _content.addChild(new TextWidget(null, to!dstring("IaC base: " ~ n.displayName)));
                _content.addChild(new TextWidget(null, to!dstring("Path: " ~ n.basePath)));
                auto files = new TextWidget(null, to!dstring("Config files: " ~ (n.base.configFiles.length ? join(", ", n.base.configFiles) : "none")));
                files.maxLines = 20;
                _content.addChild(files);
                break;
            }
        }
    }

    private IacScopedNode* findNodeByFlatIndex(ref IacScopedNode node, size_t target, ref size_t cur, ref bool found)
    {
        if (cur == target) { found = true; return &node; }
        cur++;
        foreach (ref up; node.upstream)
        {
            IacScopedNode* p = findNodeByFlatIndex(up, target, cur, found);
            if (found) return p;
        }
        return null;
    }

    private void showEtcDetail(size_t nodeIndex)
    {
        size_t idx = 0;
        foreach (ref root; _summary.scopedIacRoots)
        {
            bool found;
            IacScopedNode* n = findNodeByFlatIndex(root, nodeIndex, idx, found);
            if (found && n !is null)
            {
                _content.addChild(new TextWidget(null, to!dstring(n.etcBlock.label)));
                auto desc = new TextWidget(null, to!dstring(n.etcBlock.description));
                desc.maxLines = 10;
                _content.addChild(desc);
                auto btn = new Button(null, to!dstring("Load more (may take a long time)"));
                btn.click = delegate(Widget w) {
                    // Placeholder: could trigger broader scan
                    return true;
                };
                _content.addChild(btn);
                break;
            }
        }
    }

    private void showServiceDetail(size_t serviceIndex)
    {
        if (serviceIndex >= _summary.services.length) return;
        auto svc = _summary.services[serviceIndex];
        _content.addChild(new TextWidget(null, to!dstring(svc.name)));
        auto desc = new TextWidget(null, to!dstring(svc.shortDescription));
        desc.maxLines = 10;
        _content.addChild(desc);
        if (svc.homepage.length > 0)
        {
            auto btnHome = new Button(null, to!dstring("Open homepage"));
            btnHome.click = delegate(Widget w) { openUrlInBrowser(svc.homepage); return true; };
            _content.addChild(btnHome);
        }
        if (svc.docs.length > 0)
        {
            auto btnDocs = new Button(null, to!dstring("Open docs"));
            btnDocs.click = delegate(Widget w) { openUrlInBrowser(svc.docs); return true; };
            _content.addChild(btnDocs);
        }
        auto btnDevcentr = new Button(null, to!dstring("Open DevCentr docs"));
        string url = devcentrDocsBase ~ devcentrDocsIacPath;
        if (svc.devcentrDoc.length > 0 && svc.devcentrDoc.canFind("infrastructure/"))
        {
            auto start = indexOf(svc.devcentrDoc, "infrastructure/");
            if (start >= 0)
            {
                auto sub = svc.devcentrDoc[start .. $];
                if (sub.canFind(".adoc"))
                    url = devcentrDocsBase ~ "knowledge-base/latest/explanation/" ~ replace(replace(sub, ".adoc[]", ".html"), "[]", "");
            }
        }
        btnDevcentr.click = delegate(Widget w) { openUrlInBrowser(url); return true; };
        _content.addChild(btnDevcentr);
        auto installBtn = new Button(null, to!dstring(svc.cliInstalled ? "Manage install" : "Install"));
        installBtn.click = delegate(Widget w) {
            // Placeholder: launch install flow for this service
            return true;
        };
        _content.addChild(installBtn);
    }
}

/// Main Infra discovery panel: left list (tree + services), right detail.
class InfraDiscoveryPanel : HorizontalLayout
{
    ListWidget _list;
    StringListAdapter _adapter;
    InfraDetailPanel _detailPanel;
    InfraDiscoverySummary _summary;
    InfraListItem[] _items;

    this(InfraDiscoverySummary summary)
    {
        super("infra_panel");
        layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT);
        _summary = summary;
        string[] labels;
        buildInfraList(summary, labels, _items);
        _adapter = new StringListAdapter();
        foreach (l; labels)
            _adapter.add(to!dstring(l));

        _list = new ListWidget(null);
        _list.layoutWidth(300).layoutHeight(FILL_PARENT);
        _list.adapter = _adapter;
        addChild(_list);

        _detailPanel = new InfraDetailPanel(summary, _items);
        _detailPanel.layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT);
        addChild(_detailPanel);

        _list.itemClick = delegate(Widget w, int index) {
            if (index >= 0 && index < cast(int)_items.length)
                _detailPanel.showSelection(cast(size_t)index);
            return true;
        };
    }

}

/// Overload: build list and fill adapter + items.
void buildInfraList(InfraDiscoverySummary summary, ref StringListAdapter adapter, ref InfraListItem[] items)
{
    string[] labels;
    buildInfraList(summary, labels, items);
    adapter.clear();
    foreach (l; labels)
        adapter.add(to!dstring(l));
}
