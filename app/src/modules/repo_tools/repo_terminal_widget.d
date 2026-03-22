module modules.repo_tools.repo_terminal_widget;

import dlangui;
import dlangui.widgets.styles : Align;
import dlangui.graphics.fonts : FontFamily;
import modules.infra.logging : logInfo, logError;
import modules.repo_tools.registry;
import std.algorithm : min;
import std.array : split;
import std.conv : to;
import std.datetime : Clock;
import std.path : buildPath;
import std.process : pipeProcess, Redirect, Config, wait, spawnProcess;
import std.string : strip;
import core.sync.mutex : Mutex;
import core.thread : Thread;

private class TerminalCommandState
{
    private Mutex _mutex;
    private string _output;
    private bool _completed;
    private int _exitCode = int.min;
    private size_t _version;

    this()
    {
        _mutex = new Mutex();
    }

    void appendLine(string line)
    {
        synchronized (_mutex)
        {
            _output ~= line ~ "\n";
            _version++;
        }
    }

    void markComplete(int exitCode)
    {
        synchronized (_mutex)
        {
            _completed = true;
            _exitCode = exitCode;
            _version++;
        }
    }

    void snapshot(out string output, out bool completed, out int exitCode, out size_t changeVersion)
    {
        synchronized (_mutex)
        {
            output = _output.dup;
            completed = _completed;
            exitCode = _exitCode;
            changeVersion = _version;
        }
    }
}

private class CommandBlockRefs
{
    VerticalLayout container;
    TextWidget header;
    EditBox output;
    TerminalCommandState state;
    string command;
    size_t lastVersion;
    bool completed;
    int exitCode;
}

private class RepoTerminalScrollWidget : ScrollWidget
{
    void jumpToY(int y)
    {
        scrollTo(0, y);
    }
}

class RepoTerminalWidget : VerticalLayout
{
    private string _repoRoot;
    private RepoToolsRegistry _repoTools;

    private StringListAdapter _indexAdapter;
    private ListWidget _indexList;
    private RepoTerminalScrollWidget _scroll;
    private VerticalLayout _blocks;
    private EditLine _commandInput;
    private TextWidget _status;

    private CommandBlockRefs[] _entries;
    private ulong _pollTimerId;

    this(string repoRoot, RepoToolsRegistry repoTools)
    {
        super();
        _repoRoot = repoRoot;
        _repoTools = repoTools;
        layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT);
        buildUI();
        registerSelf();
    }

    private void registerSelf()
    {
        ToolInstance inst;
        inst.id = "integrated-terminal-" ~ _repoRoot;
        inst.repoRoot = _repoRoot;
        inst.kind = ToolKind.builtinModule;
        inst.label = "Integrated Terminal";
        inst.icon = "terminal";
        inst.pid = 0;
        inst.executable = "";
        inst.startedAt = Clock.currTime;
        inst.lastSeenAliveAt = Clock.currTime;
        _repoTools.registerOrUpdateInstance(inst);
    }

    private void buildUI()
    {
        backgroundColor = 0x000000;
        padding(6);

        auto mainRow = new HorizontalLayout();
        mainRow.layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT);

        auto leftCol = new VerticalLayout();
        leftCol.layoutWidth(220).layoutHeight(FILL_PARENT).padding(6).backgroundColor(0x111111);
        leftCol.addChild(new TextWidget(null, "Commands"d).fontWeight(700).margins(Rect(0, 0, 0, 4)));
        _indexAdapter = new StringListAdapter();
        _indexList = new ListWidget("repoTerminalIndex");
        _indexList.layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT);
        _indexList.adapter = _indexAdapter;
        _indexList.itemClick = delegate(Widget w, int idx) {
            jumpToBlock(idx);
            return true;
        };
        leftCol.addChild(_indexList);
        mainRow.addChild(leftCol);

        _scroll = new RepoTerminalScrollWidget();
        _scroll.layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT);
        _scroll.backgroundColor = 0x1B1B1B;
        _blocks = new VerticalLayout();
        _blocks.layoutWidth(FILL_PARENT).padding(8);
        _scroll.contentWidget = _blocks;
        mainRow.addChild(_scroll);
        addChild(mainRow);

        auto toolbar = new HorizontalLayout();
        toolbar.layoutWidth(FILL_PARENT).padding(6).backgroundColor(0x1A1A1A).margins(Rect(0, 6, 0, 0));
        _commandInput = new EditLine("repoTerminalInput", ""d);
        _commandInput.layoutWidth(FILL_PARENT);
        toolbar.addChild(_commandInput);

        auto runBtn = new Button(null, "Run"d);
        runBtn.click = delegate(Widget w) { runCurrentCommand(); return true; };
        toolbar.addChild(runBtn);

        auto refreshEnvBtn = new Button(null, "Inject Env Refresh"d);
        refreshEnvBtn.click = delegate(Widget w) {
            injectEnvRefreshCommand();
            return true;
        };
        toolbar.addChild(refreshEnvBtn);

        auto openExternalBtn = new Button(null, "Open External Terminal"d);
        openExternalBtn.click = delegate(Widget w) {
            openExternalTerminal();
            return true;
        };
        toolbar.addChild(openExternalBtn);
        addChild(toolbar);

        _status = new TextWidget(null, "Repo terminal keeps per-command history blocks. Environment changes across commands are not fully persistent yet."d);
        _status.textColor(0xAAAAAA).fontSize(9).margins(Rect(4, 4, 0, 0));
        addChild(_status);
    }

    override bool onTimer(ulong id)
    {
        if (id == _pollTimerId)
        {
            bool stillRunning = false;
            foreach (entry; _entries)
            {
                string output;
                bool completed;
                int exitCode;
                size_t changeVersion;
                entry.state.snapshot(output, completed, exitCode, changeVersion);
                if (changeVersion != entry.lastVersion)
                {
                    entry.lastVersion = changeVersion;
                    entry.output.text = UIString.fromRaw(to!dstring(output));
                    entry.header.text = UIString.fromRaw(to!dstring(entry.command ~ commandStatusSuffix(completed, exitCode)));
                    entry.container.backgroundColor = completed
                        ? (exitCode == 0 ? 0x2A2A2A : 0x3A2222)
                        : 0x223344;
                    requestLayout();
                    if (window)
                        window.update(true);
                }
                if (!completed)
                    stillRunning = true;
            }
            if (stillRunning)
                return true;
            _pollTimerId = 0;
            return false;
        }
        return super.onTimer(id);
    }

    private string commandStatusSuffix(bool completed, int exitCode)
    {
        if (!completed)
            return "  [running]";
        return exitCode == 0 ? "  [done]" : "  [failed " ~ to!string(exitCode) ~ "]";
    }

    private void runCurrentCommand()
    {
        string command = to!string(_commandInput.text).strip();
        if (command.length == 0)
            return;
        logInfo("Repo terminal run: " ~ command);
        auto state = new TerminalCommandState();
        auto refs = createCommandBlock(command, state);
        auto entryIndex = _entries.length;
        _entries ~= refs;
        _indexAdapter.add(to!dstring(indexLabelFor(entryIndex, command)));
        _commandInput.text = UIString.fromRaw(""d);

        auto shellCommand = command;
        auto repoRoot = _repoRoot;
        auto threadState = state;

        auto worker = new Thread({
            int exitCode = 1;
            try
            {
                version (Windows)
                {
                    auto pipes = pipeProcess(
                        ["powershell", "-NoLogo", "-NoProfile", "-Command", shellCommand],
                        Redirect.stdout | Redirect.stderr, null, Config.none, repoRoot);
                    foreach (line; pipes.stdout.byLine())
                        threadState.appendLine(line.idup);
                    exitCode = wait(pipes.pid);
                }
                else
                {
                    auto pipes = pipeProcess(
                        ["sh", "-lc", shellCommand],
                        Redirect.stdout | Redirect.stderr, null, Config.none, repoRoot);
                    foreach (line; pipes.stdout.byLine())
                        threadState.appendLine(line.idup);
                    exitCode = wait(pipes.pid);
                }
            }
            catch (Exception e)
            {
                threadState.appendLine("Error: " ~ e.msg);
                logError("Repo terminal command failed to start: " ~ e.msg);
            }
            threadState.markComplete(exitCode);
        });
        worker.start();

        if (_pollTimerId == 0)
            _pollTimerId = setTimer(250);
    }

    private CommandBlockRefs createCommandBlock(string command, TerminalCommandState state)
    {
        auto block = new VerticalLayout();
        block.layoutWidth(FILL_PARENT).padding(8).margins(Rect(6, 6, 6, 6)).backgroundColor(0x303030);

        auto header = new TextWidget(null, to!dstring(command ~ "  [running]"));
        header.fontFamily(FontFamily.MonoSpace).fontWeight(700).margins(Rect(0, 0, 0, 6));
        block.addChild(header);

        auto output = new EditBox(null, ""d);
        output.layoutWidth(FILL_PARENT).layoutHeight(140);
        output.fontFamily(FontFamily.MonoSpace);
        output.readOnly(true);
        output.backgroundColor = 0x1B1B1B;
        block.addChild(output);

        _blocks.addChild(block);
        requestLayout();
        if (window)
            window.update(true);

        auto refs = new CommandBlockRefs();
        refs.container = block;
        refs.header = header;
        refs.output = output;
        refs.state = state;
        refs.command = command;
        refs.lastVersion = 0;
        refs.completed = false;
        refs.exitCode = int.min;
        return refs;
    }

    private string indexLabelFor(size_t index, string command)
    {
        string label = command;
        if (index > 0)
        {
            string previous = _entries[index - 1].command;
            size_t prefixLen;
            while (prefixLen < previous.length && prefixLen < command.length && previous[prefixLen] == command[prefixLen])
                prefixLen++;
            if (prefixLen >= 6 && prefixLen < command.length)
                label = "..." ~ command[prefixLen .. $];
        }
        if (label.length > 36)
            label = label[0 .. 33] ~ "...";
        return label;
    }

    private void jumpToBlock(int idx)
    {
        if (idx < 0 || idx >= _entries.length)
            return;
        int y = _entries[idx].container.pos.top;
        _scroll.jumpToY(y < 0 ? 0 : y);
        if (window)
            window.update(true);
    }

    private void injectEnvRefreshCommand()
    {
        version (Windows)
        {
            _commandInput.text = UIString.fromRaw(to!dstring("$env:Path = [System.Environment]::GetEnvironmentVariable(\"Path\",\"Machine\") + \";\" + [System.Environment]::GetEnvironmentVariable(\"Path\",\"User\")"));
        }
        else
        {
            _commandInput.text = UIString.fromRaw("exec $SHELL -l"d);
        }
    }

    private void openExternalTerminal()
    {
        version (Windows)
        {
            spawnProcess(["cmd", "/c", "start", "\"\"", "powershell", "-NoExit", "-Command", "Set-Location \"" ~ _repoRoot ~ "\""]);
        }
        else version (Posix)
        {
            spawnProcess(["sh", "-lc", "cd \"" ~ _repoRoot ~ "\"; exec $SHELL -l"]);
        }
    }
}
