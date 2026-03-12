module modules.repo_tools.platform;

import std.process : environment;

version (Windows)
{
    import core.sys.windows.windows;
    
    extern(Windows) {
        BOOL SetForegroundWindow(HWND);
        BOOL ShowWindow(HWND, int);
        HWND GetWindow(HWND, UINT);
        DWORD GetWindowThreadProcessId(HWND, LPDWORD);
        BOOL IsWindowVisible(HWND);
    }

    private struct EnumData {
        DWORD targetPid;
        HWND foundHwnd;
    }

    private extern(Windows) BOOL enumWindowProc(HWND hwnd, LPARAM lParam) {
        EnumData* data = cast(EnumData*)lParam;
        DWORD pid;
        GetWindowThreadProcessId(hwnd, &pid);
        if (pid == data.targetPid && IsWindowVisible(hwnd)) {
            data.foundHwnd = hwnd;
            return FALSE; // Stop enumerating
        }
        return TRUE;
    }

    /// Bring a process's main window to the front on Windows.
    void bringProcessToFront(int pid) {
        EnumData data;
        data.targetPid = cast(DWORD)pid;
        data.foundHwnd = null;
        
        EnumWindows(&enumWindowProc, cast(LPARAM)&data);
        
        if (data.foundHwnd) {
            ShowWindow(data.foundHwnd, 9); // SW_RESTORE
            SetForegroundWindow(data.foundHwnd);
        }
    }
}
else
{
    /// No-op or implementation for Linux/macOS (e.g. wmctrl -ia <pid>)
    void bringProcessToFront(int pid) {
        // Placeholder for Linux/macOS
    }
}
