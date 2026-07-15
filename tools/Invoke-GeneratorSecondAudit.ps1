param(
    [string]$OutputPath = '.agents\generator-second-audit.md'
)

$ErrorActionPreference = 'Stop'
$repoRoot = 'C:\Dev\Transform_clean'

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

Set-Location -LiteralPath $repoRoot
$claudeCommand = Resolve-ClaudeCommand
if (-not $claudeCommand) {
    throw "Claude Code is not installed or available on PATH."
}

$outputFile = if ([System.IO.Path]::IsPathRooted($OutputPath)) {
    $OutputPath
} else {
    Join-Path $repoRoot $OutputPath
}
$outputDirectory = Split-Path -Parent $outputFile
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null

$packetPath = Join-Path $outputDirectory 'generator-review-packet.md'
$status = git status --short
$diff = git diff --no-ext-diff HEAD --
$trackedFiles = git diff --name-only HEAD --
$untrackedFiles = git ls-files --others --exclude-standard
$changedFiles = @($trackedFiles) + @($untrackedFiles) | Sort-Object -Unique
$untrackedSections = foreach ($file in $untrackedFiles) {
    $fullPath = Join-Path $repoRoot $file
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { continue }
    $content = Get-Content -Raw -LiteralPath $fullPath
    @(
        "## Untracked File: $file",
        '```text',
        $content,
        '```',
        ''
    ) -join "`n"
}

$diffText = @(
    ($diff -join "`n"),
    ($untrackedSections -join "`n")
) -join "`n"
$secretPatterns = @(
    'sk-ant-[A-Za-z0-9_-]{20,}',
    'sk-[A-Za-z0-9_-]{32,}',
    'gh[opsu]_[A-Za-z0-9]{20,}'
)
foreach ($pattern in $secretPatterns) {
    if ($diffText -match $pattern) {
        throw "Potential live credential detected in the diff. Review locally before sending anything to Claude Code."
    }
}

$packet = @(
    '# Transform Generator Review Packet',
    '',
    '## Working Tree Status',
    '```text',
    ($status -join "`n"),
    '```',
    '',
    '## Changed Files',
    '```text',
    ($changedFiles -join "`n"),
    '```',
    '',
    '## Tracked Diff And Untracked File Contents',
    '```diff',
    $diffText,
    '```'
) -join "`n"
Set-Content -LiteralPath $packetPath -Value $packet -Encoding utf8

$prompt = @"
Perform a second, adversarial review of the current Transform generator changes.

Repository: $repoRoot
Start with AGENTS.md and this packet: $packetPath
You have read-only tools only. Do not edit files, run builds, invoke APIs, or expose secrets.

Assume the first implementation is incomplete. Findings must lead, ordered by severity,
with exact file and line references. Audit these independently:
- whether deterministic fixture replay genuinely covers the historical five maintenance-volume errors;
- whether the optional live smoke test exercises the production request, parsing, sanitization,
  set-prescription, validator, and fallback behavior without overstating equivalence;
- whether any credential can leak into logs, artifacts, tracked files, or the iPhone build;
- whether API spend is explicitly gated and bounded;
- whether a green result proves workout quality, not merely schema or validator cleanliness;
- missing tests, CI failure modes, and misleading documentation.

Finish with one of: APPROVE, APPROVE WITH FOLLOW-UPS, or REQUEST CHANGES. Be blunt and concise.
"@

$review = & $claudeCommand -p --permission-mode plan --tools 'Read,Grep,Glob' --output-format text $prompt 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "Claude Code review failed with exit code $LASTEXITCODE.`n$($review -join "`n")"
}
if (-not $review -or [string]::IsNullOrWhiteSpace(($review -join "`n"))) {
    throw "Claude Code returned an empty review."
}

Set-Content -LiteralPath $outputFile -Value ($review -join "`n") -Encoding utf8
Write-Host "Claude second audit saved to $outputFile" -ForegroundColor Cyan
