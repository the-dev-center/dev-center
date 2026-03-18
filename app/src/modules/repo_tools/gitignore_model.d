/// Parses .gitignore content and recognizes technologies from patterns and comments.
module modules.repo_tools.gitignore_model;

import std.string : strip, splitLines, startsWith, indexOf;
import std.algorithm : canFind, filter, map;
import std.array : array;

/// A technology inferred from gitignore patterns.
struct RecognizedTech
{
    string name;      /// e.g. "Node", "Python", "Build"
    int[] lineIndices; /// 0-based line numbers that relate to this tech
}

/// Pattern-to-technology mapping. Order matters (first match wins for a line).
struct PatternRule { string name; string[] patterns; }
static immutable PatternRule[] PATTERN_RULES = [
    PatternRule("Node", ["node_modules", "npm-debug", "yarn-error", "pnpm-debug", ".pnpm-store", "nvm"]),
    PatternRule("Python", ["__pycache__", "*.pyc", "*.pyo", ".Python", "venv", ".venv", "env", ".eggs", "*.egg"]),
    PatternRule("D", ["*.o", "*.obj", ".dub", "dub.selections", "dub.json"]),
    PatternRule("Rust", ["target/", "Cargo.lock", "*.rs.bk"]),
    PatternRule("Go", ["*.exe", "*.exe~", "*.dll", "*.so", "*.dylib", "/vendor/"]),
    PatternRule("Build", ["build/", "dist/", "out/", "bin/", "obj/", ".build"]),
    PatternRule("Logs", ["*.log", "logs/", ".logs"]),
    PatternRule("Env", [".env", ".env.local", ".env.*.local"]),
    PatternRule("IDE", [".idea", ".vscode", "*.swp", "*.swo", "*~"]),
    PatternRule("OS", [".DS_Store", "Thumbs.db", "desktop.ini"]),
];

/// Parse gitignore content and return recognized technologies with their line mappings.
RecognizedTech[] parseTechnologies(string content)
{
    RecognizedTech[] result;
    auto lines = content.splitLines();
    int[] techLineCount;
    techLineCount.length = PATTERN_RULES.length;

    foreach (i, line; lines)
    {
        string ln = line.strip();
        if (ln.length == 0) continue;
        if (ln.startsWith("#")) continue;

        foreach (j, rule; PATTERN_RULES)
        {
            string techName = rule.name;
            string[] patterns = rule.patterns.dup;
            bool matched = false;
            foreach (pat; patterns)
            {
                if (canFind(ln, pat) || ln == pat)
                {
                    matched = true;
                    break;
                }
            }
            if (matched)
            {
                size_t idx = size_t.max;
                foreach (k, rt; result)
                {
                    if (rt.name == techName) { idx = k; break; }
                }
                if (idx == size_t.max)
                {
                    result ~= RecognizedTech(techName, [cast(int)i]);
                }
                else
                {
                    result[idx].lineIndices ~= cast(int)i;
                }
                break;
            }
        }
    }
    return result;
}
