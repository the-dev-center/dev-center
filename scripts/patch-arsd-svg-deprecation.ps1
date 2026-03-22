# Patch arsd-official svg.d to fix extern(C) + in parameter deprecation
# Run after `dub fetch` or `dub upgrade` when using arsd-official 10.9.x
# The fix: change `in void *` to `scope const void *` in nsvg__cmpEdge
# Upstream fixed this in 11.0.1; we patch 10.9.x for dlangui compatibility

$dubPackages = Join-Path $env:LOCALAPPDATA "dub\packages"
$arsdDir = Join-Path $dubPackages "arsd-official"
if (-not (Test-Path $arsdDir)) {
    Write-Host "arsd-official not found in dub packages; run dub build first" -ForegroundColor Yellow
    exit 0
}

$dirs = Get-ChildItem $arsdDir -Directory
foreach ($dir in $dirs) {
    $svgPath = Join-Path $dir.FullName "arsd-official\svg.d"
    if (-not (Test-Path $svgPath)) { continue }
    $content = Get-Content $svgPath -Raw
    if ($content -match 'in void \*p, in void \*q') {
        $content = $content -replace 'in void \*p, in void \*q', 'scope const void *p, scope const void *q'
        Set-Content $svgPath -Value $content -NoNewline
        Write-Host "Patched $svgPath" -ForegroundColor Green
    }
}
