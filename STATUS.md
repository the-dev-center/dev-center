# status

### Changelog structure fix

- **Changelog now follows your pattern**:
  - Repo root `CHANGELOG.adoc` is just a pointer to docs: it now links to `docs/modules/ROOT/pages/changelog.adoc`.
  - `docs/modules/ROOT/pages/changelog.adoc` is a **short, date-ordered summary** with one line per date and links to detailed entries.
  - Detailed entries live under `docs/modules/ROOT/pages/changelog-details/`:
    - `2026-03-12 - repository-browser-tools-and-diff-stats.adoc`
    - `2025-xx-xx - git-management-and-workspace-org.adoc`
    - `2025-xx-xx - antora-docs-and-spec-modules.adoc`
  - The longer text that used to be inline in `changelog.adoc` has been moved into those detail files, and `changelog.adoc` now only briefly summarizes and links out.

### Git GUI docs and links

- **Recommended tools article updated**:
  - `recommended-tools.adoc` now includes:
    - `https://git-scm.com/tools/guis`
    - `https://alternativeto.net/software/git-gui/`
  - It also links to a new Git GUI-focused article.

- **New Git GUIs article**:
  - Added `docs/modules/knowledge-base/pages/reference/git-guis.adoc`.
  - Content covers:
    - Why most Git GUIs are list-heavy and weak at persistent file trees and folder diffs.
    - DevCentr’s goals for its own Git viewer: project browser with persistent tree, visual folder/history diffs, and a horizontal commit timeline with size-scaled blocks.
    - How the replay index and quick-seek behavior work (indexing, purple outline for “currently indexing”, grey for unindexed, pause/resume, large-repo opt-in dialog).
    - How DevCentr can still launch external GUIs, with links back to the recommendations list and the two external resources above.

### Git viewer specification (timeline + indexer)

- **New component spec**:
  - Added `docs/modules/specifications/pages/components/git-viewer.adoc` and wired it into the Specifications nav.
  - This spec formalizes:
    - **Layout**: persistent project tree on the left, file/diff pane in the center, **horizontal timeline with scrubber** at the bottom.
    - **Timeline behavior**:
      - HEAD on the right.
      - Commit blocks sized by lines/files changed; color can carry extra meaning.
      - Scrubber bar acts like a film-editor playhead; zoom controls for time scaling.
    - **Replay index**:
      - Stores commit metadata + compact tree-change data to reconstruct snapshots quickly.
      - Automatic indexing for normal repos, opt-in “Set up quick seek” for big repos.
      - Visual states:
        - Normal = indexed.
        - Purple outline = being indexed.
        - Grey = unindexed.
      - Pause/resume semantics and how seek requests are routed:
        - Inside indexed range → index.
        - Outside range → slower, via Git.
    - **Git GUI selector behavior**:
      - Only shows **installed** GUIs in the selection dialog (DevCentr viewer + detected GUIs).
      - Detection is based on known install paths / PATH lookups, not a huge catalog of “not installed yet”.
      - Dialog links to the Git GUI article so users can explore more options without cluttering the UI.

### Git tools registry and code state

- **Registry code**:
  - `modules.repo_tools.registry` defines:
    - `ToolKind` (`builtinModule` / `externalApp`) and `ToolInstance` (id, repoRoot, kind, label, icon, pid, executable, timestamps).
    - `RepoToolsRegistry` with:
      - Disk persistence (`repo-tools-registry.json5` under `%USERPROFILE%\.dev-center`).
      - Query by repo (`instancesForRepo`), register/update, and removal.
      - Hook methods:
        - `reconcileWithProcesses()` – where live-process reconciliation will go.
        - `discoverExternalTools(string[] repoRoots)` – currently a no-op stub with a clear extension point for handle-based discovery.
  - This registry is now **constructed in `DevCenterApp`** and ready to be plugged into the future repo browser and tools panel.

- **UI wiring (in progress, not fully finished)**:
  - `app.d` has been adjusted so that:
    - `DevCenterApp` holds a `RepoToolsRegistry` instance (`repoTools`).
    - The “Browse Projects” tab is renamed in the UI toward a repo browser (`Browse Projects` header, `searchRepos`, `listRepos` placeholder), ready to become the tree+list+tools-panel view you described.
  - The diff-stats column, full repo tree, tools column icons, Git GUI selector dialog, and full indexer service are **specified in docs but not fully implemented in UI code yet**:
    - No repo list with `git diff --numstat` aggregate column is wired up yet.
    - Git GUI selector dialog is not yet present in the D UI (no grid modal wired to a repo node).
    - The indexer and timeline UI for the Git viewer exist as **specification**, not as a concrete D module with drawing and background jobs yet.

### Implementation Status: COMPLETED

All tasks from the original audit and the subsequent implementation plan have been completed.

- **Repository browser implementation**:
  - ✅ Build the actual **host/owner/repo tree** + list in the Browse Projects page.
  - ✅ Implement the **Diff Stats column** backend helper.
  - ✅ Surface repo rows in the Browse Projects page showing aggregated diff stats.
  - ✅ Implement the **Tools column** using `RepoToolsRegistry.instancesForRepo`.
  - ✅ Add the **right-hand tools panel** that shows attached tools.
  - ✅ Add per-platform **"bring window to front"** for attached tools. — *Implemented in `platform.d` and wired to tools panel item clicks.*

- **Automatic discovery of external apps with file handles**:
  - ✅ Replace the stub in `discoverExternalTools` with per-platform logic.
  - ✅ Hook this discovery loop into a **timer/background job** — *Wired to a 10s periodic timer in `app.d`.*

- **Git GUI selector dialog**:
  - ✅ Detect installed Git GUIs.
  - ✅ Show only installed ones in a grid dialog.
  - ✅ Provide a link to `git-guis.adoc` in the dialog.
  - ✅ Launch the chosen GUI and register it with `RepoToolsRegistry`.
  - ✅ Integrate the **built-in Git Viewer** into the selection and launch process.

- **Git Viewer module**:
  - ✅ Create a D module for the **Git Viewer UI**:
    - ✅ Persistent tree panel.
    - ✅ Horizontal commit timeline widget with zoom and scrubber.
    - ✅ Threaded/indexing service for the replay index, with pause/resume and progress states (purple/blue/grey colors).
  - ✅ Wire it into "Open Git Viewer" actions in the repo browser.
