module modules.template_installer.project_manager;

import modules.project_recognizer.recognizer;
import modules.template_installer.installer;
import std.file : exists, mkdirRecurse, write, readText, copy, dirEntries, SpanMode;
import std.path : dirName, buildPath, absolutePath, baseName, relativePath;
import std.json : JSONValue, parseJSON, JSONType;
import std.exception : enforce;
import std.array : array;
import std.algorithm : endsWith;

/// Manages a specific project's templates and workspace state.
class ProjectWorkspaceManager
{
    private string projectRoot;
    private ProjectRecognizer recognizer;

    this(string projectRoot, ProjectRecognizer recognizer)
    {
        this.projectRoot = absolutePath(projectRoot);
        this.recognizer = recognizer;
    }

    /// Identifies tech stacks in the project.
    ArchitectureModel identifyStacks()
    {
        return recognizer.recognize(projectRoot);
    }

    /// Gets a list of templates already installed in the project.
    string[] getInstalledTemplates()
    {
        auto path = buildPath(projectRoot, ".dev-center", "installed-templates.json");
        if (!exists(path)) return [];

        try
        {
            auto json = parseJSON(readText(path));
            string[] results;
            foreach (v; json["templates"].array)
            {
                results ~= v.str;
            }
            return results;
        }
        catch (Exception)
        {
            return [];
        }
    }

    /// Saves the current project's workspace configurations to a new local template.
    void saveAsTemplate(string templateName, string localTemplatesRoot, bool derivative = true)
    {
        auto destPath = buildPath(localTemplatesRoot, templateName);
        if (!exists(destPath)) mkdirRecurse(destPath);

        // Copy .code-workspace files
        foreach (entry; dirEntries(projectRoot, SpanMode.shallow))
        {
            if (entry.name.endsWith(".code-workspace"))
            {
                copy(entry.name, buildPath(destPath, baseName(entry.name)));
            }
        }

        // Copy .vscode folder if it exists
        auto vscodeDir = buildPath(projectRoot, ".vscode");
        if (exists(vscodeDir))
        {
            auto destVsCode = buildPath(destPath, ".vscode");
            if (!exists(destVsCode)) mkdirRecurse(destVsCode);
            foreach (entry; dirEntries(vscodeDir, SpanMode.depth))
            {
                if (!entry.isDir)
                {
                    auto relPath = relativePath(entry.name, vscodeDir);
                    auto target = buildPath(destVsCode, relPath);
                    auto targetDir = dirName(target);
                    if (!exists(targetDir)) mkdirRecurse(targetDir);
                    copy(entry.name, target);
                }
            }
        }

        // Create a metadata file for the template
        JSONValue meta;
        meta["name"] = JSONValue(templateName);
        meta["derivative"] = JSONValue(derivative);
        if (derivative)
        {
            meta["parents"] = stringArrayToJSON(getInstalledTemplates());
        }
        write(buildPath(destPath, "template.json"), meta.toString());
    }

    private JSONValue stringArrayToJSON(string[] arr)
    {
        JSONValue[] vals;
        foreach (s; arr) vals ~= JSONValue(s);
        return JSONValue(vals);
    }
}
