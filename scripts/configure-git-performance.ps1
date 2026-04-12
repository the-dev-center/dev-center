# Git Performance Configuration Script
# Enables core.fsmonitor globally and unsets legacy keys.

$warnings = @"
Git Performance Optimization (FSMonitor) - Technical Considerations:

1. Resource Overhead:
   - Spawns a background daemon for EACH repository.
   - High process count if navigating many projects.
   - Increased processing cycles for submodules.

2. Filesystem Limitations:
   - Unreliable over Network/Shared drives (SMB/NFS).
   - Potential Socket Path Errors on macOS (non-native filesystems).

3. Security Considerations:
   - Malicious repos could exploit settings (though global is safer).
   - Orphaned processes may remain in Task Manager on Windows.

4. Deprecation Note:
   - This script uses 'core.fsmonitor', NOT the legacy 'core.useBuiltinFSMonitor'.
"@

Write-Host "----------------------------------------------------" -ForegroundColor Cyan
Write-Host "Configuring Git Global Performance (Built-in FSMonitor)" -ForegroundColor White
Write-Host "----------------------------------------------------" -ForegroundColor Cyan
Write-Host $warnings
Write-Host "----------------------------------------------------" -ForegroundColor Cyan

# Check Git Version
$gitVersion = git --version
if ($gitVersion -match "git version (\d+\.\d+\.\d+)") {
    $version = [version]$matches[1]
    if ($version -lt [version]"2.37.0") {
        Write-Error "Git version $version detected. core.fsmonitor requires at least 2.37.0."
        exit 1
    }
}

# Enable modern fsmonitor globally
Write-Host "Setting core.fsmonitor=true globally..." -ForegroundColor Green
git config --global core.fsmonitor true

# Unset legacy key if it exists
Write-Host "Ensuring legacy core.useBuiltinFSMonitor is unset..." -ForegroundColor Gray
git config --global --unset-all core.useBuiltinFSMonitor 2>$null

Write-Host "SUCCESS: Git performance optimization applied." -ForegroundColor Green
Write-Host "You may need to restart your IDE or terminal for full effect." -ForegroundColor Yellow
