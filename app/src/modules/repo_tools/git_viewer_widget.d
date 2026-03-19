module modules.repo_tools.git_viewer_widget;

import dlangui;
import dlangui.widgets.popup : PopupAlign;
import dlangui.graphics.drawbuf : DrawBuf;
import modules.repo_tools.git_viewer_indexer;
import modules.repo_tools.git_attributes_helper;
import std.conv : to;
import std.path : baseName;
import std.datetime.systime : SysTime, unixTimeToStdTime;
import std.algorithm : max, min, sort;
import std.file : dirEntries, SpanMode;
import std.string : toLower;
import std.array : array;

/// A custom widget to draw the horizontal commit timeline.
class TimelineWidget : Widget {
    GitViewerIndexer _indexer;
    float _zoom = 1.0f;
    float _scrollOffset = 0.0f;
    long _selectedTimestamp = 0;

    this(GitViewerIndexer indexer) {
        super("timeline");
        _indexer = indexer;
        layoutWidth(FILL_PARENT).layoutHeight(120);
        backgroundColor(0x111111);
    }

    override void onDraw(DrawBuf buf) {
        super.onDraw(buf);
        
        auto rect = _pos;
        if (rect.empty) return;

        auto commits = _indexer.commits;
        if (commits.length == 0) return;

        long minTs = commits[$-1].timestamp;
        long maxTs = commits[0].timestamp;
        long duration = maxTs - minTs;
        if (duration == 0) duration = 1;

        // Draw background
        buf.fillRect(rect, 0x111111);

        // Draw commit blocks
        foreach (commit; commits) {
            float relPos = (commit.timestamp - minTs) / cast(float)duration;
            int x = cast(int)(rect.left + relPos * rect.width * _zoom - _scrollOffset);
            
            // Skip if out of view
            if (x < rect.left || x > rect.right) continue;

            int width = cast(int)(max(2.0f, commit.filesChanged * 2.0f));
            int height = cast(int)(min(rect.height - 10, 20 + commit.linesAdded / 100.0f));
            
            uint color = 0x444444; // Default unindexed
            if (commit.isIndexed) {
                color = 0x007AFF; // Indexed blue
            } else if (_indexer.isIndexing) {
                color = 0x9B4DFF; // Indexing purple
            }

            Rect blockRect = Rect(x, rect.bottom - height - 10, x + width, rect.bottom - 10);
            buf.fillRect(blockRect, color);
        }

        // Draw scrubber/playhead
        if (_selectedTimestamp != 0) {
            float relPos = (_selectedTimestamp - minTs) / cast(float)duration;
            int x = cast(int)(rect.left + relPos * rect.width * _zoom - _scrollOffset);
            buf.fillRect(Rect(x - 1, rect.top, x + 1, rect.bottom), 0xFFFFFF);
        }
    }

    override bool onMouseEvent(MouseEvent event) {
        if (event.action == MouseAction.ButtonDown || (event.action == MouseAction.Move && (event.flags & MouseFlag.LButton))) {
            // Calculate timestamp from X position
            auto rect = _pos;
            if (_indexer.commits.length > 0 && !rect.empty) {
                long minTs = _indexer.commits[$-1].timestamp;
                long maxTs = _indexer.commits[0].timestamp;
                long duration = maxTs - minTs;
                
                float relPos = (event.x - rect.left + _scrollOffset) / (rect.width * _zoom);
                _selectedTimestamp = cast(long)(minTs + relPos * min(1.0f, max(0.0f, duration)));
                invalidate();
                return true;
            }
        }
        return super.onMouseEvent(event);
    }
}

/// The main Git Viewer window.
class GitViewerWindow {
    Window _window;
    GitViewerIndexer _indexer;
    string _repoRoot;

    this(string repoRoot) {
        _repoRoot = repoRoot;
        _indexer = new GitViewerIndexer(repoRoot);
        _indexer.start();
    }

    void show() {
        _window = Platform.instance.createWindow(to!dstring("Git Viewer - " ~ baseName(_repoRoot)), null);
        
        auto mainLayout = new VerticalLayout();
        mainLayout.layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT).padding(0);

        // Top bar
        auto topBar = new HorizontalLayout();
        topBar.layoutWidth(FILL_PARENT).padding(10).backgroundColor(0x1A1A1A);
        topBar.addChild(new TextWidget(null, "Git Viewer: " ~ to!dstring(baseName(_repoRoot))));
        mainLayout.addChild(topBar);

        // Center: Tree and Diff (placeholder)
        auto centerLayout = new HorizontalLayout();
        centerLayout.layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT);
        
        auto tree = new ListWidget("repo_tree");
        tree.layoutWidth(250).layoutHeight(FILL_PARENT).backgroundColor(0x1F1F1F);
        
        auto treeAdapter = new StringListAdapter();
        string[] files;
        foreach (entry; dirEntries(_repoRoot, SpanMode.shallow)) {
            files ~= baseName(entry.name);
        }
        files.sort!((a, b) => a.toLower() < b.toLower());
        foreach (f; files) treeAdapter.add(to!dstring(f));
        tree.adapter = treeAdapter;
        
        tree.mouseEvent = delegate(Widget w, MouseEvent event) {
            if (event.action == MouseAction.ButtonDown && event.button == MouseButton.Right) {
                // Show context menu if .gitattributes is selected
                int idx = tree.selectedItemIndex;
                if (idx >= 0 && idx < treeAdapter.items.length) {
                    string filename = to!string(treeAdapter.items[idx]);
                    if (filename == ".gitattributes") {
                        MenuItem menuRoot = new MenuItem();
                        auto action = new Action(1, UIString.fromRaw("Show other locations (user, system)..."d));
                        menuRoot.add(action);
                        PopupMenu menu = new PopupMenu(menuRoot);
                        menu.menuItemAction = delegate(const Action a) {
                            if (a.id == 1) {
                                showGitAttributesLocationsDialog(_window, _repoRoot);
                                return true;
                            }
                            return false;
                        };
                        _window.showPopup(menu, tree, PopupAlign.Point | PopupAlign.Right, event.x, event.y);
                        return true;
                    }
                }
            }
            return false;
        };
        centerLayout.addChild(tree);

        auto diffArea = new VerticalLayout();
        diffArea.layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT).padding(20);
        diffArea.addChild(new TextWidget(null, "Select a commit on the timeline to view changes..."));
        centerLayout.addChild(diffArea);

        mainLayout.addChild(centerLayout);

        // Bottom: Timeline
        auto timelineContainer = new VerticalLayout();
        timelineContainer.layoutWidth(FILL_PARENT).padding(5).backgroundColor(0x111111);
        
        auto timeline = new TimelineWidget(_indexer);
        timelineContainer.addChild(timeline);
        
        auto controls = new HorizontalLayout();
        controls.layoutWidth(FILL_PARENT).padding(5);
        auto btnPause = new Button(null, "Pause Indexing");
        btnPause.click = delegate(Widget w) {
            if (_indexer.isPaused) {
                _indexer.resume();
                btnPause.text = "Pause Indexing";
            } else {
                _indexer.pause();
                btnPause.text = "Resume Indexing";
            }
            return true;
        };
        controls.addChild(btnPause);
        
        timelineContainer.addChild(controls);
        mainLayout.addChild(timelineContainer);

        _window.mainWidget = mainLayout;
        _window.show();
    }
}
