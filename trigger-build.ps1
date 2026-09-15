<#
.SYNOPSIS
    Triggers a CodeMagic build for NewsReader via the REST API.

.PARAMETER ApiKey
    Your CodeMagic API token (User Settings > Integrations > Codemagic API).

.PARAMETER AppId
    Your CodeMagic app ID (visible in the URL: app.codemagic.io/apps/<AppId>).

.PARAMETER Branch
    The branch to build (e.g. main, develop).

.PARAMETER Workflow
    The workflow to run. Must be one of:
      ios-workflow       - iOS build & Firebase distribution
      android-workflow   - Android build & Firebase distribution
      dev-workflow       - iOS + Android build & Firebase distribution (default)

.EXAMPLE
    .\trigger-build.ps1 -ApiKey "abc123" -AppId "def456" -Branch "main"

.EXAMPLE
    .\trigger-build.ps1 -ApiKey "abc123" -AppId "def456" -Branch "main" -Workflow ios-workflow

.PARAMETER SkipChangelogCheck
    Skip the check that pubspec.yaml's version matches CHANGELOG.md's latest
    entry (and that the entry has notes). Use when re-triggering a build for
    a version already released.

.PARAMETER SkipGitCheck
    Skip the check that the working tree is clean and local HEAD matches
    origin/<Branch>. CodeMagic builds whatever commit is on the remote
    branch, not your local working tree, so an unpushed commit builds
    silently stale code unless this check catches it first.
#>

param(
    [string] $ApiKey,
    [string] $AppId,
    [Parameter(Mandatory)][string] $Branch,
    [ValidateSet("ios-workflow", "android-workflow", "dev-workflow")]
    [string] $Workflow = "ios-workflow",
    [switch] $SkipChangelogCheck,
    [switch] $SkipGitCheck
)

# Load ApiKey / AppId from app.info if not supplied on the command line.
# Parsed manually because PowerShell 5.1 won't dot-source non-.ps1 files.
if (-not $ApiKey -or -not $AppId) {
    $infoFile = Join-Path $PSScriptRoot "app.info"
    if (Test-Path $infoFile) {
        foreach ($line in (Get-Content $infoFile)) {
            if ($line -match '^\$(\w+)=(.+)$') {
                Set-Variable -Name $Matches[1] -Value $Matches[2]
            }
        }
    }
}

if (-not $ApiKey) { Write-Error "ApiKey is required (pass -ApiKey or set it in app.info)"; exit 1 }
if (-not $AppId)  { Write-Error "AppId is required (pass -AppId or set it in app.info)";  exit 1 }

# Checks that the working tree is committed and that local HEAD is exactly
# what origin/<TargetBranch> has - CodeMagic clones the remote branch, so
# anything only sitting in the local working tree or in unpushed commits is
# invisible to the build no matter how recently it changed.
function Test-GitPushed {
    param([string] $TargetBranch)

    git -C $PSScriptRoot rev-parse --is-inside-work-tree *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Not inside a git repository; skipping git push check." -ForegroundColor Yellow
        return $true
    }

    $dirty = git -C $PSScriptRoot status --porcelain
    if ($dirty) {
        Write-Host "Working tree has uncommitted changes:" -ForegroundColor Red
        Write-Host $dirty
        return $false
    }

    Write-Host "Fetching origin/$TargetBranch to verify it's pushed..."
    git -C $PSScriptRoot fetch origin $TargetBranch --quiet
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Could not fetch origin/$TargetBranch - check the branch name and remote." -ForegroundColor Red
        return $false
    }

    $localHead = git -C $PSScriptRoot rev-parse HEAD
    $remoteHead = git -C $PSScriptRoot rev-parse "origin/$TargetBranch"

    if ($localHead -ne $remoteHead) {
        Write-Host "Local HEAD ($localHead) doesn't match origin/$TargetBranch ($remoteHead)." -ForegroundColor Red
        Write-Host "Commit and push before triggering a build, or CodeMagic will build stale code." -ForegroundColor Red
        return $false
    }

    Write-Host "Git check OK: HEAD is committed and matches origin/$TargetBranch ($localHead)."
    return $true
}

# Checks that pubspec.yaml's version and CHANGELOG.md's latest entry agree,
# and that the entry has actual notes under it - mirrors the extraction
# codemagic.yaml's "Create release notes" step uses, so this fails exactly
# when that step would silently produce stale or empty release notes.
function Test-ReleaseNotes {
    $pubspecFile = Join-Path $PSScriptRoot "pubspec.yaml"
    $changelogFile = Join-Path $PSScriptRoot "CHANGELOG.md"

    if (-not (Test-Path $pubspecFile)) {
        Write-Host "pubspec.yaml not found; skipping release notes check." -ForegroundColor Yellow
        return $true
    }
    if (-not (Test-Path $changelogFile)) {
        Write-Host "CHANGELOG.md not found - add release notes before triggering a build." -ForegroundColor Red
        return $false
    }

    $pubspecVersionLine = Get-Content $pubspecFile | Where-Object { $_ -match '^version:' } | Select-Object -First 1
    if (-not ($pubspecVersionLine -match '^version:\s*(\d+\.\d+\.\d+)')) {
        Write-Host "Could not parse a version from pubspec.yaml." -ForegroundColor Red
        return $false
    }
    $pubspecVersion = $Matches[1]

    $changelogVersionLine = Get-Content $changelogFile | Where-Object { $_ -match '^## ' } | Select-Object -First 1
    if (-not $changelogVersionLine) {
        Write-Host "CHANGELOG.md has no '## <version>' entry." -ForegroundColor Red
        return $false
    }
    $changelogVersion = ($changelogVersionLine -replace '^## *', '').Trim()

    if ($changelogVersion -ne $pubspecVersion) {
        Write-Host "Version mismatch: pubspec.yaml is $pubspecVersion but CHANGELOG.md's latest entry is $changelogVersion." -ForegroundColor Red
        Write-Host "Bump pubspec.yaml's version or add a CHANGELOG.md entry so they match." -ForegroundColor Red
        return $false
    }

    # Same extraction codemagic.yaml uses for release_notes.txt: everything
    # from line 3 up to (not including) the first "---" separator.
    $lines = Get-Content $changelogFile
    $sepMatch = $lines | Select-String -Pattern '^---$' | Select-Object -First 1
    $notes = ""
    if ($lines.Count -gt 2) {
        $upperIndex = if ($sepMatch) { $sepMatch.LineNumber - 2 } else { $lines.Count - 1 }
        if ($upperIndex -ge 2) {
            $notes = ($lines[2..$upperIndex] -join "`n").Trim()
        }
    }
    if (-not $notes) {
        Write-Host "CHANGELOG.md's latest entry ($changelogVersion) has no notes under it." -ForegroundColor Red
        return $false
    }

    Write-Host "Release notes OK: CHANGELOG.md's latest entry ($changelogVersion) matches pubspec.yaml."
    return $true
}

if (-not $SkipGitCheck) {
    if (-not (Test-GitPushed -TargetBranch $Branch)) {
        Write-Host ""
        Write-Error "Aborting build trigger. Commit and push to origin/$Branch, or pass -SkipGitCheck to bypass."
        exit 1
    }
} else {
    Write-Host "Skipping git push check (-SkipGitCheck)."
}

if (-not $SkipChangelogCheck) {
    if (-not (Test-ReleaseNotes)) {
        Write-Host ""
        Write-Error "Aborting build trigger. Fix CHANGELOG.md/pubspec.yaml, or pass -SkipChangelogCheck to bypass."
        exit 1
    }
} else {
    Write-Host "Skipping release notes check (-SkipChangelogCheck)."
}

$body = @{
    appId      = $AppId
    workflowId = $Workflow
    branch     = $Branch
} | ConvertTo-Json

Write-Host "Triggering CodeMagic build..."
Write-Host "  App:      $AppId"
Write-Host "  Workflow: $Workflow"
Write-Host "  Branch:   $Branch"
Write-Host ""

try {
    $response = Invoke-RestMethod `
        -Uri "https://api.codemagic.io/builds" `
        -Method Post `
        -Headers @{ "x-auth-token" = $ApiKey; "Content-Type" = "application/json" } `
        -Body $body

    $buildId = $response.buildId
    Write-Host "Build triggered successfully!" -ForegroundColor Green
    Write-Host "  Build ID: $buildId"
    Write-Host "  Track at: https://codemagic.io/app/$AppId/build/$buildId"
}
catch {
    $status = $_.Exception.Response.StatusCode.value__
    $detail = $_.ErrorDetails.Message | ConvertFrom-Json -ErrorAction SilentlyContinue
    Write-Host "Failed to trigger build (HTTP $status)" -ForegroundColor Red
    if ($detail.message) { Write-Host "  $($detail.message)" -ForegroundColor Red }
    exit 1
}
