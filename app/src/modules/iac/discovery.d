module modules.iac.discovery;

import std.algorithm : canFind;
import std.array : array, appender;
import std.file : DirEntry, SpanMode, dirEntries, exists, isDir, readText;
import std.path : absolutePath, baseName, buildPath, canonicalizePath, dirName, isAbsolute, relativePath, extension;
import std.string : strip, startsWith, toLower;
import std.typecons : Nullable, nullable;

/// Type of IaC tooling detected for a base.
enum IacTool
{
    unknown,
    terraform,   // Covers both Terraform and OpenTofu style HCL
    pulumi,
    cloudformation,
    bicep,
    ansible
}

/// A dependency edge inside an IaC base (for example a module source).
struct IacDependency
{
    string fromFile;   /// Relative path to the IaC file that declares the dependency.
    string kind;       /// Short label such as "module" or "remote_state".
    string target;     /// The raw target string (for example module source).
}

/// A detected IaC base within a repository.
struct IacBase
{
    string repoRoot;       /// Absolute path of the repository root.
    string basePath;       /// Absolute path of the IaC base directory or repo root.
    string displayName;    /// Human-friendly name (for example "infra/" or repo name).
    IacTool tool;          /// Dominant IaC tool detected for this base.
    string[] configFiles;  /// Relative paths (from repo root) of IaC config files in this base.
    IacDependency[] deps;  /// Dependency edges discovered from config files.
}

/// Summary of IaC detected in a single repository.
struct IacDiscoveryResult
{
    string repoRoot;   /// Absolute repo root (normalized).
    string repoName;   /// Base name of the repo.
    IacBase[] bases;   /// All IaC bases found in this repo.
}

/// Result of resolving a module source to a local path (repo + optional base subpath).
struct ResolvedModulePath
{
    string repoRoot;   /// Absolute path of the repository root.
    string basePath;   /// Absolute path of the IaC base directory (may equal repoRoot).
}

/// Try to resolve a Terraform/OpenTofu module source to a local repo and base path.
///
/// Only local relative paths (e.g. "./foo", "../other-repo/infra") are resolved.
/// The resolved path must lie under searchRoot. Returns null if the source is
/// remote (git URL, registry) or not found under searchRoot.
Nullable!ResolvedModulePath resolveModuleSourceToPath(
    string basePath,
    string moduleSource,
    string searchRoot)
{
    import std.path : dirName, expandPath, isAbsolute;
    auto trimmed = moduleSource.strip();
    if (trimmed.length == 0)
    {
        return Nullable!ResolvedModulePath.init;
    }
    // Only resolve local relative paths.
    if (trimmed.startsWith("http://") || trimmed.startsWith("https://") ||
        trimmed.startsWith("git::") || trimmed.startsWith("github.com") ||
        trimmed.startsWith("registry.terraform.io") || isAbsolute(trimmed))
    {
        return Nullable!ResolvedModulePath.init;
    }
    auto baseDir = dirName(basePath);
    if (baseDir.length == 0)
    {
        baseDir = ".";
    }
    auto combined = buildPath(baseDir, trimmed);
    string resolved;
    try
    {
        resolved = absolutePath(expandPath(combined));
    }
    catch (Exception)
    {
        return Nullable!ResolvedModulePath.init;
    }
    auto normSearch = canonicalizePath(absolutePath(searchRoot));
    resolved = canonicalizePath(resolved);
    // Resolved must be under search root.
    if (normSearch.length == 0 || resolved.length <= normSearch.length)
    {
        return Nullable!ResolvedModulePath.init;
    }
    if (resolved[0 .. normSearch.length] != normSearch)
    {
        return Nullable!ResolvedModulePath.init;
    }
    if (resolved.length > normSearch.length && resolved[normSearch.length] != '/')
    {
        return Nullable!ResolvedModulePath.init;
    }
    // Treat resolved as repo root (directory containing IaC). Caller may use discoverIacInRepo to get bases.
    if (!exists(resolved) || !isDir(resolved))
    {
        auto parent = dirName(resolved);
        if (exists(parent) && isDir(parent))
        {
            resolved = parent;
        }
        else
        {
            return Nullable!ResolvedModulePath.init;
        }
    }
    ResolvedModulePath result;
    result.repoRoot = resolved;
    result.basePath = resolved;
    return nullable(result);
}

/// Discover IaC bases and simple dependency trees in a single repository.
///
/// This function applies the following assumptions:
/// - It only treats the repo root and its immediate child directories as IaC base candidates.
/// - It skips Git submodules to avoid double-counting their IaC inside the parent.
IacDiscoveryResult discoverIacInRepo(string repoRoot)
{
    auto absoluteRoot = absolutePath(repoRoot);
    string normalizedRoot = absoluteRoot;

    auto bases = discoverBases(normalizedRoot);
    return IacDiscoveryResult(normalizedRoot, baseName(normalizedRoot), bases);
}

/// Find IaC bases in the given repository root.
private IacBase[] discoverBases(string repoRoot)
{
    IacBase[] bases;

    // Candidate 1: the repo root itself.
    discoverBaseInDirectory(repoRoot, repoRoot, bases);

    // Candidate 2: one level of child directories, excluding submodules.
    foreach (DirEntry entry; dirEntries(repoRoot, SpanMode.shallow))
    {
        if (!entry.isDir)
        {
            continue;
        }

        auto childPath = entry.name;
        if (isGitSubmodule(childPath))
        {
            // Treat submodules as their own repos; do not scan them as part of this repo's bases.
            continue;
        }

        discoverBaseInDirectory(repoRoot, childPath, bases);
    }

    return bases;
}

/// Try to detect an IaC base in a single directory.
private void discoverBaseInDirectory(string repoRoot, string dirPath, ref IacBase[] bases)
{
    string[] iacFiles = collectIacFiles(repoRoot, dirPath);
    if (iacFiles.length == 0)
    {
        return;
    }

    auto tool = inferToolForFiles(iacFiles);
    auto deps = collectDependencies(repoRoot, iacFiles, tool);
    string display;

    if (dirPath == repoRoot)
    {
        display = baseName(repoRoot) ~ " (root)";
    }
    else
    {
        auto rel = relativePath(dirPath, repoRoot);
        display = canonicalizePath(rel) ~ "/";
    }

    IacBase base;
    base.repoRoot = repoRoot;
    base.basePath = dirPath;
    base.displayName = display;
    base.tool = tool;
    base.configFiles = iacFiles;
    base.deps = deps;
    bases ~= base;
}

/// Collect IaC config files that live directly under the directory or exactly one level deeper.
private string[] collectIacFiles(string repoRoot, string dirPath)
{
    auto files = appender!string[];

    // Files directly in dirPath.
    foreach (DirEntry entry; dirEntries(dirPath, SpanMode.shallow))
    {
        if (entry.isDir)
        {
            continue;
        }
        if (isIacFile(entry.name))
        {
            auto rel = relativePath(entry.name, repoRoot);
            files ~= canonicalizePath(rel);
        }
    }

    // Files one level below dirPath.
    foreach (DirEntry childDir; dirEntries(dirPath, SpanMode.shallow))
    {
        if (!childDir.isDir)
        {
            continue;
        }
        foreach (DirEntry entry; dirEntries(childDir.name, SpanMode.shallow))
        {
            if (entry.isDir)
            {
                continue;
            }
            if (isIacFile(entry.name))
            {
                auto rel = relativePath(entry.name, repoRoot);
                files ~= canonicalizePath(rel);
            }
        }
    }

    auto result = files;
    result.sort;
    return result;
}

/// Detect whether a given file path looks like an IaC config file.
private bool isIacFile(string path)
{
    auto name = baseName(path);
    auto ext = extension(name).toLower();

    // OpenTofu / Terraform / Terragrunt
    if (ext == ".tf" || ext == ".tf.json" || ext == ".tofu" || ext == ".tofu.json")
    {
        return true;
    }
    if (name == "terragrunt.hcl")
    {
        return true;
    }

    // Pulumi
    if (name.startsWith("Pulumi.") && (name.endsWith(".yaml") || name.endsWith(".yml")))
    {
        return true;
    }
    if (name == "Pulumi.yaml" || name == "Pulumi.yml")
    {
        return true;
    }

    // CloudFormation (very heuristic)
    if (name == "template.yaml" || name == "template.yml")
    {
        return true;
    }

    // Bicep
    if (ext == ".bicep")
    {
        return true;
    }

    // Ansible (simple heuristic: playbook-like files)
    if ((ext == ".yaml" || ext == ".yml") && (name.canFind("playbook") || name.canFind("ansible")))
    {
        return true;
    }

    return false;
}

/// Infer the dominant IaC tool from the list of config files.
private IacTool inferToolForFiles(const string[] files)
{
    bool hasTf = false;
    bool hasPulumi = false;
    bool hasCf = false;
    bool hasBicep = false;
    bool hasAnsible = false;

    foreach (file; files)
    {
        auto name = baseName(file);
        auto ext = extension(name).toLower();

        if (ext == ".tf" || ext == ".tf.json" || ext == ".tofu" || ext == ".tofu.json" || name == "terragrunt.hcl")
        {
            hasTf = true;
        }
        if (name == "Pulumi.yaml" || name == "Pulumi.yml" ||
            (name.startsWith("Pulumi.") && (name.endsWith(".yaml") || name.endsWith(".yml"))))
        {
            hasPulumi = true;
        }
        if (name == "template.yaml" || name == "template.yml")
        {
            hasCf = true;
        }
        if (ext == ".bicep")
        {
            hasBicep = true;
        }
        if ((ext == ".yaml" || ext == ".yml") && (name.canFind("playbook") || name.canFind("ansible")))
        {
            hasAnsible = true;
        }
    }

    if (hasTf) return IacTool.terraform;
    if (hasPulumi) return IacTool.pulumi;
    if (hasCf) return IacTool.cloudformation;
    if (hasBicep) return IacTool.bicep;
    if (hasAnsible) return IacTool.ansible;
    return IacTool.unknown;
}

/// Collect simple dependency edges based on the dominant tool.
private IacDependency[] collectDependencies(string repoRoot, const string[] configFiles, IacTool tool)
{
    IacDependency[] deps;

    final switch (tool)
    {
        case IacTool.terraform:
            foreach (relPath; configFiles)
            {
                auto absPath = buildPath(repoRoot, relPath);
                auto content = safeReadText(absPath);
                if (content.length == 0)
                {
                    continue;
                }
                deps ~= extractTerraformDeps(relPath, content);
            }
            break;
        case IacTool.pulumi:
        case IacTool.cloudformation:
        case IacTool.bicep:
        case IacTool.ansible:
        case IacTool.unknown:
            break;
    }

    return deps;
}

/// Extract module-style dependencies from Terraform / OpenTofu HCL content.
private IacDependency[] extractTerraformDeps(string relPath, const string content)
{
    IacDependency[] deps;
    auto lowered = content.toLower();

    // Very small and forgiving scan:
    // - Look for lines starting with "module" and then find "source =".
    auto lines = content.splitLines();
    foreach (line; lines)
    {
        auto trimmed = line.strip();
        if (trimmed.length == 0)
        {
            continue;
        }
        auto lowerLine = trimmed.toLower();
        if (!lowerLine.startsWith("module"))
        {
            continue;
        }

        // Look for "source" on the same line or as a very simple follow-up.
        string candidate = trimmed;
        if (!candidate.canFind("source"))
        {
            continue;
        }

        auto sourceIndex = candidate.indexOf("source");
        if (sourceIndex == -1)
        {
            continue;
        }

        auto after = candidate[sourceIndex .. $];
        auto eqPos = after.indexOf('=');
        if (eqPos == -1)
        {
            continue;
        }
        auto valuePart = after[cast(size_t)eqPos + 1 .. $].strip();
        if (valuePart.length == 0)
        {
            continue;
        }

        // Strip surrounding quotes if present.
        if ((valuePart[0] == '"' || valuePart[0] == '\'') && valuePart.length >= 2)
        {
            auto quote = valuePart[0];
            auto last = valuePart.length - 1;
            if (valuePart[last] == quote)
            {
                valuePart = valuePart[1 .. last];
            }
        }

        if (valuePart.length == 0)
        {
            continue;
        }

        IacDependency dep;
        dep.fromFile = relPath;
        dep.kind = "module";
        dep.target = valuePart;
        deps ~= dep;
    }

    return deps;
}

/// Detect whether a path is a Git submodule (has a .git file that points elsewhere).
private bool isGitSubmodule(string dirPath)
{
    auto dotGitPath = buildPath(dirPath, ".git");
    if (!exists(dotGitPath) || isDir(dotGitPath))
    {
        // A directory .git means this is a normal repo root, not a submodule entry.
        return false;
    }
    return true;
}

/// Canonicalize path separators to forward slashes for consistency.
private string canonicalizePath(string path)
{
    char[] result = path.dup;
    foreach (ref c; result)
    {
        if (c == '\\')
        {
            c = '/';
        }
    }
    return result.idup;
}

/// Read a text file safely; return an empty string on error.
private string safeReadText(string path)
{
    try
    {
        return readText(path);
    }
    catch (Exception)
    {
        return "";
    }
}

