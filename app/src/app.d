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
import modules.infra.logging : initDevCenterLogging, logInfo;
import modules.infra.ui : InfraDiscoveryPanel, openUrlInBrowser;
import modules.repo_tools.repo_terminal_widget : RepoTerminalWidget;
import modules.services.ai_config_dialog : showAIConfigDialog;
import modules.vcs.vcs_profiles : loadProfilesJson, getProviderForHost, hasOrgProfileSupport, orgProfilePublicUrl, orgProfileMemberUrl, orgProfilePublicRepoUrl, orgProfilePrivateRepoUrl, VCSProviderProfile;
import std.json : JSONValue;
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
    string selectedHost;      /// When owner/org selected
    string selectedOwner;     /// When org selected (for profile panel)
    enum BrowserItemType { host, owner, repo }
    struct BrowserItem { BrowserItemType type; string host; string owner; RepoNode repo; }
    BrowserItem[] browserItems; /// Maps list index to item type
    JSONValue vcsProfiles;     /// Loaded from profiles.json5
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
        initDevCenterLogging(dataRoot);
        logInfo("DevCenterApp constructor started.");
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

        string vcsProfilesPath = buildPath(projectRoot, "src", "modules", "vcs", "profiles.json5");
        vcsProfiles = loadProfilesJson(vcsProfilesPath);
        logInfo("VCS profiles loaded.");

        templateAdapter = new StringListAdapter();
        repoAdapter = new StringListAdapter();
        stackAdapter = new StringListAdapter();
        workflowTemplateAdapter = new StringListAdapter();
    }

    void createUI() {
        logInfo("Creating main UI window.");
        window = Platform.instance.createWindow("Dev Center", null);

        string uiPath = buildPath(getcwd(), "src", "ui", "main.sdl");
        window.mainWidget = parseML(readText(uiPath));

        // The tab bodies are declared in DML already; just populate them.
        auto tabInstalled = window.mainWidget.childById!VerticalLayout("tabInstalled");
        if (tabInstalled)
            tabInstalled.addChild(new ToolStatusDashboard(toolManager, true));

        auto tabAvailable = window.mainWidget.childById!VerticalLayout("tabAvailable");
        if (tabAvailable)
            tabAvailable.addChild(new ToolStatusDashboard(toolManager, false));

        // Template list is no longer displayed directly; the Browse Projects page
        // will be wired to a repository browser in a future revision.

        auto listRepos = window.mainWidget.childById!ListWidget("listRepos");
        if (listRepos) {
            listRepos.adapter = repoAdapter;
            listRepos.itemClick = delegate(Widget source, int itemIndex) {
                if (itemIndex >= 0 && itemIndex < browserItems.length) {
                    auto bi = browserItems[itemIndex];
                    selectedHost = bi.host;
                    selectedOwner = bi.owner;
                    selectedRepoPath = (bi.type == BrowserItemType.repo) ? bi.repo.fullPath : "";
                    refreshToolsPanel();
                }
                return true;
            };
        }

        auto listAttachedTools = window.mainWidget.childById!ListWidget("listAttachedTools");
        auto toolsAdapter = new StringListAdapter();
        if (listAttachedTools) {
            listAttachedTools.adapter = toolsAdapter;
            listAttachedTools.itemClick = delegate(Widget source, int itemIndex) {
                import modules.repo_tools.platform : bringProcessToFront;
                auto tools = repoTools.instancesForRepo(selectedRepoPath);
                if (itemIndex >= 0 && itemIndex < tools.length) {
                    bringProcessToFront(tools[itemIndex].pid);
                }
                return true;
            };
        }

        auto listStacks = window.mainWidget.childById!ListWidget("listStacks");
        if (listStacks)
            listStacks.adapter = stackAdapter;

        auto listWorkflowTemplates = window.mainWidget.childById!ListWidget("listWorkflowTemplates");
        if (listWorkflowTemplates)
            listWorkflowTemplates.adapter = workflowTemplateAdapter;

        auto sidebar = window.mainWidget.childById("sidebar");
        if (sidebar)
            sidebar.visibility = Visibility.Gone;

        setupEventHandlers();
        refreshTemplates();
        refreshProject();
        auto contentStack = window.mainWidget.childById!FrameLayout("contentStack");
        if (contentStack)
            contentStack.showChild("pageHome", Visibility.Gone);

        // Start background discovery timer (TODO: implement properly with DlangUI timers in future)

        window.show();
    }

    void setupEventHandlers() {
    auto contentStack = window.mainWidget.childById!FrameLayout("contentStack");
    auto sidebar = window.mainWidget.childById("sidebar");

        auto showPage = delegate(int index, bool showSidebar) {
        logInfo("Switching to page index " ~ to!string(index));
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

        auto bindClick = delegate(string id, bool delegate(Widget) handler) {
            auto btn = cast(Button)window.mainWidget.childById(id);
            if (btn)
                btn.click = handler;
        };

        bindClick("btnHome", delegate(Widget w) { showPage(0, false); return true; });
        bindClick("btnAIConfig", delegate(Widget w) { showAIConfigDialog(window, selectedRepoPath); return true; });
        bindClick("navHome", delegate(Widget w) { showPage(0, false); return true; });
        bindClick("btnChoiceBrowse", delegate(Widget w) { showPage(1, true); return true; });
        bindClick("navTemplates", delegate(Widget w) { showPage(1, true); return true; });
        bindClick("btnChoiceTools", delegate(Widget w) { showPage(3, true); return true; });
        bindClick("navDashboard", delegate(Widget w) { showPage(3, true); return true; });
        bindClick("navProject", delegate(Widget w) { showPage(2, true); refreshProject(); return true; });
        bindClick("navWorkflowTemplates", delegate(Widget w) { showPage(4, true); return true; });
        bindClick("btnChoiceWorkflowTemplates", delegate(Widget w) { showPage(4, true); return true; });
        bindClick("btnChoiceInstall", delegate(Widget w) { showPage(6, true); return true; });
        bindClick("btnInstallIacDocs", delegate(Widget w) {
            openUrlInBrowser("https://docs.devcentr.org/general-knowledge/latest/explanation/infrastructure/iac.html");
            return true;
        });
        bindClick("btnInstallIac", delegate(Widget w) { bootstrapOpenTofuHere(); return true; });
        bindClick("btnInstallTech", delegate(Widget w) {
            window.showMessageBox(
                UIString.fromRaw("Project technologies"d),
                UIString.fromRaw("Frameworks and runtimes will be available here. Use the sidebar to open Project Analysis or Infra."d)
            );
            return true;
        });
        bindClick("navInfra", delegate(Widget w) { showPage(5, true); return true; });
        bindClick("btnRefreshInfra", delegate(Widget w) { refreshInfra(); return true; });
        bindClick("btnInfraDocs", delegate(Widget w) {
            openUrlInBrowser("https://docs.devcentr.org/general-knowledge/latest/explanation/infrastructure/iac.html");
            return true;
        });
        bindClick("btnRefreshWorkflowTemplates", delegate(Widget w) {
            refreshWorkflowTemplates();
            return true;
        });
        bindClick("btnInstallWorkflowTemplate", delegate(Widget w) {
            auto list = cast(ListWidget)window.mainWidget.childById("listWorkflowTemplates");
            if (list is null)
                return true;
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
        });
        bindClick("btnOpenWorkflowStore", delegate(Widget w) { openWorkflowTemplatesStore(); return true; });
        bindClick("btnUpdate", delegate(Widget w) {
            bool updated = installer.updateCache(true);
            refreshTemplates();
            window.showMessageBox(UIString.fromRaw("Status"d), UIString.fromRaw(updated ? "Cache Updated"d : "Up to Date"d));
            return true;
        });

        auto searchEdit = cast(EditLine)window.mainWidget.childById("searchRepos");
        if (searchEdit) {
            searchEdit.contentChange = delegate(EditableContent content) {
                refreshRepoList();
            };
        }

        bindClick("btnRefreshRepos", delegate(Widget w) {
            allRepos = scanCodeRoot(codeRoot);
            refreshRepoList();
            return true;
        });
        bindClick("btnOpenGitGui", delegate(Widget w) {
            if (selectedRepoPath.length > 0)
                showGitGuiSelectorDialog(window, selectedRepoPath, repoTools);
            else
                window.showMessageBox(UIString.fromRaw("Git Viewer"d), UIString.fromRaw("Select a repository first."d));
            return true;
        });
        bindClick("btnDiscoverTools", delegate(Widget w) {
            string[] roots;
            foreach (r; allRepos)
                roots ~= r.fullPath;
            repoTools.discoverExternalTools(roots);
            refreshToolsPanel();
            return true;
        });
        bindClick("btnInstall", delegate(Widget w) {
            auto list = cast(ListWidget)window.mainWidget.childById("listTemplates");
            if (list && list.selectedItemIndex >= 0) {
                // TODO: proper install
            }
            return true;
        });
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
        browserItems.length = 0;

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
                browserItems ~= BrowserItem(BrowserItemType.host, repo.host, "", RepoNode.init);
                lastHost = repo.host;
                lastOwner = ""; // reset owner on new host
            }

            // Insert owner header
            if (repo.owner != lastOwner)
            {
                string ownerPrefix = repo.isClone ? "  ▸ .clones/" : "  ▸ ";
                repoAdapter.add(to!dstring(ownerPrefix ~ repo.owner));
                browserItems ~= BrowserItem(BrowserItemType.owner, repo.host, repo.owner, RepoNode.init);
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
            browserItems ~= BrowserItem(BrowserItemType.repo, repo.host, repo.owner, repo);
        }
    }

    void refreshToolsPanel() {
        // --- Setup Hallmark Strip ---
        auto hallmarkContainer = window.mainWidget.childById!VerticalLayout("hallmarkContainer");
        if (hallmarkContainer) {
            hallmarkContainer.removeAllChildren();
            if (selectedRepoPath.length > 0) {
                hallmarkContainer.addChild(createRepoToolbar(window, selectedRepoPath, installer, repoTools));
            }
        }

        // --- Setup Org Profile Panel (when owner/org selected) ---
        auto orgProfileContainer = window.mainWidget.childById!VerticalLayout("orgProfileContainer");
        if (orgProfileContainer) {
            orgProfileContainer.removeAllChildren();
            if (selectedOwner.length > 0 && selectedHost.length > 0 && selectedRepoPath.length == 0) {
                auto profile = getProviderForHost(vcsProfiles, selectedHost);
                if (hasOrgProfileSupport(profile)) {
                    auto box = new VerticalLayout();
                    box.layoutWidth(FILL_PARENT).padding(Rect(10, 10, 10, 10)).backgroundColor(0x222222);
                    box.addChild(new TextWidget(null, "Organization Profile"d).fontSize(14).fontWeight(700));
                    string infoText = "Provider: " ~ profile.displayName ~ " — Profile READMEs in " ~ profile.orgProfile.publicRepo;
                    if (profile.orgProfile.privateRepo.length > 0) infoText ~= " / " ~ profile.orgProfile.privateRepo;
                    auto infoW = new TextWidget(null, to!dstring(infoText));
                    infoW.textColor = 0xAAAAAA; infoW.fontSize = 10;
                    box.addChild(infoW);
                    auto btnRow1 = new HorizontalLayout();
                    btnRow1.padding(Rect(0, 8, 0, 0));
                    auto btnPublic = new Button(null, "Open Public Profile"d);
                    btnPublic.click = delegate(Widget w) {
                        string url = orgProfilePublicUrl(profile, selectedOwner);
                        if (url.length > 0) openUrlInBrowser(url);
                        return true;
                    };
                    btnRow1.addChild(btnPublic);
                    auto btnMember = new Button(null, "Open Private Profile"d);
                    btnMember.click = delegate(Widget w) {
                        string url = orgProfileMemberUrl(profile, selectedOwner);
                        if (url.length > 0) openUrlInBrowser(url);
                        return true;
                    };
                    btnRow1.addChild(btnMember);
                    box.addChild(btnRow1);
                    auto btnRow2 = new HorizontalLayout();
                    btnRow2.padding(Rect(0, 4, 0, 0));
                    auto btnOpenPublicRepo = new Button(null, "Open Public Profile Repo"d);
                    btnOpenPublicRepo.click = delegate(Widget w) {
                        string url = orgProfilePublicRepoUrl(profile, selectedOwner);
                        if (url.length > 0) openUrlInBrowser(url);
                        return true;
                    };
                    btnRow2.addChild(btnOpenPublicRepo);
                    if (profile.orgProfile.privateRepo.length > 0) {
                        auto btnOpenPrivateRepo = new Button(null, "Open Private Profile Repo"d);
                        btnOpenPrivateRepo.click = delegate(Widget w) {
                            string url = orgProfilePrivateRepoUrl(profile, selectedOwner);
                            if (url.length > 0) openUrlInBrowser(url);
                            return true;
                        };
                        btnRow2.addChild(btnOpenPrivateRepo);
                    }
                    box.addChild(btnRow2);
                    auto btnHighlight = new Button(null, "Highlight Profile Repos in Tree"d);
                    btnHighlight.padding(Rect(0, 8, 0, 0));
                    btnHighlight.click = delegate(Widget w) {
                        highlightProfileReposInTree(profile);
                        return true;
                    };
                    box.addChild(btnHighlight);
                    orgProfileContainer.addChild(box);
                }
            }
        }
        
        auto previewContainer = window.mainWidget.childById!VerticalLayout("repoPreviewContainer");
        if (previewContainer)
        {
            previewContainer.removeAllChildren();
            if (selectedRepoPath.length > 0)
            {
                auto tabs = new TabWidget();
                tabs.layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT);

                auto overview = new ScrollWidget();
                overview.layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT);
                auto overviewContent = new VerticalLayout();
                overviewContent.layoutWidth(FILL_PARENT).padding(10);
                auto title = new TextWidget(null, "Repository Details"d);
                title.fontSize(14).fontWeight(700).margins(Rect(0, 0, 0, 6));
                overviewContent.addChild(title);
                auto repoText = new TextWidget(null, "Repository: "d ~ to!dstring(selectedRepoPath));
                repoText.textColor = 0xCCCCCC;
                overviewContent.addChild(repoText);
                auto docsRow = new HorizontalLayout();
                docsRow.layoutWidth(FILL_PARENT).margins(Rect(0, 8, 0, 8));
                auto aiBtn = new Button(null, "Open AI Config"d);
                aiBtn.click = delegate(Widget w) { showAIConfigDialog(window, selectedRepoPath); return true; };
                docsRow.addChild(aiBtn);
                auto skillsBtn = new Button(null, "Open Context7 Skills Browser"d);
                skillsBtn.click = delegate(Widget w) { openUrlInBrowser("https://context7.com/skills/"); return true; };
                docsRow.addChild(skillsBtn);
                overviewContent.addChild(docsRow);
                auto note = new TextWidget(null,
                    "Use the Terminal tab for repo-scoped commands. Use AI Config for Context7 MCP, skills, and AI provider setup."d);
                note.textColor = 0xAAAAAA;
                overviewContent.addChild(note);
                overview.contentWidget = overviewContent;
                tabs.addTab(overview, "Overview"d);

                auto terminal = new RepoTerminalWidget(selectedRepoPath, repoTools);
                tabs.addTab(terminal, "Terminal"d);
                previewContainer.addChild(tabs);
            }
            else
            {
                auto repoText = new TextWidget(null,
                    selectedOwner.length > 0 && selectedHost.length > 0
                        ? UIString.fromRaw("Organization: "d ~ to!dstring(selectedHost) ~ "/"d ~ to!dstring(selectedOwner))
                        : UIString.fromRaw("Select a repository or organization to view details."d));
                repoText.alignment(Align.Center).textColor(0xAAAAAA);
                previewContainer.addChild(repoText);
            }
        }

        // --- Setup Tools List ---
        auto toolsList = window.mainWidget.childById!ListWidget("listAttachedTools");
        if (!toolsList) return;

        auto adapter = cast(StringListAdapter) toolsList.adapter;
        if (!adapter) return;

        adapter.clear();

        if (selectedRepoPath.length == 0)
        {
            adapter.add(to!dstring(selectedOwner.length > 0 ? "Select a repo under this org to see attached tools."d : "Select a repo to see tools"d));
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

    void highlightProfileReposInTree(VCSProviderProfile profile) {
        string publicPath = buildPath(codeRoot, selectedHost, selectedOwner, profile.orgProfile.publicRepo);
        string privatePath = profile.orgProfile.privateRepo.length > 0
            ? buildPath(codeRoot, selectedHost, selectedOwner, profile.orgProfile.privateRepo) : "";
        int highlightIdx = -1;
        foreach (i, bi; browserItems) {
            if (bi.type == BrowserItemType.repo && bi.repo.host == selectedHost && bi.repo.owner == selectedOwner) {
                if (bi.repo.fullPath == publicPath || (privatePath.length > 0 && bi.repo.fullPath == privatePath)) {
                    highlightIdx = cast(int)i;
                    break;
                }
            }
        }
        if (highlightIdx >= 0) {
            auto listRepos = window.mainWidget.childById!ListWidget("listRepos");
            if (listRepos) {
                listRepos.selectedItemIndex = highlightIdx;
                selectedRepoPath = browserItems[highlightIdx].repo.fullPath;
                refreshToolsPanel();
            }
        } else {
            window.showMessageBox(UIString.fromRaw("Profile Repos"d), UIString.fromRaw("No local copy of profile repos found. Clone "d ~ to!dstring(profile.orgProfile.publicRepo) ~ " or "d ~ to!dstring(profile.orgProfile.privateRepo) ~ " first."d));
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
        std.file.write(buildPath(infraDir, "main.tofu"), mainContent);
        std.file.write(buildPath(infraDir, "variables.tofu"), varsContent);
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
