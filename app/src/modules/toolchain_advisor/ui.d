module modules.toolchain_advisor.ui;

import dlangui;
import dlangui.graphics.drawbuf : DrawBuf;
import modules.toolchain_advisor.model;
import modules.toolchain_advisor.sdl_parser : loadAdvisorCatalogFromSdl;
import modules.infra.ui : openUrlInBrowser;
import std.conv : to;
import std.path : buildPath, dirName;
import std.file : exists, getcwd, thisExePath;

private enum BoxStyle {
    bg = 0x252525,
    border = 0x333333,
    accent = 0x007AFF,
    muted = 0xAAAAAA,
    connector = 0x555555,
}

/// Narrow vertical connector between step boxes.
class FlowConnector : Widget
{
    this()
    {
        super("flowConnector");
        minWidth(24).maxWidth(24).layoutHeight(FILL_PARENT);
    }

    override void onDraw(DrawBuf buf)
    {
        super.onDraw(buf);
        Rect rc = _pos;
        if (rc.empty)
            return;
        int cx = rc.left + rc.width / 2;
        int y1 = rc.top + rc.height / 3;
        int y2 = rc.top + 2 * rc.height / 3;
        buf.fillRect(Rect(cx - 1, y1, cx + 1, y2), BoxStyle.connector);
        buf.fillRect(Rect(cx - 4, y2 - 2, cx + 4, y2 + 2), BoxStyle.connector);
    }
}

/// One decision step: title, searchable list, selection state.
class DecisionStepBox : VerticalLayout
{
    AdvisorStep _step;
    EditLine _filter;
    ListWidget _list;
    StringListAdapter _adapter;
    AdvisorOption[] _visibleOptions;
    string _selectedId;
    void delegate(string stepId, string optionId) _onChange;
    void delegate(string stepId) _onFocus;

    string stepId() const @safe { return _step.id; }
    string selectedOptionId() const @safe { return _selectedId; }

    this(AdvisorStep step, void delegate(string stepId, string optionId) onChange,
         void delegate(string stepId) onFocus = null)
    {
        super("step_" ~ step.id);
        _step = step;
        _onChange = onChange;
        _onFocus = onFocus;
        layoutWidth(WRAP_CONTENT).minWidth(220).maxWidth(280).padding(12);
        backgroundColor(BoxStyle.bg).margins(Rect(0, 4, 0, 4));

        auto title = new TextWidget(null, to!dstring(step.title));
        title.fontSize(11).fontWeight(700).textColor(BoxStyle.accent);
        addChild(title);

        if (step.hint.length > 0)
        {
            auto hint = new TextWidget(null, to!dstring(step.hint));
            hint.fontSize(8).textColor(BoxStyle.muted).margins(Rect(0, 4, 0, 6));
            addChild(hint);
        }

        _filter = new EditLine("filter_" ~ step.id, ""d);
        _filter.layoutWidth(FILL_PARENT).margins(Rect(0, 0, 0, 4));
        addChild(_filter);

        _adapter = new StringListAdapter();
        _list = new ListWidget("list_" ~ step.id);
        _list.layoutWidth(FILL_PARENT).minHeight(140).maxHeight(180);
        _list.adapter = _adapter;
        addChild(_list);

        refreshList("");
        if (step.options.length > 0)
            selectByIndex(0);

        _filter.contentChange = delegate(EditableContent content) {
            refreshList(to!string(_filter.text));
        };

        _list.itemClick = delegate(Widget source, int itemIndex) {
            if (itemIndex >= 0)
                selectByIndex(itemIndex);
            if (_onFocus !is null)
                _onFocus(_step.id);
            return true;
        };
    }

    void refreshList(string query)
    {
        _adapter.clear();
        _visibleOptions = [];
        string q = query;
        foreach (opt; _step.options)
        {
            import std.algorithm : canFind;
            import std.string : toLower;
            if (q.length == 0 || toLower(opt.label).canFind(toLower(q)) || toLower(opt.id).canFind(toLower(q)))
            {
                _visibleOptions ~= opt;
                _adapter.add(to!dstring(opt.label));
            }
        }
        // Keep the committed selection. Filtering must not silently re-select
        // index 0 (that broke Primary language: highlight ≠ advice).
        int keep = -1;
        foreach (i, opt; _visibleOptions)
        {
            if (opt.id == _selectedId)
            {
                keep = cast(int)i;
                break;
            }
        }
        if (keep >= 0)
            _list.selectedItemIndex = keep;
    }

    void selectByIndex(int listIndex)
    {
        if (listIndex < 0 || listIndex >= cast(int)_visibleOptions.length)
            return;
        _selectedId = _visibleOptions[listIndex].id;
        _list.selectedItemIndex = listIndex;
        if (_onChange !is null)
            _onChange(_step.id, _selectedId);
    }
}

/// Right-hand context: overview, timeline, alternates, ranked guidance.
class OptionContextPanel : ScrollWidget
{
    VerticalLayout _content;
    AdvisorCatalog _catalog;
    string[string] _selections;
    string _focusStepId;

    this(AdvisorCatalog catalog)
    {
        super("optionContextPanel");
        layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT);
        _catalog = catalog;
        _content = new VerticalLayout();
        _content.layoutWidth(FILL_PARENT).padding(12);
        contentWidget = _content;
        showPlaceholder();
    }

    void update(string focusStepId, string[string] selections)
    {
        _focusStepId = focusStepId;
        _selections = selections;
        refresh();
    }

    void showPlaceholder()
    {
        _content.removeAllChildren();
        auto t = new TextWidget(null,
            "Select an option in any step to see its history, comparisons, and how it relates to alternates."d);
        t.textColor(BoxStyle.muted).fontSize(9);
        _content.addChild(t);
    }

    private void refresh()
    {
        _content.removeAllChildren();
        if (_focusStepId.length == 0 || _focusStepId !in _selections)
        {
            showPlaceholder();
            return;
        }

        auto opt = findOption(_catalog, _focusStepId, _selections[_focusStepId]);
        if (opt.id.length == 0)
        {
            showPlaceholder();
            return;
        }

        auto head = new TextWidget(null, to!dstring(opt.label));
        head.fontSize(13).fontWeight(800).textColor(BoxStyle.accent);
        _content.addChild(head);

        if (opt.era.length > 0)
        {
            auto era = new TextWidget(null, to!dstring("Era: " ~ opt.era));
            era.fontSize(8).textColor(0x88AA88).margins(Rect(0, 2, 0, 6));
            _content.addChild(era);
        }

        if (opt.overview.length > 0)
        {
            auto overviewHead = new TextWidget(null, "Overview"d);
            overviewHead.fontSize(10).fontWeight(700).margins(Rect(0, 4, 0, 2));
            _content.addChild(overviewHead);
            auto overview = new TextWidget(null, to!dstring(opt.overview));
            overview.fontSize(9).textColor(0xCCCCCC).margins(Rect(0, 0, 0, 8));
            _content.addChild(overview);
        }

        if (opt.timeline.length > 0)
        {
            auto tlHead = new TextWidget(null, "Timeline"d);
            tlHead.fontSize(10).fontWeight(700).textColor(BoxStyle.accent).margins(Rect(0, 8, 0, 4));
            _content.addChild(tlHead);
            foreach (m; opt.timeline)
            {
                auto period = new TextWidget(null, to!dstring(m.period ~ " — " ~ m.title));
                period.fontSize(9).fontWeight(600).textColor(0xBBBBBB);
                _content.addChild(period);
                auto sum = new TextWidget(null, to!dstring(m.summary));
                sum.fontSize(8).textColor(BoxStyle.muted).margins(Rect(0, 0, 0, 6));
                _content.addChild(sum);
            }
        }

        if (opt.alternates.length > 0)
        {
            auto altHead = new TextWidget(null, "Compare alternates"d);
            altHead.fontSize(10).fontWeight(700).textColor(BoxStyle.accent).margins(Rect(0, 10, 0, 4));
            _content.addChild(altHead);
            foreach (alt; opt.alternates)
            {
                auto box = new VerticalLayout();
                box.layoutWidth(FILL_PARENT).padding(8).backgroundColor(0x1E1E1E).margins(Rect(0, 0, 0, 6));
                string vsLabel = alt.title.length > 0 ? alt.title : ("vs " ~ alt.versus);
                box.addChild(new TextWidget(null, to!dstring(vsLabel)).fontSize(9).fontWeight(700));
                if (alt.summary.length > 0)
                    box.addChild(new TextWidget(null, to!dstring(alt.summary)).fontSize(8).textColor(0xAAAAAA));
                if (alt.preferWhen.length > 0)
                    box.addChild(new TextWidget(null, to!dstring("Prefer when: " ~ alt.preferWhen)).fontSize(8).textColor(0x888888));
                if (alt.problemsSolved.length > 0)
                    box.addChild(new TextWidget(null, to!dstring("Addresses: " ~ alt.problemsSolved)).fontSize(8).textColor(0x88AA88));
                _content.addChild(box);
            }
        }

        appendRankedGuidance();
    }

    private void appendRankedGuidance()
    {
        auto ranked = rankRecommendations(_catalog.recommendations, _selections);
        auto best = pickBestRecommendation(ranked);

        auto sep = new TextWidget(null, "Guidance for full selection"d);
        sep.fontSize(10).fontWeight(700).textColor(BoxStyle.muted).margins(Rect(0, 14, 0, 4));
        _content.addChild(sep);

        auto title = new TextWidget(null, to!dstring(best.title));
        title.fontSize(11).fontWeight(700).textColor(BoxStyle.accent);
        _content.addChild(title);

        auto summary = new TextWidget(null, to!dstring(best.summary));
        summary.fontSize(9).textColor(0xCCCCCC).margins(Rect(0, 4, 0, 0));
        _content.addChild(summary);

        if (best.docs.length > 0)
        {
            auto btnDocs = new Button(null, "Read docs"d);
            btnDocs.margins(Rect(0, 8, 0, 0));
            btnDocs.click = delegate(Widget w) {
                openUrlInBrowser(best.docs);
                return true;
            };
            _content.addChild(btnDocs);
        }
    }
}

/// Decision flow (left) + context panel (right).
class ToolchainAdvisorPanel : VerticalLayout
{
    AdvisorCatalog _catalog;
    DecisionStepBox[] _boxes;
    OptionContextPanel _contextPanel;
    string[string] _selections;
    string _focusStepId;

    this(AdvisorCatalog catalog)
    {
        super("toolchainAdvisorPanel");
        layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT).padding(10);
        _catalog = catalog;

        if (_catalog.steps.length == 0)
        {
            addChild(new TextWidget(null, "Toolchain advisor definitions not found."d).textColor(BoxStyle.muted));
            return;
        }

        auto intro = new TextWidget(null,
            "Pick options in each step (left). History, comparisons, and guidance appear in the context panel (right)."d);
        intro.fontSize(9).textColor(BoxStyle.muted).margins(Rect(0, 0, 0, 8));
        addChild(intro);

        auto split = new HorizontalLayout();
        split.layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT);

        auto leftCol = new VerticalLayout();
        leftCol.layoutWidth(WRAP_CONTENT).layoutHeight(FILL_PARENT).minWidth(400);

        auto flowScroll = new ScrollWidget();
        flowScroll.layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT);

        auto flowRow = new HorizontalLayout();
        flowRow.layoutWidth(WRAP_CONTENT).padding(4);

        foreach (i, step; _catalog.steps)
        {
            if (i > 0)
                flowRow.addChild(new FlowConnector());
            auto box = new DecisionStepBox(step, &onStepChanged, &onStepFocused);
            _boxes ~= box;
            flowRow.addChild(box);
        }

        flowScroll.contentWidget = flowRow;
        leftCol.addChild(flowScroll);
        split.addChild(leftCol);

        _contextPanel = new OptionContextPanel(_catalog);
        _contextPanel.layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT).minWidth(320);
        split.addChild(_contextPanel);

        addChild(split);

        rebuildSelectionsFromBoxes();
        if (_catalog.steps.length > 0)
        {
            _focusStepId = _catalog.steps[0].id;
            refreshContext();
        }
    }

    static AdvisorCatalog loadCatalog(string sdlPath, string jsonFallbackPath)
    {
        auto catalog = loadAdvisorCatalogFromSdl(sdlPath);
        if (catalog.steps.length > 0)
            return catalog;
        return loadAdvisorCatalog(jsonFallbackPath);
    }

    static string bundledFallbackSdlPath()
    {
        string p = buildPath(getcwd(), "src", "modules", "toolchain_advisor", "fallback-advisor.sdl");
        if (exists(p))
            return p;
        return buildPath(dirName(thisExePath()), "fallback-advisor.sdl");
    }

    static string bundledFallbackJsonPath()
    {
        string p = buildPath(getcwd(), "src", "modules", "toolchain_advisor", "fallback-advisor.json");
        if (exists(p))
            return p;
        return buildPath(dirName(thisExePath()), "fallback-advisor.json");
    }

    private void onStepChanged(string stepId, string optionId)
    {
        _selections[stepId] = optionId;
        _focusStepId = stepId;
        refreshContext();
    }

    private void onStepFocused(string stepId)
    {
        _focusStepId = stepId;
        refreshContext();
    }

    private void rebuildSelectionsFromBoxes()
    {
        _selections = null;
        foreach (box; _boxes)
            _selections[box.stepId()] = box.selectedOptionId();
    }

    private void refreshContext()
    {
        // DecisionStepBox fires its change callback while it is being
        // constructed (selectByIndex in its ctor), which reaches here before
        // _contextPanel is created. Skip until the panel exists; the explicit
        // refreshContext() after construction performs the real initial update.
        if (_contextPanel is null)
            return;
        _contextPanel.update(_focusStepId, _selections);
    }
}
