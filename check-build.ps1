<#
.SYNOPSIS
    Checks the status of a CodeMagic build via the REST API.

.PARAMETER BuildId
    The build ID returned by trigger-build.ps1 (or from the CodeMagic URL).

.PARAMETER ApiKey
    Your CodeMagic API token. Loaded from app.info if not supplied.

.PARAMETER Wait
    If specified, polls every 30 seconds until the build reaches a terminal state.

.EXAMPLE
    .\check-build.ps1 -BuildId "69f6b16b1b22154a1810dd4a"

.EXAMPLE
    .\check-build.ps1 -BuildId "69f6b16b1b22154a1810dd4a" -Wait
#>

param(
    [Parameter(Mandatory)][string] $BuildId,
    [string] $ApiKey,
    [switch] $Wait
)

# Load ApiKey from app.info if not supplied on the command line.
if (-not $ApiKey) {
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

$terminalStates = @('finished', 'failed', 'canceled', 'timeout', 'skipped')

function Get-BuildStatus {
    param([string] $Id, [string] $Key)

    $response = Invoke-RestMethod `
        -Uri "https://api.codemagic.io/builds/$Id" `
        -Method Get `
        -Headers @{ "x-auth-token" = $Key }

    $build    = $response.build
    $status   = $build.status
    $workflow = $build.workflowName
    $branch   = $build.branch
    $started  = if ($build.startedAt)  { [datetime]$build.startedAt  } else { $null }
    $finished = if ($build.finishedAt) { [datetime]$build.finishedAt } else { $null }

    $elapsed = if ($started) {
        $end = if ($finished) { $finished } else { Get-Date }
        $span = $end - $started
        "{0:mm}m {0:ss}s" -f $span
    } else { "-" }

    [PSCustomObject]@{
        Status   = $status
        Workflow = $workflow
        Branch   = $branch
        Started  = if ($started)  { $started.ToString("HH:mm:ss")  } else { "-" }
        Finished = if ($finished) { $finished.ToString("HH:mm:ss") } else { "-" }
        Elapsed  = $elapsed
        Build    = $build
    }
}

function Write-StatusLine {
    param($Info)

    $color = switch ($Info.Status) {
        'finished' { 'Green'  }
        'failed'   { 'Red'    }
        'canceled' { 'Yellow' }
        'timeout'  { 'Yellow' }
        default    { 'Cyan'   }
    }

    Write-Host ""
    Write-Host "  Build ID:  $BuildId"
    Write-Host "  Workflow:  $($Info.Workflow)"
    Write-Host "  Branch:    $($Info.Branch)"
    Write-Host "  Status:    " -NoNewline
    Write-Host $Info.Status -ForegroundColor $color
    Write-Host "  Started:   $($Info.Started)"
    Write-Host "  Finished:  $($Info.Finished)"
    Write-Host "  Elapsed:   $($Info.Elapsed)"
}

try {
    if ($Wait) {
        Write-Host "Polling build $BuildId (Ctrl+C to stop)..."
        while ($true) {
            $info = Get-BuildStatus -Id $BuildId -Key $ApiKey
            $timestamp = (Get-Date).ToString("HH:mm:ss")
            $statusColor = if ($info.Status -in $terminalStates) {
                if ($info.Status -eq 'finished') { 'Green' } else { 'Red' }
            } else { 'Cyan' }
            Write-Host "[$timestamp]  " -NoNewline
            Write-Host $info.Status -ForegroundColor $statusColor

            if ($info.Status -in $terminalStates) {
                Write-StatusLine $info
                Write-Host ""
                Write-Host "  Track at: https://codemagic.io/app/$($info.Build.appId)/build/$BuildId"
                break
            }
            Start-Sleep -Seconds 30
        }
    } else {
        $info = Get-BuildStatus -Id $BuildId -Key $ApiKey
        Write-StatusLine $info
        Write-Host ""
        Write-Host "  Track at: https://codemagic.io/app/$($info.Build.appId)/build/$BuildId"
    }
}
catch {
    $status = $_.Exception.Response.StatusCode.value__
    Write-Host "Failed to fetch build status (HTTP $status)" -ForegroundColor Red
    exit 1
}
