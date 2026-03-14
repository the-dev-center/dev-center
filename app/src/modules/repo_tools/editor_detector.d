module modules.repo_tools.editor_detector;

import std.process;
import std.file;
import std.path;
import std.string;

struct EditorProfile {
    string name;
    string executableName;
    string processArg; // The argument format to open a folder/workspace
}

// Built-in known VSCode forks
static const EditorProfile[] KNOWN_VSCODE_FORKS = [
    EditorProfile("VS Code", "code", ""),
    EditorProfile("VS Code Insiders", "code-insiders", ""),
    EditorProfile("VSCodium", "codium", ""),
    EditorProfile("Cursor", "cursor", ""),
    EditorProfile("Windsurf", "windsurf", ""),
    EditorProfile("Trae", "trae", ""),
    EditorProfile("PearAI", "pearai", ""),
    EditorProfile("Google Antigravity", "antigravity", "")
];

/// Returns a list of installed editor profiles that are detected on the system PATH
EditorProfile[] detectInstalledEditors()
{
    EditorProfile[] installed;
    
    version(Windows) {
        string cmd = "where";
    } else {
        string cmd = "which";
    }
    
    foreach(profile; KNOWN_VSCODE_FORKS)
    {
        try {
            auto result = execute([cmd, profile.executableName]);
            if (result.status == 0 && result.output.length > 0)
            {
                installed ~= profile;
            }
        } catch (Exception) {
            // Executable checking failed
        }
    }
    return installed;
}

/// Helper method to open a specific path with the requested editor
void openPathWithEditor(EditorProfile editor, string targetPath)
{
    try {
        spawnProcess([editor.executableName, targetPath]);
    } catch (Exception e) {
        import std.stdio;
        writeln("Failed to cleanly spawn external editor: ", e.msg);
    }
}
