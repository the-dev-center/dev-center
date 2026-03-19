module modules.repo_tools.git_viewer_indexer;

import core.time : msecs;
import std.process : pipeProcess, Redirect, wait, Config;
import std.string : splitLines, strip;
import std.algorithm : splitter;
import std.conv : to;
import std.datetime.systime : SysTime, unixTimeToStdTime;
import std.datetime.date : DateTime;
import std.array : array;
import core.thread : Thread;

/// Metadata for a single commit stored in the replay index.
struct IndexedCommit
{
    string hash;
    long timestamp;
    SysTime timestampObj;
    string subject;
    size_t linesAdded;
    size_t linesRemoved;
    size_t filesChanged;
    bool isIndexed;
}

/// The indexer service walks git history in the background.
class GitViewerIndexer
{
    private string _repoRoot;
    private IndexedCommit[] _commits;
    private bool _indexing;
    private bool _paused;
    private Thread _worker;

    this(string repoRoot)
    {
        _repoRoot = repoRoot;
    }

    @property bool isIndexing() const { return _indexing && !_paused; }
    @property bool isPaused() const { return _paused; }
    @property const(IndexedCommit[]) commits() const { return _commits; }

    void start()
    {
        if (_indexing) return;
        _indexing = true;
        _paused = false;
        _worker = new Thread(&run);
        _worker.start();
    }

    void pause() { _paused = true; }
    void resume() { _paused = false; }

    private void run()
    {
        import std.process : pipeProcess, Redirect, Config;
        import core.time : msecs;

        // Initial pass: get commit hashes and timestamps quickly
        int status;
        auto pipes = pipeProcess(["git", "log", "--pretty=format:%H|%at|%s"],
            Redirect.stdout | Redirect.stderr, null, Config.none, _repoRoot);

        foreach (line; pipes.stdout.byLine)
        {
            if (_paused) {
                // Spinning wait for resume or stop signal
                while (_paused && _indexing) {
                    Thread.sleep(msecs(100));
                }
                if (!_indexing) break;
            }

            auto parts = line.idup.splitter('|').array;
            if (parts.length < 3) continue;

            IndexedCommit item;
            item.hash = parts[0];
            try {
                item.timestamp = to!long(parts[1]);
                item.timestampObj = SysTime(unixTimeToStdTime(item.timestamp));
            } catch (Exception) {}
            item.subject = parts[2];
            item.isIndexed = false;

            _commits ~= item;
        }
        pipes.pid.wait();

        // Second pass: fill in detailed stats (numstat) for each commit
        // In a real implementation, we would do this incrementally and save to disk.
        foreach (ref commit; _commits)
        {
            if (!_indexing) break;
            while (_paused && _indexing) {
                Thread.sleep(msecs(100));
            }

            auto statsPipes = pipeProcess(["git", "show", "--numstat", "--format=", commit.hash],
                Redirect.stdout | Redirect.stderr, null, Config.none, _repoRoot);

            foreach (statLine; statsPipes.stdout.byLine)
            {
                auto parts = statLine.splitter('\t').array;
                if (parts.length < 3) continue;

                string addedStr = parts[0].idup;
                string removedStr = parts[1].idup;

                if (addedStr != "-") {
                    try { commit.linesAdded += to!size_t(addedStr); } catch (Exception) {}
                }
                if (removedStr != "-") {
                    try { commit.linesRemoved += to!size_t(removedStr); } catch (Exception) {}
                }
                commit.filesChanged++;
            }
            statsPipes.pid.wait();
            commit.isIndexed = true;

            // Artificial delay to simulate background work and not saturate I/O
            Thread.sleep(msecs(10));
        }

        _indexing = false;
    }

    void stop()
    {
        _indexing = false;
        if (_worker && _worker.isRunning)
            _worker.join();
    }
}
