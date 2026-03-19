/// Gitignore viewer: editor with minimap, technology tree, and template comparison.
module modules.repo_tools.gitignore_viewer_widget;

import dlangui;
import std.file : exists, readText, write;
import std.path : buildPath;
import std.conv : to;
import std.string : splitLines, strip, toLower;
import std.algorithm : canFind, map;
import std.array : array;

import modules.repo_tools.minimap_widget;
import modules.repo_tools.gitignore_model;
import modules.repo_tools.devcentr_sdl;
import modules.repo_tools.gitignore_template_sources;
import modules.template_installer.installer;

/// Main gitignore viewer widget. Layout: minimap | editor | (model tree + template comparison).
class GitignoreViewerWidget : VerticalLayout
{
    string _repoRoot;
    string _gitignorePath;
    TemplateInstaller _installer;
    string _content;

    EditBox _editor;
    MinimapWidget _minimap;
    ListWidget _techList;
    TabWidget _templateTabs;
    ScrollWidget _devcentrPanel, _githubPanel, _localPanel;
    StringListAdapter _techAdapter;
    RecognizedTech[] _techs;

    this(string repoRoot, TemplateInstaller installer)
    {
        super();
        _repoRoot = repoRoot;
        _installer = installer;
        _gitignorePath = buildPath(repoRoot, ".gitignore");
        layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT);

        _content = exists(_gitignorePath) ? readText(_gitignorePath) : "# .gitignore\n";

        auto mainRow = new HorizontalLayout();
        mainRow.layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT);

        _minimap = new MinimapWidget();
        _minimap.setText(_content);
        _minimap.setVisibleRegion(0f, 0.3f);
        _minimap.onScrollRequested(delegate(float r) {
            if (_editor) {
                auto lines = _content.splitLines();
                int targetLine = cast(int)(r * lines.length);
                if (targetLine >= 0 && targetLine < lines.length)
                    scrollEditorToLine(targetLine);
            }
        });
        mainRow.addChild(_minimap);

        _editor = new EditBox("gitignore_editor", to!dstring(_content));
        _editor.layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT);
        _editor.contentChange = delegate(EditableContent ec) {
            _content = to!string(_editor.text);
            _minimap.setText(_content);
            refreshTechTree();
        };
        mainRow.addChild(_editor);

        auto rightPanel = new VerticalLayout();
        rightPanel.layoutWidth(280).layoutHeight(FILL_PARENT);

        auto techLabel = new TextWidget(null, "Technologies"d);
        techLabel.fontSize(10).fontWeight(600);
        rightPanel.addChild(techLabel);

        _techAdapter = new StringListAdapter();
        _techList = new ListWidget("tech_list");
        _techList.layoutWidth(FILL_PARENT).layoutHeight(120);
        _techList.adapter = _techAdapter;
        _techList.itemClick = delegate(Widget w, int idx) {
            if (idx >= 0 && idx < _techs.length)
                highlightTechLines(_techs[idx]);
            return true;
        };
        rightPanel.addChild(_techList);

        auto templateLabel = new TextWidget(null, "Template comparison"d);
        templateLabel.fontSize(10).fontWeight(600).margins(Rect(0, 10, 0, 5));
        rightPanel.addChild(templateLabel);

        _templateTabs = new TabWidget();
        _templateTabs.layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT);

        _devcentrPanel = new ScrollWidget();
        _devcentrPanel.layoutWidth(FILL_PARENT).layoutHeight(150);
        _devcentrPanel.contentWidget = buildTemplateComparisonPanel(GitIgnoreSource.DevCentr);

        _githubPanel = new ScrollWidget();
        _githubPanel.layoutWidth(FILL_PARENT).layoutHeight(150);
        _githubPanel.contentWidget = buildTemplateComparisonPanel(GitIgnoreSource.GitHub);

        _localPanel = new ScrollWidget();
        _localPanel.layoutWidth(FILL_PARENT).layoutHeight(150);
        _localPanel.contentWidget = buildTemplateComparisonPanel(GitIgnoreSource.Local);

        _templateTabs.addTab(_devcentrPanel, "DevCentr"d);
        _templateTabs.addTab(_githubPanel, "GitHub"d);
        _templateTabs.addTab(_localPanel, "Local"d);

        rightPanel.addChild(_templateTabs);
        mainRow.addChild(rightPanel);

        layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT);
        addChild(mainRow);
        refreshTechTree();
    }

    private Widget buildTemplateComparisonPanel(GitIgnoreSource source)
    {
        auto layout = new VerticalLayout();
        layout.layoutWidth(FILL_PARENT).padding(5);

        string[] templateLines;
        string templateContent = getTemplateContentForSelectedTech(source);
        if (templateContent.length > 0)
        {
            auto projectLines = _content.splitLines().map!(l => l.strip()).array;
            auto suppressions = loadGitignoreSuppressions(_repoRoot);

            foreach (line; templateContent.splitLines())
            {
                auto stripped = line.strip();
                if (stripped.length == 0) continue;

                bool inProject = projectLines.canFind(stripped);
                bool suppressed = suppressions.canFind(stripped);

                auto row = new HorizontalLayout();
                row.layoutWidth(FILL_PARENT).padding(2);

                auto txt = new TextWidget(null, to!dstring(stripped));
                if (!inProject && !suppressed)
                {
                    txt.textColor(0xFF6666);
                }
                else if (!inProject && suppressed)
                {
                    txt.textColor(0x888888);
                }
                else
                {
                    txt.textColor(0xCCCCCC);
                }

                row.addChild(txt);

                if (!inProject && !suppressed)
                {
                    auto btn = new Button(null, "Suppress"d);
                    btn.fontSize(8);
                    string lineCopy = stripped;
                    btn.click = delegate(Widget w) {
                        addGitignoreSuppression(_repoRoot, lineCopy);
                        refreshTemplatePanels();
                        return true;
                    };
                    row.addChild(btn);
                }

                layout.addChild(row);
            }
        }
        else
        {
            auto hint = new TextWidget(null, "Select a technology above or choose a template source."d);
            hint.textColor(0x888888);
            layout.addChild(hint);
        }

        return layout;
    }

    private string getTemplateContentForSelectedTech(GitIgnoreSource source)
    {
        int idx = _techList.selectedItemIndex;
        if (idx < 0 || idx >= _techs.length) return "";

        string techName = _techs[idx].name;

        final switch (source)
        {
            case GitIgnoreSource.DevCentr:
                auto path = buildPath(_installer.cachePath, "repo", "workspaces");
                auto ecoPath = buildPath(path, toLower(techName), ".gitignore");
                if (exists(ecoPath)) return readText(ecoPath);
                return "";

            case GitIgnoreSource.GitHub:
                if (!_installer.ensureGitHubGitIgnoreCache()) return "";
                auto ghTemplates = listFromGitHub(_installer.githubGitIgnorePath);
                foreach (t; ghTemplates)
                {
                    if (toLower(t.name) == toLower(techName))
                        return readTemplateContent(t.path);
                }
                return "";

            case GitIgnoreSource.Local:
                return "";
        }
    }

    private void refreshTechTree()
    {
        _techs = parseTechnologies(_content);
        _techAdapter.clear();
        foreach (t; _techs)
            _techAdapter.add(to!dstring(t.name ~ " (" ~ to!string(t.lineIndices.length) ~ ")"));
    }

    private void highlightTechLines(RecognizedTech tech)
    {
        import dlangui.core.editable : TextRange, TextPosition;
        if (!_editor || tech.lineIndices.length == 0) return;

        auto lines = _content.splitLines();
        int firstLine = tech.lineIndices[0];
        if (firstLine >= lines.length) return;

        int lastLine = tech.lineIndices[$ - 1];
        if (lastLine >= lines.length) lastLine = cast(int)lines.length - 1;

        int endPos = cast(int)lines[lastLine].length;

        _editor.setCaretPos(firstLine, 0);
        _editor.selectionRange = TextRange(TextPosition(firstLine, 0), TextPosition(lastLine, endPos));
    }

    private void scrollEditorToLine(int lineIndex)
    {
        auto lines = _content.splitLines();
        if (lineIndex >= lines.length) return;
        _editor.setCaretPos(lineIndex, 0);
    }

    private void refreshTemplatePanels()
    {
        _devcentrPanel.contentWidget = buildTemplateComparisonPanel(GitIgnoreSource.DevCentr);
        _githubPanel.contentWidget = buildTemplateComparisonPanel(GitIgnoreSource.GitHub);
        _localPanel.contentWidget = buildTemplateComparisonPanel(GitIgnoreSource.Local);
    }

    /// Save current content to .gitignore.
    void save()
    {
        write(_gitignorePath, to!string(_editor.text));
        _content = to!string(_editor.text);
    }
}
