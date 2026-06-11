param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ClaudeArgs
)

$ErrorActionPreference = 'Stop'

$repoRoot = 'C:\Dev\Transform_clean'
$repoMemoryFile = Join-Path $repoRoot 'CLAUDE.md'
$repoSkillsRoot = Join-Path $repoRoot '.claude\skills'

function Resolve-ClaudeCommand {
    $candidatePaths = @(
        (Join-Path $env:APPDATA 'npm\claude.cmd'),
        (Join-Path $env:APPDATA 'npm\claude')
    )

    foreach ($candidatePath in $candidatePaths) {
        if (Test-Path -LiteralPath $candidatePath) {
            return $candidatePath
        }
    }

    $command = Get-Command claude -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    return $null
}

try {
    if (-not (Test-Path -LiteralPath $repoRoot)) {
        throw "The Transform source-of-truth repo was not found at $repoRoot."
    }

    Set-Location -LiteralPath $repoRoot

    if ($host.Name -ne 'ServerRemoteHost') {
        $host.UI.RawUI.WindowTitle = 'Transform Claude Code'
    }

    Write-Host "Transform repo: $repoRoot" -ForegroundColor Cyan

    if (Test-Path -LiteralPath $repoMemoryFile) {
        Write-Host "Repo memory loaded from $repoMemoryFile" -ForegroundColor DarkGray
    } else {
        Write-Warning "Repo memory file is missing: $repoMemoryFile"
    }

    if (Test-Path -LiteralPath $repoSkillsRoot) {
        Write-Host "Repo-local Claude skills detected." -ForegroundColor DarkGray
    } else {
        Write-Warning "Repo-local Claude skills folder is missing: $repoSkillsRoot"
    }

    $claudeCommand = Resolve-ClaudeCommand
    if (-not $claudeCommand) {
        throw "The 'claude' command could not be found. Expected it on PATH or under $env:APPDATA\npm."
    }

    Write-Host "Launching Claude via $claudeCommand" -ForegroundColor DarkGray
    & $claudeCommand @ClaudeArgs
    exit $LASTEXITCODE
} catch {
    Write-Error $_.Exception.Message
    exit 1
}
