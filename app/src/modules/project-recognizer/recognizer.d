module modules.project_recognizer.recognizer;

import std.algorithm.searching : all, any, canFind;
import std.algorithm.sorting : sort;
import std.array : array, empty;
import std.datetime : Clock, SysTime;
import std.exception : enforce;
import std.file;
import std.json : JSONType, JSONValue, parseJSON;
import std.path : absolutePath, baseName, buildPath, extension, globMatch, isAbsolute, relativePath;
import std.string : indexOf, splitLines, strip, toLower;
import std.typecons : Nullable, nullable;
import std.digest.sha : sha1Of;
import std.digest : toHexString;
import std.conv : to;

/// Maximum file size (in bytes) to scan when checking for keyword matches.
immutable ulong maxKeywordScanBytes = 1_048_576; // 1 MiB

/// Rules that describe how to validate a dependency manifest file.
struct ManifestRule
{
    string pathPattern;
    string format = "text"; // Supported: "text", "json"
    string[] required;      // Dependencies that must be present
    string[] anyOf;         // At least one dependency that must be present (if provided)
    string[] dependencyFields; // For JSON manifests: fields that contain dependency maps
}

/// Recognition rule that describes a single technology stack signature.
struct RecognitionRule
{
    string name;
    string description;
    string parent;
    string[] allOfFiles;     // Patterns where each must have at least one matching file
    string[] anyOfFiles;     // Patterns where at least one must match
    string[] excludedFiles;  // Patterns that, if matched, invalidate the rule
    string[] keywords;       // Keywords that must be found in the project
    ManifestRule[] manifests;
}

/// Options that configure how the recognizer operates.
struct RecognizerOptions
{
    string cacheRoot = buildDefaultCacheRoot();
    string architectureFormat = "json"; // Currently only JSON is implemented
    string recognizerVersion = "0.1.0";
    bool includeInactiveFiles = true;

    static string buildDefaultCacheRoot() @safe
    {
        return buildPath(".dev-center", "cache", "recognizer");
    }
}

/// Evidence collected while validating a dependency manifest.
struct ManifestCheckResult
{
    string manifestPath;
    string format;
    string[] requiredSatisfied;
    string[] anySatisfied;

    JSONValue toJSON() const
    {
        JSONValue[string] obj;
        obj["path"] = JSONValue(manifestPath);
        obj["format"] = JSONValue(format);
        obj["requiredSatisfied"] = stringArrayToJSON(requiredSatisfied);
        obj["anySatisfied"] = stringArrayToJSON(anySatisfied);
        return JSONValue(obj);
    }

    static ManifestCheckResult fromJSON(const JSONValue value)
    {
        ManifestCheckResult result;
        result.manifestPath = jsonExpectString(value, "path");
        result.format = jsonGetStringOrDefault(value, "format", "text");
        result.requiredSatisfied = jsonGetStringArray(value, "requiredSatisfied");
        result.anySatisfied = jsonGetStringArray(value, "anySatisfied");
        return result;
    }
}

/// Result describing a matched technology stack within a project.
struct TechStackMatch
{
    string name;
    string description;
    string parent;
    string[] children;
    string[] relevantFiles;
    string[] aggregatedFiles;
    string[] keywordHits;
    ManifestCheckResult[] manifestEvidence;
    string[] inactiveFiles;

    JSONValue toJSON() const
    {
        JSONValue[string] obj;
        obj["name"] = JSONValue(name);
        if (!description.empty)
        {
            obj["description"] = JSONValue(description);
        }
        if (!parent.empty)
        {
            obj["parent"] = JSONValue(parent);
        }
        obj["relevantFiles"] = stringArrayToJSON(relevantFiles);
        obj["aggregatedFiles"] = stringArrayToJSON(aggregatedFiles);
        obj["keywordHits"] = stringArrayToJSON(keywordHits);

        JSONValue[] manifestArray;
        foreach (manifest; manifestEvidence)
        {
            manifestArray ~= manifest.toJSON();
        }
        obj["manifests"] = JSONValue(manifestArray);

        obj["children"] = stringArrayToJSON(children);
        obj["inactiveFiles"] = stringArrayToJSON(inactiveFiles);
        return JSONValue(obj);
    }

    static TechStackMatch fromJSON(const JSONValue value)
    {
        TechStackMatch match;
        match.name = jsonExpectString(value, "name");
        match.description = jsonGetStringOrDefault(value, "description");
        match.parent = jsonGetStringOrDefault(value, "parent");
        match.relevantFiles = jsonGetStringArray(value, "relevantFiles");
        match.aggregatedFiles = jsonGetStringArray(value, "aggregatedFiles");
        match.keywordHits = jsonGetStringArray(value, "keywordHits");

        auto manifestsValue = jsonGetArray(value, "manifests");
        foreach (manifestValue; manifestsValue)
        {
            match.manifestEvidence ~= ManifestCheckResult.fromJSON(manifestValue);
        }

        match.children = jsonGetStringArray(value, "children");
        match.inactiveFiles = jsonGetStringArray(value, "inactiveFiles");
        return match;
    }
}

/// Aggregated architecture model produced by the recognizer.
struct ArchitectureModel
{
    string projectRoot;
    string projectName;
    SysTime generatedAt;
    TechStackMatch[] techStacks;
    string[] unclassifiedFiles;
    string recognizerVersion;
    string cacheFile;

    JSONValue toJSON() const
    {
        JSONValue[string] obj;
        obj["projectRoot"] = JSONValue(projectRoot);
        obj["projectName"] = JSONValue(projectName);
        obj["generatedAt"] = JSONValue(generatedAt.toISOExtString());
        obj["recognizerVersion"] = JSONValue(recognizerVersion);
        if (!cacheFile.empty)
        {
            obj["cacheFile"] = JSONValue(cacheFile);
        }

        JSONValue[] stacks;
        foreach (stack; techStacks)
        {
            stacks ~= stack.toJSON();
        }
        obj["techStacks"] = JSONValue(stacks);
        obj["unclassifiedFiles"] = stringArrayToJSON(unclassifiedFiles);
        return JSONValue(obj);
    }

    static ArchitectureModel fromJSON(const JSONValue value)
    {
        ArchitectureModel model;
        model.projectRoot = jsonExpectString(value, "projectRoot");
        model.projectName = jsonExpectString(value, "projectName");
        model.generatedAt = SysTime.fromISOExtString(jsonExpectString(value, "generatedAt"));
        model.recognizerVersion = jsonGetStringOrDefault(value, "recognizerVersion");
        model.cacheFile = jsonGetStringOrDefault(value, "cacheFile");

        auto stacks = jsonGetArray(value, "techStacks");
        foreach (stackValue; stacks)
        {
            model.techStacks ~= TechStackMatch.fromJSON(stackValue);
        }
        model.unclassifiedFiles = jsonGetStringArray(value, "unclassifiedFiles");
        return model;
    }
}

/// Recognizer that inspects project directories and records technology stacks.
class ProjectRecognizer
{
    private RecognitionRule[] rules;
    private RecognizerOptions options;

    this(RecognitionRule[] rules, RecognizerOptions options = RecognizerOptions.init)
    {
        enforce(!rules.empty, "At least one recognition rule is required.");
        this.rules = rules.dup;
        this.options = patchOptions(options);
    }

    /// Loads a recognizer from a JSON configuration file.
    static ProjectRecognizer fromConfigFile(string configPath, RecognizerOptions options = RecognizerOptions.init)
    {
        enforce(exists(configPath), "Recognition rules file does not exist: "~ configPath);
        auto configContent = readText(configPath);
        auto json = parseJSON(configContent);
        auto rules = parseRuleContainer(json, configPath);
        return new ProjectRecognizer(rules, options);
    }

    /// Loads all recognizer profiles from a directory containing one JSON file per rule or rule set.
    static ProjectRecognizer fromProfilesDir(string profilesDir, RecognizerOptions options = RecognizerOptions.init)
    {
        enforce(exists(profilesDir), "Recognition profiles directory does not exist: " ~ profilesDir);
        enforce(isDir(profilesDir), "Recognition profiles path is not a directory: " ~ profilesDir);

        string[] profileFiles;
        foreach (entry; dirEntries(profilesDir, SpanMode.shallow))
        {
            if (entry.isDir)
            {
                continue;
            }

            auto ext = extension(entry.name).toLower();
            if (ext != ".json")
            {
                continue;
            }

            profileFiles ~= entry.name;
        }

        enforce(!profileFiles.empty, "No JSON profiles found in directory: " ~ profilesDir);
        sort(profileFiles);

        RecognitionRule[] allRules;
        foreach (profilePath; profileFiles)
        {
            auto content = readText(profilePath);
            auto json = parseJSON(content);
            auto rules = parseRuleContainer(json, profilePath);
            allRules ~= rules;
        }

        enforce(!allRules.empty, "No recognition rules could be loaded from profiles directory: " ~ profilesDir);
        return new ProjectRecognizer(allRules, options);
    }

    /// Runs recognition against the provided project root. Optionally persists the architecture model to cache.
    ArchitectureModel recognize(string projectRoot, bool saveToCache = true)
    {
        enforce(!projectRoot.empty, "Project root must not be empty.");

        auto absoluteRoot = absolutePath(projectRoot);
        auto projectFiles = collectProjectFiles(absoluteRoot);
        TechStackMatch[] matches;
        string[string] globallyClassified;

        foreach (rule; rules)
        {
            auto maybeMatch = evaluateRule(rule, absoluteRoot, projectFiles);
            if (maybeMatch.isNull)
            {
                continue;
            }

            auto match = maybeMatch.get();
            matches ~= match;

            foreach (filePath; match.relevantFiles)
            {
                globallyClassified[filePath] = filePath;
            }
        }

        buildHierarchy(matches);

        string[] unclassified;
        foreach (filePath; projectFiles)
        {
            if (filePath !in globallyClassified)
            {
                unclassified ~= filePath;
            }
        }
        sort(unclassified);

        auto model = ArchitectureModel(
            absoluteRoot,
            baseName(absoluteRoot),
            Clock.currTime(),
            matches,
            unclassified,
            options.recognizerVersion,
            ""
        );

        if (saveToCache)
        {
            auto cachePath = saveArchitectureModel(model);
            model.cacheFile = cachePath;
        }

        return model;
    }

    /// Attempts to load a cached architecture model for the provided project root.
    Nullable!ArchitectureModel loadCached(string projectRoot) const
    {
        enforce(!projectRoot.empty, "Project root must not be empty.");
        auto absoluteRoot = absolutePath(projectRoot);
        auto cacheDir = resolveCacheDirectory(absoluteRoot);
        auto cacheFile = buildPath(cacheDir, buildCacheFileName(absoluteRoot));

        if (!exists(cacheFile))
        {
            return Nullable!ArchitectureModel.init;
        }

        auto content = readText(cacheFile);
        auto json = parseJSON(content);
        auto model = ArchitectureModel.fromJSON(json);
        model.cacheFile = cacheFile;
        return nullable(model);
    }

    private RecognizerOptions patchOptions(RecognizerOptions opts) const @safe
    {
        RecognizerOptions patched = opts;
        if (patched.cacheRoot.length == 0)
        {
            patched.cacheRoot = RecognizerOptions.buildDefaultCacheRoot();
        }
        patched.architectureFormat = "json"; // Currently fixed
        if (patched.recognizerVersion.length == 0)
        {
            patched.recognizerVersion = "0.1.0";
        }
        return patched;
    }

    private static RecognitionRule[] parseRuleContainer(const JSONValue value, const string sourceLabel)
    {
        enforce(value.type == JSONType.object, "Recognition rule file must be a JSON object: " ~ sourceLabel);

        auto rulesField = jsonGetOptional(value, "rules");
        if (rulesField.type != JSONType.null_)
        {
            enforce(rulesField.type == JSONType.array, "JSON field `rules` must be an array in " ~ sourceLabel);
            RecognitionRule[] parsed;
            foreach (ruleValue; rulesField.array)
            {
                parsed ~= parseRule(ruleValue, sourceLabel);
            }
            enforce(!parsed.empty, "Recognition rule file did not contain any rules: " ~ sourceLabel);
            return parsed;
        }

        return [parseRule(value, sourceLabel)];
    }

    private static RecognitionRule parseRule(const JSONValue value, const string sourceLabel)
    {
        enforce(value.type == JSONType.object, "Recognition rule definition must be a JSON object in " ~ sourceLabel);

        RecognitionRule rule;
        rule.name = jsonExpectString(value, "name");
        rule.description = jsonGetStringOrDefault(value, "description");
        rule.parent = jsonGetStringOrDefault(value, "parent");
        rule.allOfFiles = jsonGetStringArray(value, "allOfFiles");
        rule.anyOfFiles = jsonGetStringArray(value, "anyOfFiles");
        rule.excludedFiles = jsonGetStringArray(value, "excludedFiles");
        rule.keywords = jsonGetStringArray(value, "keywords");

        auto manifests = jsonGetArray(value, "manifests");
        foreach (manifestValue; manifests)
        {
            rule.manifests ~= parseManifestRule(manifestValue, sourceLabel ~ " -> " ~ rule.name);
        }
        return rule;
    }

    private static ManifestRule parseManifestRule(const JSONValue value, const string sourceLabel)
    {
        enforce(value.type == JSONType.object, "Manifest rule definition must be a JSON object in " ~ sourceLabel);

        ManifestRule rule;
        rule.pathPattern = jsonExpectString(value, "pathPattern");
        rule.format = jsonGetStringOrDefault(value, "format", "text");
        rule.required = jsonGetStringArray(value, "required");
        rule.anyOf = jsonGetStringArray(value, "anyOf");
        rule.dependencyFields = jsonGetStringArray(value, "dependencyFields");
        return rule;
    }

    private Nullable!TechStackMatch evaluateRule(const RecognitionRule rule, string absoluteRoot, const string[] projectFiles) const
    {
        auto canonicalFiles = projectFiles;

        if (!rule.allOfFiles.empty && !allPatternsSatisfied(rule.allOfFiles, canonicalFiles))
        {
            return Nullable!TechStackMatch.init;
        }

        if (!rule.anyOfFiles.empty && !anyPatternSatisfied(rule.anyOfFiles, canonicalFiles))
        {
            return Nullable!TechStackMatch.init;
        }

        if (!rule.excludedFiles.empty && anyPatternSatisfied(rule.excludedFiles, canonicalFiles))
        {
            return Nullable!TechStackMatch.init;
        }

        string[] relevantFiles = collectMatchingFiles(rule.allOfFiles ~ rule.anyOfFiles, canonicalFiles);
        sort(relevantFiles);

        auto keywordHits = evaluateKeywordHits(rule.keywords, absoluteRoot, relevantFiles, canonicalFiles);
        if (!rule.keywords.empty && keywordHits.length != rule.keywords.length)
        {
            return Nullable!TechStackMatch.init;
        }

        ManifestCheckResult[] manifestEvidence;
        if (!rule.manifests.empty && !evaluateManifestRules(rule.manifests, absoluteRoot, canonicalFiles, manifestEvidence))
        {
            return Nullable!TechStackMatch.init;
        }

        string[] inactiveFiles;
        if (options.includeInactiveFiles)
        {
            inactiveFiles = buildInactiveFiles(canonicalFiles, relevantFiles);
        }

        TechStackMatch match;
        match.name = rule.name;
        match.description = rule.description;
        match.parent = rule.parent;
        match.relevantFiles = relevantFiles;
        match.keywordHits = keywordHits;
        match.manifestEvidence = manifestEvidence;
        match.inactiveFiles = inactiveFiles;

        return nullable(match);
    }

    private void buildHierarchy(ref TechStackMatch[] matches) const
    {
        if (matches.length == 0)
        {
            return;
        }

        size_t[string] indexByName;
        foreach (idx, ref match; matches)
        {
            enforce(match.name.length != 0, "Tech stack match missing name.");
            enforce(!(match.name in indexByName), "Duplicate tech stack name detected: " ~ match.name);
            indexByName[match.name] = idx;
        }

        string[][string] childrenByParent;
        foreach (ref match; matches)
        {
            if (match.parent.length == 0)
            {
                continue;
            }
            enforce(match.parent in indexByName, "Tech stack `" ~ match.name ~ "` references unknown parent `" ~ match.parent ~ "`.");
            childrenByParent[match.parent] ~= match.name;
        }

        foreach (ref match; matches)
        {
            auto listPtr = match.name in childrenByParent;
            if (listPtr)
            {
                auto children = (*listPtr).dup;
                sort(children);
                match.children = children;
            }
            else
            {
                match.children = [];
            }
        }

        string[][string] aggregateCache;
        bool[string] recursionStack;

        string[] computeAggregate(string name)
        {
            if (auto cached = name in aggregateCache)
            {
                return *cached;
            }

            enforce(!(name in recursionStack), "Cycle detected in tech stack hierarchy involving `" ~ name ~ "`.");
            recursionStack[name] = true;

            auto index = indexByName[name];
            auto ref match = matches[index];

            string[string] total;
            foreach (file; match.relevantFiles)
            {
                total[file] = file;
            }
            foreach (childName; match.children)
            {
                foreach (childFile; computeAggregate(childName))
                {
                    total[childFile] = childFile;
                }
            }

            auto combined = total.byValue.array;
            sort(combined);
            aggregateCache[name] = combined;
            recursionStack.remove(name);
            return aggregateCache[name];
        }

        foreach (ref match; matches)
        {
            match.aggregatedFiles = computeAggregate(match.name);
        }
    }

    private static bool allPatternsSatisfied(const string[] patterns, const string[] files)
    {
        foreach (pattern; patterns)
        {
            if (!files.any!(file => matchesPattern(file, pattern)))
            {
                return false;
            }
        }
        return true;
    }

    private static bool anyPatternSatisfied(const string[] patterns, const string[] files)
    {
        foreach (pattern; patterns)
        {
            if (files.any!(file => matchesPattern(file, pattern)))
            {
                return true;
            }
        }
        return false;
    }

    private static string[] collectMatchingFiles(const string[] patterns, const string[] files)
    {
        string[string] found;
        foreach (pattern; patterns)
        {
            foreach (file; files)
            {
                if (matchesPattern(file, pattern))
                {
                    found[file] = file;
                }
            }
        }
        auto unique = found.byValue.array;
        sort(unique);
        return unique;
    }

    private string[] evaluateKeywordHits(const string[] keywords, string absoluteRoot, const string[] relevantFiles, const string[] allFiles) const
    {
        if (keywords.empty)
        {
            return [];
        }

        string[string] hits;

        string[] searchTargets = !relevantFiles.empty ? relevantFiles.dup : allFiles.dup;
        foreach (keyword; keywords)
        {
            auto hitFile = findKeywordInFiles(keyword, absoluteRoot, searchTargets);
            if (!hitFile.empty)
            {
                hits[hitFile] = hitFile;
            }
        }

        return hits.byValue.array;
    }

    private static string findKeywordInFiles(const string keyword, const string root, const string[] files)
    {
        foreach (relPath; files)
        {
            auto absolutePath = buildPath(root, relPath);
            if (!exists(absolutePath))
            {
                continue;
            }

            if (getSize(absolutePath) > maxKeywordScanBytes)
            {
                continue;
            }

            string content;
            try
            {
                content = readText(absolutePath);
            }
            catch (Exception)
            {
                continue;
            }

            if (content.canFind(keyword))
            {
                return relPath;
            }
        }
        return "";
    }

    private static bool evaluateManifestRules(const ManifestRule[] rules, const string root, const string[] files, ref ManifestCheckResult[] evidence)
    {
        foreach (rule; rules)
        {
            if (!evaluateManifestRule(rule, root, files, evidence))
            {
                return false;
            }
        }
        return true;
    }

    private static bool evaluateManifestRule(const ManifestRule rule, const string root, const string[] files, ref ManifestCheckResult[] evidence)
    {
        auto matches = collectMatchingFiles([rule.pathPattern], files);
        if (matches.empty)
        {
            return false;
        }

        foreach (relPath; matches)
        {
            auto manifestPath = buildPath(root, relPath);
            if (!exists(manifestPath))
            {
                continue;
            }

            ManifestCheckResult check;
            check.manifestPath = relPath;
            check.format = rule.format;

            string[] allDependencies;
            bool loaded = loadDependenciesFromManifest(manifestPath, rule, allDependencies);
            if (!loaded)
            {
                continue;
            }

            auto requiredSatisfied = intersection(rule.required, allDependencies);
            auto anySatisfied = intersection(rule.anyOf, allDependencies);

            if (!rule.required.empty && requiredSatisfied.length != rule.required.length)
            {
                continue;
            }
            if (!rule.anyOf.empty && anySatisfied.empty)
            {
                continue;
            }

            check.requiredSatisfied = requiredSatisfied;
            check.anySatisfied = anySatisfied;
            evidence ~= check;
            return true;
        }
        return false;
    }

    private static bool loadDependenciesFromManifest(const string manifestPath, const ManifestRule rule, ref string[] dependencies)
    {
        string content;
        try
        {
            content = readText(manifestPath);
        }
        catch (Exception)
        {
            return false;
        }

        final switch (rule.format.toLower())
        {
            case "json":
                return loadDependenciesFromJsonManifest(content, rule, dependencies);
            case "text":
                dependencies = collectDependenciesFromText(content);
                return true;
        }
    }

    private static bool loadDependenciesFromJsonManifest(const string content, const ManifestRule rule, ref string[] dependencies)
    {
        JSONValue json;
        try
        {
            json = parseJSON(content);
        }
        catch (Exception)
        {
            return false;
        }

        if (json.type != JSONType.object)
        {
            return false;
        }

        string[] fields = !rule.dependencyFields.empty
            ? rule.dependencyFields.dup
            : ["dependencies", "devDependencies", "peerDependencies", "optionalDependencies"];

        string[string] collected;
        foreach (field; fields)
        {
            auto depValues = jsonGetObjectField(json, field);
            foreach (dependencyName, _; depValues)
            {
                collected[dependencyName] = dependencyName;
            }
        }

        dependencies = collected.byValue.array;
        sort(dependencies);
        return true;
    }

    private static string[] collectDependenciesFromText(const string content)
    {
        auto normalized = content.toLower();
        string[string] deps;

        foreach (line; normalized.splitLines())
        {
            auto stripped = line.strip();
            if (stripped.length == 0 || stripped[0] == '#')
            {
                continue;
            }

            auto commentPos = stripped.indexOf('#');
            if (commentPos != -1)
            {
                stripped = stripped[0 .. cast(size_t)commentPos].strip();
            }
            if (stripped.length == 0)
            {
                continue;
            }

            string candidate = stripped;
            auto bracketPos = candidate.indexOf('[');
            if (bracketPos != -1)
            {
                candidate = candidate[0 .. cast(size_t)bracketPos];
            }

            static immutable string[] separators = ["==", ">=", "<=", "~=", "!=", "=", ">", "<", " "];
            foreach (sep; separators)
            {
                auto pos = candidate.indexOf(sep);
                if (pos != -1)
                {
                    candidate = candidate[0 .. cast(size_t)pos];
                    break;
                }
            }

            candidate = candidate.strip();
            if (candidate.length == 0)
            {
                continue;
            }
            deps[candidate] = candidate;
        }

        if (deps.length == 0)
        {
            foreach (token; splitWhitespace(normalized))
            {
                if (token.length == 0)
                {
                    continue;
                }
                deps[token] = token;
            }
        }

        auto values = deps.byValue.array;
        sort(values);
        return values;
    }

    private string saveArchitectureModel(const ArchitectureModel model)
    {
        enforce(options.architectureFormat == "json", "Only JSON architecture format is supported currently.");

        auto cacheDir = resolveCacheDirectory(model.projectRoot);
        if (!exists(cacheDir))
        {
            mkdirRecurse(cacheDir);
        }

        auto cacheFileName = buildCacheFileName(model.projectRoot);
        auto cachePath = buildPath(cacheDir, cacheFileName);
        auto json = model.toJSON();
        auto serialized = json.toPrettyString();
        write(cachePath, serialized);
        return cachePath;
    }

    private string resolveCacheDirectory(const string projectRoot) const @safe
    {
        if (isAbsolute(options.cacheRoot))
        {
            return options.cacheRoot;
        }
        return buildPath(projectRoot, options.cacheRoot);
    }

    private static string buildCacheFileName(const string projectRoot)
    {
        auto digest = sha1Of(projectRoot);
        auto hex = toHexString(digest);
        auto projectId = baseName(projectRoot);
        if (projectId.length == 0)
        {
            projectId = "project";
        }
        return projectId ~ "-" ~ to!string(hex) ~ ".json";
    }

    private static string[] collectProjectFiles(const string projectRoot)
    {
        string[] files;
        foreach (DirEntry entry; dirEntries(projectRoot, SpanMode.depth))
        {
            if (entry.isDir)
            {
                continue;
            }

            auto relative = relativePath(entry.name, projectRoot);
            files ~= canonicalizePath(relative);
        }
        sort(files);
        return files;
    }

    private static string[] buildInactiveFiles(const string[] allFiles, const string[] activeFiles)
    {
        string[string] activeSet;
        foreach (file; activeFiles)
        {
            activeSet[file] = file;
        }

        string[] inactive;
        foreach (file; allFiles)
        {
            if (file !in activeSet)
            {
                inactive ~= file;
            }
        }
        sort(inactive);
        return inactive;
    }

    private static string canonicalizePath(string path)
    {
        char[] result = path.dup;
        foreach (ref char c; result)
        {
            if (c == '\\')
            {
                c = '/';
            }
        }
        return result.idup;
    }

    private static bool matchesPattern(const string path, const string pattern)
    {
        auto normalizedPath = toLower(canonicalizePath(path));
        auto normalizedPattern = toLower(canonicalizePath(pattern));
        return globMatch(normalizedPath, normalizedPattern);
    }

    private static string[] intersection(const string[] expected, const string[] actual)
    {
        if (expected.empty)
        {
            return [];
        }

        string[string] found;
        foreach (value; expected)
        {
            if (actual.canFind(value))
            {
                found[value] = value;
            }
        }
        auto intersected = found.byValue.array;
        sort(intersected);
        return intersected;
    }
}

// --- Helper extension methods for JSONValue access -------------------------

private JSONValue jsonGetOptional(const JSONValue value, const string key)
{
    enforce(value.type == JSONType.object, "JSON value must be an object.");
    auto obj = value.object;
    if (auto entry = key in obj)
    {
        return *entry;
    }
    return JSONValue.init;
}

private string jsonExpectString(const JSONValue value, const string key)
{
    auto maybe = jsonGetOptional(value, key);
    enforce(maybe.type != JSONType.null_, "Missing required JSON field `" ~ key ~ "`.");
    enforce(maybe.type == JSONType.string, "JSON field `" ~ key ~ "` must be a string.");
    return maybe.str;
}

private string jsonGetStringOrDefault(const JSONValue value, const string key, const string defaultValue = "")
{
    auto maybe = jsonGetOptional(value, key);
    if (maybe.type == JSONType.null_)
    {
        return defaultValue;
    }

    enforce(maybe.type == JSONType.string, "JSON field `" ~ key ~ "` must be a string.");
    return maybe.str;
}

private string[] jsonGetStringArray(const JSONValue value, const string key)
{
    auto maybe = jsonGetOptional(value, key);
    if (maybe.type == JSONType.null_)
    {
        return [];
    }
    enforce(maybe.type == JSONType.array, "JSON field `" ~ key ~ "` must be an array.");

    string[] result;
    foreach (element; maybe.array)
    {
        enforce(element.type == JSONType.string, "JSON array `" ~ key ~ "` must contain only strings.");
        result ~= element.str;
    }
    return result;
}

private JSONValue[] jsonGetArray(const JSONValue value, const string key)
{
    auto maybe = jsonGetOptional(value, key);
    if (maybe.type == JSONType.null_)
    {
        return [];
    }
    enforce(maybe.type == JSONType.array, "JSON field `" ~ key ~ "` must be an array.");
    return maybe.array;
}

private JSONValue[string] jsonGetObjectField(const JSONValue value, const string field)
{
    JSONValue[string] empty;
    if (value.type != JSONType.object)
    {
        return empty;
    }
    auto obj = value.object;
    if (auto entry = field in obj)
    {
        auto refValue = *entry;
        if (refValue.type == JSONType.object)
        {
            return cast(JSONValue[string])refValue.object;
        }
    }
    return empty;
}

private JSONValue stringArrayToJSON(const string[] values)
{
    JSONValue[] result;
    foreach (value; values)
    {
        result ~= JSONValue(value);
    }
    return JSONValue(result);
}

private string[] splitWhitespace(const string content)
{
    string[] tokens;
    string current;
    foreach (dchar c; content)
    {
        if (c == ' ' || c == '\n' || c == '\r' || c == '\t' || c == '\f')
        {
            if (!current.empty)
            {
                tokens ~= current;
                current = "";
            }
        }
        else
        {
            current ~= c;
        }
    }
    if (!current.empty)
    {
        tokens ~= current;
    }
    return tokens;
}
