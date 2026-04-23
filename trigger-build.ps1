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
#>

param(
    [string] $ApiKey,
    [string] $AppId,
    [Parameter(Mandatory)][string] $Branch,
    [ValidateSet("ios-workflow", "android-workflow", "dev-workflow")]
    [string] $Workflow = "ios-workflow"
)

# Load ApiKey / AppId from app.info if not supplied on the command line.
# Parsed manually because PowerShell 5.1 won't dot-source non-.ps1 files.
if (-not $ApiKey -or -not $AppId) {
    $infoFile = Join-Path $PSScriptRoot "app.info"
    if (Test-Path $infoFile) {
        Get-Content $infoFile | ForEach-Object {
            if ($_ -match '^\$(\w+)=(.+)$') {
                Set-Variable -Name $Matches[1] -Value $Matches[2]
            }
        }
    }
}

if (-not $ApiKey) { Write-Error "ApiKey is required (pass -ApiKey or set it in app.info)"; exit 1 }
if (-not $AppId)  { Write-Error "AppId is required (pass -AppId or set it in app.info)";  exit 1 }

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
