[CmdletBinding()]
param(
    [ValidateSet("Check", "Sync")]
    [string] $Mode = "Check",

    [string] $SourceRepository
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$provenancePath = Join-Path $repoRoot "docs/modules/specifications/images/playtime-diagrams.provenance.sdl"

function Read-ProvenanceValue {
    param(
        [string[]] $Lines,
        [string] $Name
    )

    $pattern = '^\s*' + [regex]::Escape($Name) + '\s+"([^"]+)"\s*$'
    $matches = @($Lines | Select-String -Pattern $pattern)
    if ($matches.Count -ne 1) {
        throw "Expected exactly one '$Name' value in $provenancePath."
    }

    return $matches[0].Matches[0].Groups[1].Value
}

if (-not (Test-Path -LiteralPath $provenancePath -PathType Leaf)) {
    throw "Missing provenance file: $provenancePath"
}

$provenanceLines = Get-Content -LiteralPath $provenancePath
$canonicalRepository = Read-ProvenanceValue $provenanceLines "repository"
$canonicalCommit = Read-ProvenanceValue $provenanceLines "commit"
$sourceRoot = Read-ProvenanceValue $provenanceLines "sourceRoot"
$destinationRoot = Read-ProvenanceValue $provenanceLines "destinationRoot"

$artifacts = @(
    foreach ($line in $provenanceLines) {
        if ($line -match '^\s*artifact\s+"([^"]+)"(?:\s+source\s+"([^"]+)")?\s+gitBlob\s+"([0-9a-f]{40})"\s*$') {
            [pscustomobject]@{
                File = $Matches[1]
                Source = $Matches[2]
                GitBlob = $Matches[3]
            }
        }
    }
)

if ($artifacts.Count -ne 36) {
    throw "Expected 36 adaptive, host, and fixed artifacts; found $($artifacts.Count)."
}

if (-not $SourceRepository) {
    if ($env:SCRIPTBOOK_REPO) {
        $SourceRepository = $env:SCRIPTBOOK_REPO
    }
    elseif ($env:code) {
        $SourceRepository = Join-Path $env:code "github.com/dev-centr/scriptbook"
    }
    else {
        $SourceRepository = Join-Path (Split-Path $repoRoot -Parent) "scriptbook"
    }
}

if ($Mode -eq "Sync" -and -not (Test-Path -LiteralPath (Join-Path $SourceRepository ".git"))) {
    throw "Canonical repository is unavailable at '$SourceRepository'. Clone $canonicalRepository or pass -SourceRepository."
}

$hasSource = Test-Path -LiteralPath (Join-Path $SourceRepository ".git")
if ($hasSource) {
    & git -C $SourceRepository cat-file -e "$canonicalCommit^{commit}"
    if ($LASTEXITCODE -ne 0) {
        throw "Canonical commit $canonicalCommit is unavailable in '$SourceRepository'."
    }
}

$destinationDirectory = Join-Path $repoRoot $destinationRoot
if (-not (Test-Path -LiteralPath $destinationDirectory -PathType Container)) {
    throw "Destination directory does not exist: $destinationDirectory"
}

$temporaryDirectory = Join-Path ([System.IO.Path]::GetTempPath()) "devcentr-playtime-$PID-$([guid]::NewGuid().ToString('N'))"
$archivePath = Join-Path $temporaryDirectory "canonical.zip"
$extractPath = Join-Path $temporaryDirectory "canonical"

try {
    New-Item -ItemType Directory -Path $temporaryDirectory, $extractPath | Out-Null
    if ($hasSource) {
        $sourcePaths = @($artifacts | Where-Object Source | ForEach-Object { "$sourceRoot/$($_.Source)" })
        & git -C $SourceRepository archive --format=zip "--output=$archivePath" $canonicalCommit -- $sourcePaths
        if ($LASTEXITCODE -ne 0) {
            throw "Could not archive canonical artifacts from $canonicalCommit."
        }
        Expand-Archive -LiteralPath $archivePath -DestinationPath $extractPath
    }

    foreach ($artifact in $artifacts) {
        $destinationFile = Join-Path $destinationDirectory $artifact.File
        if ($artifact.Source -and $hasSource) {
            $sourcePath = "$sourceRoot/$($artifact.Source)"
            $sourceBlob = (& git -C $SourceRepository rev-parse "$canonicalCommit`:$sourcePath").Trim()
            if ($LASTEXITCODE -ne 0 -or $sourceBlob -ne $artifact.GitBlob) {
                throw "Provenance mismatch for $sourcePath (expected $($artifact.GitBlob), got $sourceBlob)."
            }
            if ($Mode -eq "Sync") {
                $archivedFile = Join-Path $extractPath ($sourcePath -replace "/", [System.IO.Path]::DirectorySeparatorChar)
                Copy-Item -LiteralPath $archivedFile -Destination $destinationFile -Force
            }
        }

        if (-not (Test-Path -LiteralPath $destinationFile -PathType Leaf)) {
            throw "Missing synchronized artifact: $destinationFile"
        }

        $destinationBlob = (& git hash-object $destinationFile).Trim()
        if ($LASTEXITCODE -ne 0 -or $destinationBlob -ne $artifact.GitBlob) {
            throw "Stale artifact $($artifact.File) (expected $($artifact.GitBlob), got $destinationBlob)."
        }
    }

    $baseNames = @($artifacts.File | ForEach-Object { $_ -replace '(\.host|\.fixed)?\.svg$', '' } | Sort-Object -Unique)
    foreach ($baseName in $baseNames) {
        foreach ($duplicateSuffix in @(".mmd", ".theme.json")) {
            $duplicate = Join-Path $destinationDirectory "$baseName$duplicateSuffix"
            if (Test-Path -LiteralPath $duplicate) {
                throw "Canonical source/manifest must not be duplicated here: $duplicate"
            }
        }
    }

    Write-Output "$Mode passed: 36 PlayTime artifacts match pinned provenance for $canonicalRepository@$canonicalCommit."
}
finally {
    if (Test-Path -LiteralPath $temporaryDirectory) {
        Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force
    }
}
