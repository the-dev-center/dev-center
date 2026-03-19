module modules.infra.discovery;

import modules.iac.discovery : IacDiscoveryResult, IacBase, IacDependency, IacTool, discoverIacInRepo, resolveModuleSourceToPath, ResolvedModulePath;
import sdlang;
import std.algorithm : canFind;
import std.array : array;
import std.file : exists, readText;
import std.path : absolutePath, baseName, buildPath, dirName;
import std.string : strip;
import std.typecons : Nullable, nullable;

/// How the Infra discovery module is being used.
enum InfraDiscoveryMode
{
    StandaloneWindow, /// User-selected folder, independent browser.
    IntegratedPerRepo /// Scoped to the current repository in DevCentr.
}

/// A service that may have infra impact (CI, cloud runtime, etc.).
struct InfraService
{
    string id;
    string name;
    string shortDescription;
    string homepage;
    string docs;
    string devcentrDoc; /// Link or xref to a DevCentr docs page.
    bool cliInstalled;  /// Whether the corresponding CLI/tooling is detected.
}

/// A white-box placeholder for infra we know exists but haven't expanded.
struct WhiteBox
{
    string label;      /// For example "Org-wide IaC (etc.)" or service name.
    string description;
    string kind;       /// "iac-etc" or "service"
}

/// A node in the scoped IaC tree. We model only the current scope and its upstream dependency chain.
/// Siblings, parents, and grandparents are not modeled; they are represented by a single etc block per node.
struct IacScopedNode
{
    string repoRoot;       /// Absolute repo root for this node.
    string basePath;      /// Absolute path of the IaC base (directory or repo root).
    string displayName;   /// Human-friendly label for the UI.
    IacBase base;         /// Snapshot of the IaC base at this node.
    IacScopedNode[] upstream; /// Only upstream dependencies we follow (no siblings/parents/grandparents).
    WhiteBox etcBlock;    /// One block per node: unrelated scopes at this level (uncles, grand-uncles, siblings).
}

/// Summary of infra discovered for the current scope.
struct InfraDiscoverySummary
{
    InfraDiscoveryMode mode;
    string scopeRoot;            /// Folder or repo root that was scanned.
    string searchRoot;           /// Root used to resolve upstream (e.g. org root); same as scopeRoot if not set.
    IacDiscoveryResult iac;     /// Flat IaC result for the scope (all bases in scope repo).
    IacScopedNode[] scopedIacRoots; /// One tree root per base in the current scope; each has upstream[] and etcBlock.
    InfraService[] services;     /// Services inferred from recognition profiles.
}

/// Build the scoped IaC tree: current scope + upstream dependencies only. At each node, attach one "etc" block
/// for unrelated scopes (siblings, uncles, grand-uncles). Does not model siblings, parents, or grandparents.
void buildScopedIacTree(string scopeRoot, string searchRoot, ref IacScopedNode[] roots, size_t maxDepth = 32)
{
    auto iacResult = discoverIacInRepo(scopeRoot);
    if (iacResult.bases.length == 0) return;
    string[string] visited;
    foreach (ref base; iacResult.bases)
    {
        IacScopedNode node;
        node.repoRoot = base.repoRoot;
        node.basePath = base.basePath;
        node.displayName = base.displayName;
        node.base = base;
        node.etcBlock.label = "Other services";
        node.etcBlock.description = "Other repos, siblings, or parent/grandparent scopes at this level are not modeled. Click to load more (may take a long time).";
        node.etcBlock.kind = "iac-etc";
        buildUpstreamNodes(base, searchRoot, node.upstream, visited, 0, maxDepth);
        roots ~= node;
    }
}

private void buildUpstreamNodes(ref IacBase base, string searchRoot, ref IacScopedNode[] upstreamNodes, ref string[string] visited, size_t depth, size_t maxDepth)
{
    if (depth >= maxDepth) return;
    foreach (dep; base.deps)
    {
        if (dep.kind != "module") continue;
        auto fromFileAbs = buildPath(base.repoRoot, dep.fromFile);
        auto resolved = resolveModuleSourceToPath(fromFileAbs, dep.target, searchRoot);
        if (resolved.isNull()) continue;
        auto r = resolved.get();
        auto key = r.repoRoot ~ "|" ~ r.basePath;
        if (key in visited) continue;
        visited[key] = "1";
        auto upstreamIac = discoverIacInRepo(r.repoRoot);
        IacBase upstreamBase;
        bool found = false;
        foreach (b; upstreamIac.bases)
        {
            if (b.basePath == r.basePath || (r.basePath.length >= r.repoRoot.length && b.basePath.length > 0))
            {
                upstreamBase = b;
                found = true;
                break;
            }
        }
        if (!found && upstreamIac.bases.length > 0) upstreamBase = upstreamIac.bases[0];
        if (!found && upstreamIac.bases.length == 0) continue;
        IacScopedNode upNode;
        upNode.repoRoot = r.repoRoot;
        upNode.basePath = upstreamBase.basePath;
        upNode.displayName = upstreamBase.displayName;
        upNode.base = upstreamBase;
        upNode.etcBlock.label = "Other services";
        upNode.etcBlock.description = "Siblings, uncles, and other scopes at this level are not modeled. Click to load (may take a long time).";
        upNode.etcBlock.kind = "iac-etc";
        buildUpstreamNodes(upstreamBase, searchRoot, upNode.upstream, visited, depth + 1, maxDepth);
        upstreamNodes ~= upNode;
    }
}

/// Discover infra for a single repo or folder, including:
/// - IaC subset for this scope and its upstream dependency tree only (no siblings/parents/grandparents).
/// - One "etc." block per node for unrelated scopes.
/// - Service descriptions (white boxes when CLIs are missing).
InfraDiscoverySummary discoverInfra(string rootPath, InfraDiscoveryMode mode, string searchRoot = null)
{
    auto absRoot = absolutePath(rootPath);
    auto effectiveSearch = (searchRoot.length > 0) ? absolutePath(searchRoot) : absRoot;
    InfraDiscoverySummary summary;
    summary.mode = mode;
    summary.scopeRoot = absRoot;
    summary.searchRoot = effectiveSearch;
    summary.iac = discoverIacInRepo(absRoot);
    buildScopedIacTree(absRoot, effectiveSearch, summary.scopedIacRoots);
    summary.services = loadInfraServices();
    return summary;
}

/// Load service descriptions from an SDL definition file.
InfraService[] loadInfraServices()
{
    InfraService[] result;

    auto path = buildPath("src", "modules", "services", "descriptions.sdl");
    if (!exists(path))
    {
        return result;
    }

    Tag root;
    try
    {
        root = parseSource(readText(path), path);
    }
    catch (Exception)
    {
        return result;
    }

    auto servicesTag = root.getTag("services");
    if (servicesTag is null)
    {
        return result;
    }

    foreach (serviceTag; servicesTag.all.tags)
    {
        if (serviceTag.name != "service")
        {
            continue;
        }

        InfraService svc;
        svc.id = serviceTag.getTag("id") !is null && serviceTag.getTag("id").values.length > 0
            ? serviceTag.getTag("id").values[0].get!string
            : "";
        auto nameTag = serviceTag.getTag("name");
        if (nameTag !is null && nameTag.values.length > 0)
        {
            svc.name = nameTag.values[0].get!string;
        }
        auto descTag = serviceTag.getTag("shortDescription");
        if (descTag !is null && descTag.values.length > 0)
        {
            svc.shortDescription = descTag.values[0].get!string;
        }
        auto homepageTag = serviceTag.getTag("homepage");
        if (homepageTag !is null && homepageTag.values.length > 0)
        {
            svc.homepage = homepageTag.values[0].get!string;
        }
        auto docsTag = serviceTag.getTag("docs");
        if (docsTag !is null && docsTag.values.length > 0)
        {
            svc.docs = docsTag.values[0].get!string;
        }
        auto devcentrDocTag = serviceTag.getTag("devcentrDoc");
        if (devcentrDocTag !is null && devcentrDocTag.values.length > 0)
        {
            svc.devcentrDoc = devcentrDocTag.values[0].get!string;
        }

        // For now, CLI installation is unknown; UI should treat this as "not installed".
        svc.cliInstalled = false;

        if (svc.id.length != 0)
        {
            result ~= svc;
        }
    }

    return result;
}

