module app;

import dlangui;
import modules.template_installer.installer;
import modules.template_installer.project_manager;
import modules.repo_tools.registry;
import modules.repo_tools.git_diff_stats;
import modules.repo_tools.repo_browser;
import modules.repo_tools.git_gui_dialog;
import modules.repo_tools.git_viewers;
import modules.repo_tools.hallmark_toolbar;
import modules.project_recognizer.recognizer;
import modules.system_overview.tool_manager;
import modules.system_overview.widgets;
import modules.workflow_templates_store.browser;
import modules.workflow_templates_store.store;
import modules.infra.discovery : discoverInfra, InfraDiscoveryMode, InfraDiscoverySummary;
import modules.infra.ui : InfraDiscoveryPanel, openUrlInBrowser;
import std.stdio;
import std.path;
import std.file;
import std.conv;
import std.process : environment;
import std.algorithm : endsWith, canFind;
import std.array : empty, array;
import std.string : toLower;

mixin APP_ENTRY_POINT;

class DevCenterApp {
    Window window;
    TemplateInstaller installer;
    ProjectWorkspaceManager projectManager;
    ToolManager toolManager;
    RepoToolsRegistry repoTools;
    ArchitectureModel currentModel;
    string codeRoot;          /// Root of the code hierarchy (Z:\code)
    RepoNode[] allRepos;      /// Cached scan results
    RepoNode[] filteredRepos; /// After search filter
    string selectedRepoPath;  /// Currently selected repo
    uint discoveryTimerId;    /// Background tool-discovery timer

    StringListAdapter templateAdapter;
    StringListAdapter repoAdapter;
    StringListAdapter stackAdapter;
    StringListAdapter workflowTemplateAdapter;
    WorkflowTemplateRef[] workflowTemplateList;  /// Cached list for install

    this() {
        // Initialize backend
        string cacheRoot = buildPath(getHomeDir(), ".dev-center", "templates");
        installer = new TemplateInstaller(cacheRoot);
        toolManager = new ToolManager();
        string dataRoot = buildPath(getHomeDir(), ".dev-center");
        repoTools = new RepoToolsRegistry(dataRoot);

        // Determine code root from environment or default
        string drive = environment.get("CODE_ROOT");
        if (drive is null || drive.length == 0)
        {
            version (Windows)
                codeRoot = "Z:\\code";
            else
                codeRoot = buildPath(getHomeDir(), "code");
        }
        else
        {
            codeRoot = drive;
        }

        // Target current directory
        string projectRoot = getcwd();

        // Load recognizer rules
        string profilesDir = buildPath(projectRoot, "src", "modules", "project-recognizer", "profiles");
        ProjectRecognizer recognizer;
        if (exists(profilesDir)) {
             recognizer = ProjectRecognizer.fromProfilesDir(profilesDir);
        } else {
             recognizer = new ProjectRecognizer([RecognitionRule("Generic", "General project", "", [], [], [], [], [])]);
        }

        projectManager = new ProjectWorkspaceManager(projectRoot, recognizer);

        templateAdapter = new StringListAdapter();
        repoAdapter = new StringListAdapter();
        stackAdapter = new StringListAdapter();
        workflowTemplateAdapter = new StringListAdapter();
    }

    void createUI() {
        window = Platform.instance.createWindow("Dev Center", null);

        window.mainWidget = parseML(q{
            VerticalLayout {
                layoutWidth: fill; layoutHeight: fill
                padding: 0

                // Top Bar
                HorizontalLayout {
                    layoutWidth: fill; padding: 10; background: "#121212"
                    TextWidget { text: "Dev Center"; fontSize: 18pt; fontWeight: 800; textColor: "#007AFF" }
                    Spacer { layoutWidth: fill }
                    Button { id: btnHome; text: "Home"; styleId: "BUTTON_TRANSPARENT" }
                    Button { id: btnUpdate; text: "Check for Updates" }
                }

                // Main Section with Sidebar
                HorizontalLayout {
                    layoutWidth: fill; layoutHeight: fill

                    // Left Sidebar
                    VerticalLayout {
                        id: sidebar; layoutWidth: 200; layoutHeight: fill; padding: 5
                        background: "#1A1A1A"; visibility: gone
                        Button { id: navHome; text: "Home"; layoutWidth: fill }
                        Button { id: navDashboard; text: "Tool Status"; layoutWidth: fill }
                        Button { id: navTemplates; text: "Browse Projects"; layoutWidth: fill }
                        Button { id: navProject; text: "Project Analysis"; layoutWidth: fill }
                        Button { id: navWorkflowTemplates; text: "Workflow templates"; layoutWidth: fill }
                        Button { id: navInfra; text: "Infra"; layoutWidth: fill }
                    }

                    // Main Content
            TabHost {
                id: contentStack; layoutWidth: fill; layoutHeight: fill

                // Page 0: Home Screen
                VerticalLayout {
                    id: pageHome; layoutWidth: fill; layoutHeight: fill; padding: 40; alignment: center
                    TextWidget { text: "Welcome to Dev Center"; fontSize: 24pt; fontWeight: 800; margin: 20; alignment: center }

                            HorizontalLayout {
                                layoutWidth: fill; alignment: center; spacing: 30

                                // Choice 1: Browse Projects
                                VerticalLayout {
                                    id: choiceBrowse; layoutWidth: 300; layoutHeight: 350; padding: 20; background: "#252525"
                                    ImageWidget { drawableId: "folder_open"; layoutWidth: 128; layoutHeight: 128; alignment: center; margin: 10 }
                                    TextWidget { text: "Browse Projects"; fontSize: 16pt; fontWeight: 600; alignment: center; margin: 10 }
                                    TextWidget { text: "Explore templates, discover local projects, and manage your workspace."; fontSize: 10pt; textColor: "#AAAAAA"; alignment: center; maxLines: 3 }
                                    Spacer { layoutHeight: fill }
                                    Button { id: btnChoiceBrowse; text: "Open Browser"; layoutWidth: fill }
                                }

                                // Choice 2: Tool Status
                                VerticalLayout {
                                    id: choiceTools; layoutWidth: 300; layoutHeight: 350; padding: 20; background: "#252525"
                                    ImageWidget { drawableId: "settings"; layoutWidth: 128; layoutHeight: 128; alignment: center; margin: 10 }
                                    TextWidget { text: "Tool Status"; fontSize: 16pt; fontWeight: 600; alignment: center; margin: 10 }
                                    TextWidget { text: "overview of installed development tools, PATH variables, and available missing tools."; fontSize: 10pt; textColor: "#AAAAAA"; alignment: center; maxLines: 3 }
                                    Spacer { layoutHeight: fill }
                                    Button { id: btnChoiceTools; text: "View Dashboard"; layoutWidth: fill }
                                }

                                // Choice 3: Workflow templates (replaces GitHub's broken template UX)
                                VerticalLayout {
                                    id: choiceWorkflowTemplates; layoutWidth: 300; layoutHeight: 350; padding: 20; background: "#252525"
                                    ImageWidget { drawableId: "folder_open"; layoutWidth: 128; layoutHeight: 128; alignment: center; margin: 10 }
                                    TextWidget { text: "Workflow templates"; fontSize: 16pt; fontWeight: 600; alignment: center; margin: 10 }
                                    TextWidget { text: "Browse full workflow files to copy. Not GitHub Marketplace actions — real templates."; fontSize: 10pt; textColor: "#AAAAAA"; alignment: center; maxLines: 3 }
                                    Spacer { layoutHeight: fill }
                                    Button { id: btnChoiceWorkflowTemplates; text: "Open store"; layoutWidth: fill }
                                }

                                // Choice 4: Install or add
                                VerticalLayout {
                                    id: choiceInstall; layoutWidth: 300; layoutHeight: 350; padding: 20; background: "#252525"
                                    ImageWidget { drawableId: "settings"; layoutWidth: 128; layoutHeight: 128; alignment: center; margin: 10 }
                                    TextWidget { text: "Install or add"; fontSize: 16pt; fontWeight: 600; alignment: center; margin: 10 }
                                    TextWidget { text: "Add Infrastructure as Code (OpenTofu) or project technologies (frameworks, runtimes) to this repo."; fontSize: 10pt; textColor: "#AAAAAA"; alignment: center; maxLines: 3 }
                                    Spacer { layoutHeight: fill }
                                    Button { id: btnChoiceInstall; text: "Install or add..."; layoutWidth: fill }
                                }
                            }
                        }

                        HorizontalLayout {
                    id: pageTemplates; layoutWidth: fill; layoutHeight: fill; padding: 10

                            // Left side: repo tree + search
                            VerticalLayout {
                                layoutWidth: fill; layoutHeight: fill
                                TextWidget { text: "Browse Projects"; fontSize: 14pt; margin: 5 }
                                HorizontalLayout {
                                    layoutWidth: fill; margin: 5
                                    EditLine { id: searchRepos; text: ""; layoutWidth: fill; placeholderText: "Search hosts, owners, and repos..." }
                                    Button { id: btnRefreshRepos; text: "Refresh" }
                                }
                                ListWidget { id: listRepos; layoutWidth: fill; layoutHeight: fill }
                                HorizontalLayout {
                                    layoutWidth: fill; margin: 5
                                    Button { id: btnOpenGitGui; text: "Open Git Viewer" }
                                }
                            }

                            // Right side: Project Details & Tools panel
                            VerticalLayout {
                                id: toolsPanel; layoutWidth: fill; layoutHeight: fill; // replaced rigid 280-width
                                
                                // Placeholder layout where the Hallmark Toolbar will be injected
                                VerticalLayout { id: hallmarkContainer; layoutWidth: fill; layoutHeight: WRAP_CONTENT; }

                                HorizontalLayout {
                                    layoutWidth: fill; layoutHeight: fill;
                                    
                                    // Attached Tools sub-panel inside the right-hand area
                                    VerticalLayout {
                                        layoutWidth: 280; layoutHeight: fill; padding: 10; background: "#1E1E1E"
                                        TextWidget { text: "Attached Tools"; fontSize: 12pt; fontWeight: 700; margin: 5; textColor: "#007AFF" }
                                        ListWidget { id: listAttachedTools; layoutWidth: fill; layoutHeight: fill }
                                        Button { id: btnDiscoverTools; text: "Discover Tools" }
                                    }
                                    
                                    // Placeholder for future Readme WebView or integrated Editor
                                    VerticalLayout {
                                        layoutWidth: fill; layoutHeight: fill; padding: 10;
                                        TextWidget { text: "Select a repository to view details."; id: repoPreviewText; alignment: center; textColor: "#AAAAAA" }
                                    }
                                }
                            }
                        }

                        VerticalLayout {
                    id: pageProject; layoutWidth: fill; layoutHeight: fill; padding: 10
                            TextWidget { text: "Project Analysis"; fontSize: 14pt; margin: 5 }
                            TextWidget { id: projectPathLabel; text: "Path: " }
                            ListWidget { id: listStacks; layoutWidth: fill; layoutHeight: fill }
                            HorizontalLayout {
                                Button { id: btnSaveTemplate; text: "Save as New Template" }
                                Button { id: btnSync; text: "Sync Templates" }
                            }
                        }

                        VerticalLayout {
                    id: pageDashboard; layoutWidth: fill; layoutHeight: fill; padding: 10
                            TextWidget { text: "Tool Status Overview"; fontSize: 18pt; margin: 10 }

                            TabWidget {
                                id: dashboardTabs; layoutWidth: fill; layoutHeight: fill
                                VerticalLayout { id: tabInstalled; text: "Installed"; layoutWidth: fill; layoutHeight: fill }
                                VerticalLayout { id: tabAvailable; text: "Available"; layoutWidth: fill; layoutHeight: fill }
                            }
                        }

                        VerticalLayout {
                    id: pageWorkflowTemplates; layoutWidth: fill; layoutHeight: fill; padding: 10
                            TextWidget { text: "Workflow templates"; fontSize: 14pt; margin: 5 }
                            TextWidget { id: workflowInstallPathLabel; text: "Install into: "; margin: 2 }
                            ListWidget { id: listWorkflowTemplates; layoutWidth: fill; layoutHeight: fill }
                            HorizontalLayout {
                                Button { id: btnRefreshWorkflowTemplates; text: "Refresh list" }
                                Button { id: btnInstallWorkflowTemplate; text: "Install into repo" }
                                Button { id: btnOpenWorkflowStore; text: "Open store in browser" }
                            }
                        }

                        VerticalLayout {
                    id: pageInfra; layoutWidth: fill; layoutHeight: fill; padding: 10
                            TextWidget { text: "Infrastructure (IaC)"; fontSize: 14pt; margin: 5 }
                            TextWidget { id: infraPathLabel; text: "Scope: "; margin: 2 }
                            HorizontalLayout { layoutWidth: fill; margin: 5
                                Button { id: btnRefreshInfra; text: "Refresh" }
                                Button { id: btnInfraDocs; text: "Docs" }
                            }
                            HorizontalLayout { id: infraPanelContainer; layoutWidth: fill; layoutHeight: fill }
                        }

                        VerticalLayout {
                    id: pageInstall; layoutWidth: fill; layoutHeight: fill; padding: 20
                            TextWidget { text: "Install or add"; fontSize: 18pt; margin: 10 }
                            TextWidget { id: installPathLabel; text: "Repo: "; margin: 5 }
                            VerticalLayout { layoutWidth: fill; spacing: 10
                                Button { id: btnInstallIac; text: "Add Infrastructure as Code (OpenTofu)"; layoutWidth: 300 }
                                Button { id: btnInstallIacDocs; text: "Docs: Infrastructure as Code"; layoutWidth: 300 }
                                Button { id: btnInstallTech; text: "Add project technologies (frameworks, runtimes)"; layoutWidth: 300 }
                            }
                        }
                    }
                }
            }
        });

        // Programmatically add dashboard content
        auto tabInstalled = window.mainWidget.childById!VerticalLayout("tabInstalled");
        tabInstalled.addChild(new ToolStatusDashboard(toolManager, true));

        auto tabAvailable = window.mainWidget.childById!VerticalLayout("tabAvailable");
        tabAvailable.addChild(new ToolStatusDashboard(toolManager, false));

        auto dashboardTabs = window.mainWidget.childById!TabWidget("dashboardTabs");
        dashboardTabs.addTab(tabInstalled, "Installed Tools"d);
        dashboardTabs.addTab(tabAvailable, "Available Tools"d);

        // Template list is no longer displayed directly; the Browse Projects page
        // will be wired to a repository browser in a future revision.

        auto listRepos = window.mainWidget.childById!ListWidget("listRepos");
        listRepos.adapter = repoAdapter;
        listRepos.itemClick = delegate(Widget source, int itemIndex) {
            if (itemIndex >= 0 && itemIndex < filteredRepos.length) {
                selectedRepoPath = filteredRepos[itemIndex].fullPath;
                refreshToolsPanel();
            }
            return true;
        };

        auto listAttachedTools = window.mainWidget.childById!ListWidget("listAttachedTools");
        auto toolsAdapter = new StringListAdapter();
        listAttachedTools.adapter = toolsAdapter;
        listAttachedTools.itemClick = delegate(Widget source, int itemIndex) {
            import modules.repo_tools.platform : bringProcessToFront;
            auto tools = repoTools.instancesForRepo(selectedRepoPath);
            if (itemIndex >= 0 && itemIndex < tools.length) {
                bringProcessToFront(tools[itemIndex].pid);
            }
            return true;
        };

        auto listStacks = window.mainWidget.childById!ListWidget("listStacks");
        listStacks.adapter = stackAdapter;

        auto listWorkflowTemplates = window.mainWidget.childById!ListWidget("listWorkflowTemplates");
        listWorkflowTemplates.adapter = workflowTemplateAdapter;

        setupEventHandlers();
        refreshTemplates();
        refreshProject();

        // Start background discovery timer (every 10 seconds)
        discoveryTimerId = window.setTimer(10000, delegate() {
            string[] roots;
            foreach (r; allRepos) roots ~= r.fullPath;
            repoTools.discoverExternalTools(roots);
            refreshToolsPanel();
            return true;
        });

        window.show();
    }

    void setupEventHandlers() {
    auto contentStack = window.mainWidget.childById!TabHost("contentStack");
    auto sidebar = window.mainWidget.childById("sidebar");

        auto showPage = delegate(int index, bool showSidebar) {
        string[] pageIds = ["pageHome", "pageTemplates", "pageProject", "pageDashboard", "pageWorkflowTemplates", "pageInfra", "pageInstall"];
        if (index >= 0 && index < pageIds.length) {
            contentStack.showChild(pageIds[index]);
        }
        sidebar.visibility = showSidebar ? Visibility.Visible : Visibility.Gone;
        if (index == 1) {
            refreshRepoList();
        }
        if (index == 4) {
            refreshWorkflowTemplates();
        }
        if (index == 5) {
            refreshInfra();
        }
        if (index == 6) {
            auto installLabel = window.mainWidget.childById!TextWidget("installPathLabel");
            if (installLabel) installLabel.text = UIString.fromRaw("Repo: "d ~ to!dstring(getcwd()));
        }
    };

        window.mainWidget.childById!Button("btnHome").click = delegate(Widget w) {
            showPage(0, false);
            return true;
        };
        window.mainWidget.childById!Button("navHome").click = delegate(Widget w) {
            showPage(0, false);
            return true;
        };

        window.mainWidget.childById!Button("btnChoiceBrowse").click = delegate(Widget w) {
            showPage(1, true);
            return true;
        };
        window.mainWidget.childById!Button("navTemplates").click = delegate(Widget w) {
            showPage(1, true);
            return true;
        };

        window.mainWidget.childById!Button("btnChoiceTools").click = delegate(Widget w) {
            showPage(3, true);
            return true;
        };
        window.mainWidget.childById!Button("navDashboard").click = delegate(Widget w) {
            showPage(3, true);
            return true;
        };

        window.mainWidget.childById!Button("navProject").click = delegate(Widget w) {
            showPage(2, true);
            refreshProject();
            return true;
        };

        window.mainWidget.childById!Button("navWorkflowTemplates").click = delegate(Widget w) {
            showPage(4, true);
            return true;
        };
        window.mainWidget.childById!Button("btnChoiceWorkflowTemplates").click = delegate(Widget w) {
            showPage(4, true);
            return true;
        };
        window.mainWidget.childById!Button("btnChoiceInstall").click = delegate(Widget w) {
            showPage(6, true);
            return true;
        };
        window.mainWidget.childById!Button("btnInstallIacDocs").click = delegate(Widget w) {
            openUrlInBrowser("https://docs.devcentr.org/knowledge-base/latest/explanation/infrastructure/iac.html");
            return true;
        };
        window.mainWidget.childById!Button("btnInstallIac").click = delegate(Widget w) {
            bootstrapOpenTofuHere();
            return true;
        };
        window.mainWidget.childById!Button("btnInstallTech").click = delegate(Widget w) {
            window.showMessageBox(UIString.fromRaw("Project technologies"d), UIString.fromRaw("Frameworks and runtimes will be available here. Use the sidebar to open Project Analysis or Infra."d));
            return true;
        };
        window.mainWidget.childById!Button("navInfra").click = delegate(Widget w) {
            showPage(5, true);
            return true;
        };
        window.mainWidget.childById!Button("btnRefreshInfra").click = delegate(Widget w) {
            refreshInfra();
            return true;
        };
        window.mainWidget.childById!Button("btnInfraDocs").click = delegate(Widget w) {
            openUrlInBrowser("https://docs.devcentr.org/knowledge-base/latest/explanation/infrastructure/iac.html");
            return true;
        };

        window.mainWidget.childById!Button("btnRefreshWorkflowTemplates").click = delegate(Widget w) {
            refreshWorkflowTemplates();
            return true;
        };
        window.mainWidget.childById!Button("btnInstallWorkflowTemplate").click = delegate(Widget w) {
            auto list = window.mainWidget.childById!ListWidget("listWorkflowTemplates");
            int idx = list.selectedItemIndex;
            if (idx < 0 || idx >= workflowTemplateList.length) {
                window.showMessageBox(UIString.fromRaw("Install"d), UIString.fromRaw("Select a template first."d));
                return true;
            }
            string baseUrl = getWorkflowTemplatesStoreURL();
            string id = workflowTemplateList[idx].id;
            auto content = fetchTemplateContent(baseUrl, id);
            if (!content) {
                window.showMessageBox(UIString.fromRaw("Install"d), UIString.fromRaw("Could not fetch template content."d));
                return true;
            }
            string errMsg;
            bool ok = installTemplateIntoRepo(getcwd(), content.filename, content.content, errMsg);
            if (ok) {
                window.showMessageBox(UIString.fromRaw("Install"d), UIString.fromRaw("Installed "d ~ to!dstring(content.filename) ~ " into .github/workflows/"d));
            } else {
                window.showMessageBox(UIString.fromRaw("Install failed"d), UIString.fromRaw(to!dstring(errMsg)));
            }
            return true;
        };
        window.mainWidget.childById!Button("btnOpenWorkflowStore").click = delegate(Widget w) {
            openWorkflowTemplatesStore();
            return true;
        };

        window.mainWidget.childById!Button("btnUpdate").click = delegate(Widget w) {
            bool updated = installer.updateCache(true);
            refreshTemplates();
            window.showMessageBox(UIString.fromRaw("Status"d), UIString.fromRaw(updated ? "Cache Updated"d : "Up to Date"d));
            return true;
        };

        // Repo browser: search on text change
        auto searchEdit = window.mainWidget.childById!EditLine("searchRepos");
        searchEdit.contentChange = delegate(EditableContent content) {
            refreshRepoList();
        };

        window.mainWidget.childById!Button("btnRefreshRepos").click = delegate(Widget w) {
            allRepos = scanCodeRoot(codeRoot);
            refreshRepoList();
            return true;
        };

        window.mainWidget.childById!Button("btnOpenGitGui").click = delegate(Widget w) {
            if (selectedRepoPath.length > 0)
            {
                showGitGuiSelectorDialog(window, selectedRepoPath, repoTools);
            }
            else
            {
                window.showMessageBox(UIString.fromRaw("Git Viewer"d), UIString.fromRaw("Select a repository first."d));
            }
            return true;
        };

        window.mainWidget.childById!Button("btnDiscoverTools").click = delegate(Widget w) {
            string[] roots;
            foreach (r; allRepos)
            {
                roots ~= r.fullPath;
            }
            repoTools.discoverExternalTools(roots);
            refreshToolsPanel();
            return true;
        };

        window.mainWidget.childById!Button("btnInstall").click = delegate(Widget w) {
            auto list = window.mainWidget.childById!ListWidget("listTemplates");
            if (list.selectedItemIndex >= 0) {
                // TODO: proper install
            }
            return true;
        };
    }

    void refreshTemplates() {
        templateAdapter.clear();
    }

    void refreshProject() {
        stackAdapter.clear();
        currentModel = projectManager.identifyStacks();
        foreach(s; currentModel.techStacks) {
            stackAdapter.add(to!dstring(s.name ~ " (" ~ s.description ~ ")"));
        }
        auto label = window.mainWidget.childById!TextWidget("projectPathLabel");
        if (label) {
            label.text = UIString.fromRaw("Path: "d ~ to!dstring(getcwd()));
        }
    }

    void refreshRepoList() {
        repoAdapter.clear();

        // Scan on first call
        if (allRepos.length == 0)
        {
            allRepos = scanCodeRoot(codeRoot);
        }

        // Apply search filter
        auto searchEdit = window.mainWidget.childById!EditLine("searchRepos");
        string query = to!string(searchEdit.text);
        filteredRepos = filterRepos(allRepos, query);

        // Group by host/owner and render as tree-like list
        string lastHost = "";
        string lastOwner = "";

        foreach (repo; filteredRepos)
        {
            // Insert host header
            if (repo.host != lastHost)
            {
                repoAdapter.add(to!dstring("▸ " ~ repo.host));
                lastHost = repo.host;
                lastOwner = ""; // reset owner on new host
            }

            // Insert owner header
            if (repo.owner != lastOwner)
            {
                string ownerPrefix = repo.isClone ? "  ▸ .clones/" : "  ▸ ";
                repoAdapter.add(to!dstring(ownerPrefix ~ repo.owner));
                lastOwner = repo.owner;
            }

            // Compute diff stats for this repo
            auto stats = computeDiffStats(repo.fullPath);

            string prefix = repo.isFork ? "    ⑂ " : "    " ;
            string label;
            if (stats.isDirty)
            {
                label = prefix ~ repo.name ~ "  [+"
                    ~ to!string(stats.linesAdded)
                    ~ " / -"
                    ~ to!string(stats.linesRemoved)
                    ~ " ("
                    ~ to!string(stats.filesChanged)
                    ~ " files)]";
            }
            else
            {
                label = prefix ~ repo.name ~ "  (clean)";
            }

            // Append tools count from registry
            auto tools = repoTools.instancesForRepo(repo.fullPath);
            if (tools.length > 0)
            {
                label ~= "  🔧" ~ to!string(tools.length);
            }

            repoAdapter.add(to!dstring(label));
        }
    }

    void refreshToolsPanel() {
        // --- Setup Hallmark Strip ---
        auto hallmarkContainer = window.mainWidget.childById!VerticalLayout("hallmarkContainer");
        if (hallmarkContainer) {
            hallmarkContainer.removeAllChildren();
            if (selectedRepoPath.length > 0) {
                hallmarkContainer.addChild(createRepoToolbar(window, selectedRepoPath));
            }
        }
        
        auto repoText = window.mainWidget.childById!TextWidget("repoPreviewText");
        if (repoText) {
            repoText.text = UIString.fromRaw(selectedRepoPath.length > 0 ? "Repository: "d ~ to!dstring(selectedRepoPath) : "Select a repository to view details."d);
        }

        // --- Setup Tools List ---
        auto toolsList = window.mainWidget.childById!ListWidget("listAttachedTools");
        if (!toolsList) return;

        auto adapter = cast(StringListAdapter) toolsList.adapter;
        if (!adapter) return;

        adapter.clear();

        if (selectedRepoPath.length == 0)
        {
            adapter.add(to!dstring("Select a repo to see tools"));
            return;
        }

        auto tools = repoTools.instancesForRepo(selectedRepoPath);
        if (tools.length == 0)
        {
            adapter.add(to!dstring("No tools attached"));
            return;
        }

        foreach (tool; tools)
        {
            string entry = tool.label ~ " (PID " ~ to!string(tool.pid) ~ ")";
            adapter.add(to!dstring(entry));
        }
    }

    void refreshWorkflowTemplates() {
        workflowTemplateAdapter.clear();
        workflowTemplateList = fetchTemplatesList(getWorkflowTemplatesStoreURL());
        foreach (t; workflowTemplateList) {
            workflowTemplateAdapter.add(to!dstring(t.name ~ " (" ~ t.source ~ ")"));
        }
        auto pathLabel = window.mainWidget.childById!TextWidget("workflowInstallPathLabel");
        if (pathLabel) {
            pathLabel.text = UIString.fromRaw("Install into: "d ~ to!dstring(getcwd()));
        }
    }

    void refreshInfra() {
        string scopeRoot = getcwd();
        auto summary = discoverInfra(scopeRoot, InfraDiscoveryMode.IntegratedPerRepo, scopeRoot);
        auto container = window.mainWidget.childById!HorizontalLayout("infraPanelContainer");
        if (container) {
            container.removeAllChildren();
            container.addChild(new InfraDiscoveryPanel(summary));
        }
        auto label = window.mainWidget.childById!TextWidget("infraPathLabel");
        if (label) {
            label.text = UIString.fromRaw("Scope: "d ~ to!dstring(scopeRoot));
        }
    }

    void bootstrapOpenTofuHere() {
        string repo = getcwd();
        string infraDir = buildPath(repo, "infra");
        if (exists(infraDir) && isDir(infraDir)) {
            window.showMessageBox(UIString.fromRaw("Infra"d), UIString.fromRaw("infra/ already exists. Use the Infra page to view it."d));
            return;
        }
        mkdirRecurse(infraDir);
        string mainContent = `// OpenTofu root module. Add resources and modules here.
// See https://developer.opentofu.org/docs

resource "null_resource" "example" {
  triggers = {
    example = "bootstrap"
  }
}
`;
        string varsContent = `// Input variables for this OpenTofu configuration.

variable "example" {
  description = "Example variable"
  type        = string
  default     = "hello"
}
`;
        write(buildPath(infraDir, "main.tofu"), mainContent);
        write(buildPath(infraDir, "variables.tofu"), varsContent);
        window.showMessageBox(UIString.fromRaw("Infra"d), UIString.fromRaw("Created infra/ with main.tofu and variables.tofu. Open the Infra page to see it."d));
    }

    static string getHomeDir() {
        version(Windows) {
            string drive = environment.get("HOMEDRIVE");
            string path = environment.get("HOMEPATH");
            if (drive && path) return buildPath(drive, path);
            return environment.get("USERPROFILE");
        }
        else return environment.get("HOME");
    }
}

extern (C) int UIAppMain(string[] args) {
    auto app = new DevCenterApp();
    app.createUI();
    return Platform.instance.enterMessageLoop();
}
