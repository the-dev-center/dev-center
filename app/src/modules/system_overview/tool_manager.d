module modules.system_overview.tool_manager;

import std.array;
import std.algorithm;
import std.process : environment;
import std.path;
import std.file;
import std.json;

struct ToolStatus {
    string name;
    string icon;
    string[] techStacks;
    bool isInstalled;
    string installLocation;
    bool onPath;
    string[] pathVariables;
}

struct ToolStackGroup {
    string name;
    ToolStatus[] tools;
}

class ToolManager {
    ToolStatus[] allTools;

    this() {
        refresh();
    }

    void refresh() {
        allTools = [];
        // Mock data as requested
        allTools ~= ToolStatus("DMD Compiler", "dlang_logo", ["D"], true, "C:\\D\\dmd2\\windows\\bin", true, ["USER", "PATH"]);
        allTools ~= ToolStatus("LDC Compiler", "dlang_logo", ["D"], false, "", false, []);
        allTools ~= ToolStatus("Node.js", "nodejs_logo", ["JavaScript", "TypeScript"], true, "C:\\Program Files\\nodejs", true, ["System PATH"]);
        allTools ~= ToolStatus("pnpm", "pnpm_logo", ["JavaScript", "Node.js"], true, "C:\\Users\\User\\AppData\\Local\\pnpm", true, ["User PATH"]);
        allTools ~= ToolStatus("Python 3.12", "python_logo", ["Python"], true, "C:\\Python312", true, ["System PATH", "User PATH"]);
        allTools ~= ToolStatus("Rust Toolchain", "rust_logo", ["Rust"], false, "", false, []);
        allTools ~= ToolStatus("dub", "dlang_logo", ["D"], true, "C:\\D\\dmd2\\windows\\bin", true, ["User PATH"]);
        allTools ~= ToolStatus("Go Compiler", "go_logo", ["Go"], false, "", false, []);
        allTools ~= ToolStatus("Java SDK 21", "java_logo", ["Java", "JVM"], true, "C:\\Program Files\\Java\\jdk-21", false, []);

        // Virtualization & Testing
        allTools ~= ToolStatus("virt-manager", "settings", ["Virtualization", "Windows Testing"], true, "/usr/bin/virt-manager", true, ["System PATH"]);
        allTools ~= ToolStatus("virsh (libvirt)", "terminal", ["Virtualization", "Automation"], true, "/usr/bin/virsh", true, ["System PATH"]);
        allTools ~= ToolStatus("QEMU/KVM", "cpu", ["Virtualization"], true, "/usr/bin/qemu-system-x86_64", true, ["System PATH"]);
    }

    ToolStackGroup[] getGroupedTools(bool installedOnly) {
        ToolStackGroup[] groups;

        // Collect all unique stacks
        string[] stacks;
        foreach(tool; allTools) {
            if (tool.isInstalled != installedOnly) continue;
            foreach(s; tool.techStacks) {
                if (!stacks.canFind(s)) stacks ~= s;
            }
        }
        sort(stacks);

        foreach(stack; stacks) {
            ToolStatus[] toolsInStack;
            foreach(tool; allTools) {
                if (tool.isInstalled != installedOnly) continue;
                if (tool.techStacks.canFind(stack)) {
                    toolsInStack ~= tool;
                }
            }
            if (!toolsInStack.empty) {
                groups ~= ToolStackGroup(stack, toolsInStack);
            }
        }
        return groups;
    }
}
