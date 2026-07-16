param(
    [string]$OutputPath = '.agents\generator-second-audit.md',
    [switch]$ValidateOnly
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
$untrackedFiles = @(git ls-files --others --exclude-standard)
if ($untrackedFiles.Count -gt 0) {
    throw "Untracked files are not sent to Claude Code. Stage the intended review files first, then rerun. Untracked: $($untrackedFiles -join ', ')"
}

$status = git status --short
$changedFiles = @(git diff --name-only HEAD --)
$diffText = git diff --no-ext-diff HEAD -- | Out-String
if ([string]::IsNullOrWhiteSpace($diffText)) {
    throw "No tracked or staged diff exists for review."
}
if ($diffText.Length -gt 200000) {
    throw "The review diff exceeds 200,000 characters. Split the change into a smaller auditable unit."
}

$secretPatterns = @(
    'sk-ant-[A-Za-z0-9_-]{20,}',
    'sk-[A-Za-z0-9_-]{32,}',
    'github_pat_[A-Za-z0-9_]{20,}',
    'gh[opsru]_[A-Za-z0-9]{20,}',
    'AKIA[0-9A-Z]{16}',
    'ASIA[0-9A-Z]{16}',
    'xox[baprs]-[A-Za-z0-9-]{20,}',
    'AIza[0-9A-Za-z_-]{30,}',
    '-----BEGIN ([A-Z ]+ )?PRIVATE KEY-----',
    'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}',
    '(?i)(api[_-]?key|client[_-]?secret|password|access[_-]?token)\s*[:=]\s*["'']?[A-Za-z0-9_./+=-]{20,}'
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
    '## Tracked And Staged Diff',
    '```diff',
    $diffText,
    '```'
) -join "`n"
Set-Content -LiteralPath $packetPath -Value $packet -Encoding utf8
if ($ValidateOnly) {
    Write-Host "Review packet and credential checks passed: $packetPath" -ForegroundColor Cyan
    exit 0
}

$prompt = @"
Perform a second, adversarial review of the current Transform generator changes. The change
may affect the workout generator, the nutrition generator, or both; audit the surfaces that
actually appear in the packet rather than assuming this is a workout-only change.

Repository: $repoRoot
You have no tools and cannot inspect any file beyond the sanitized review packet included below.
Do not request secrets or claim to have run builds, tests, APIs, or source-tree searches.

Transform priorities, in order: workout quality, evidence-informed programming integrity,
robustness and silent-failure prevention, validator correctness, API cost, maintainability.
Fix root causes instead of trimming output or weakening validator findings.

Assume the first implementation is incomplete. Findings must lead, ordered by severity,
with exact file and line references. Audit these independently:
- for workout changes, whether deterministic fixture replay genuinely covers the reported failure
  class and whether the production request, parsing, sanitization, menu/blueprint prescription,
  validator, and fallback behavior remain aligned;
- for nutrition changes, whether effective macro targets have one safety-resolved source of truth,
  meal/template macro arithmetic agrees across calories, protein, carbohydrates, and fat, meal
  identity/order and grocery content are genuinely usable, and fallback output is coherent for
  low, high, missing, and internally inconsistent targets;
- whether any live smoke test exercises the production request, parsing, sanitization, validator,
  persistence/orchestration, and fallback behavior without overstating equivalence;
- whether partial generation, fallback transitions, and retry decisions avoid mixed-source output
  and unnecessary paid calls;
- whether any credential can leak into logs, artifacts, tracked files, or the iPhone build;
- whether API spend is explicitly gated and bounded;
- whether a green result proves workout quality, not merely schema or validator cleanliness;
- missing tests, CI failure modes, and misleading documentation.

Finish with one of: APPROVE, APPROVE WITH FOLLOW-UPS, or REQUEST CHANGES. Be blunt and concise.

$packet
"@

$claudeArgs = @(
    '--print',
    '--permission-mode', 'plan',
    '--tools=',
    '--output-format', 'text'
)
$review = $prompt | & $claudeCommand @claudeArgs 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "Claude Code review failed with exit code $LASTEXITCODE.`n$($review -join "`n")"
}
if (-not $review -or [string]::IsNullOrWhiteSpace(($review -join "`n"))) {
    throw "Claude Code returned an empty review."
}
$reviewText = $review -join "`n"
if ($reviewText.Length -lt 300 -or $reviewText -notmatch '(?i)(finding|verdict|approve|request changes|follow-up)') {
    throw "Claude Code returned an incomplete review; refusing to treat it as an audit."
}

Set-Content -LiteralPath $outputFile -Value ($review -join "`n") -Encoding utf8
Write-Host "Claude second audit saved to $outputFile" -ForegroundColor Cyan
