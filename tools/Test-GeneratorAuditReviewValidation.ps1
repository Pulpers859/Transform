$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'GeneratorAuditReviewValidation.ps1')

$body = ('Source-only review. Findings were checked against the supplied diff; no execution is claimed. ' * 4)
$cases = @(
    @{ Name = 'empty'; Text = ''; Expected = $null },
    @{ Name = 'short verdict'; Text = 'APPROVE'; Expected = $null },
    @{ Name = 'unfinished narrative'; Text = $body + 'Writing the findings to the plan file now.'; Expected = $null },
    @{ Name = 'quoted verdict'; Text = $body + "`n> APPROVE"; Expected = $null },
    @{ Name = 'instructions not verdict'; Text = $body + "`nFinish with APPROVE or REQUEST CHANGES."; Expected = $null },
    @{ Name = 'earlier verdict'; Text = $body + "`nAPPROVE`nReview still in progress."; Expected = $null },
    @{ Name = 'unclosed code'; Text = $body + "`n~~~text`nAPPROVE"; Expected = $null },
    @{ Name = 'closed code verdict'; Text = $body + "`n~~~text`nAPPROVE`n~~~"; Expected = $null },
    @{ Name = 'mismatched fence'; Text = $body + "`n" + '```text' + "`n~~~`nAPPROVE"; Expected = $null },
    @{ Name = 'short closing fence'; Text = $body + "`n~~~~text`n~~~`nAPPROVE"; Expected = $null },
    @{ Name = 'closing fence with info'; Text = $body + "`n~~~text`n~~~more`nAPPROVE"; Expected = $null },
    @{ Name = 'compatible longer close'; Text = $body + "`n~~~text`nexcerpt`n~~~~`nAPPROVE"; Expected = 'APPROVE' },
    @{ Name = 'approval'; Text = $body + "`nAPPROVE"; Expected = 'APPROVE' },
    @{ Name = 'followups'; Text = $body + "`nAPPROVE WITH FOLLOW-UPS"; Expected = 'APPROVE WITH FOLLOW-UPS' },
    @{ Name = 'changes are valid review not approval'; Text = $body + "`nREQUEST CHANGES"; Expected = 'REQUEST CHANGES' },
    @{ Name = 'markdown verdict'; Text = $body + "`n## Verdict: **REQUEST CHANGES**`n"; Expected = 'REQUEST CHANGES' },
    @{ Name = 'bold label'; Text = $body + "`n**Verdict:** **APPROVE WITH FOLLOW-UPS**"; Expected = 'APPROVE WITH FOLLOW-UPS' }
)
foreach ($case in $cases) {
    $actual = Get-GeneratorAuditVerdict -ReviewText $case.Text
    if ($actual -cne $case.Expected) { throw "$($case.Name): expected '$($case.Expected)', got '$actual'" }
}
$expectedArguments = @('--print', '--safe-mode', '--permission-mode', 'dontAsk',
    '--strict-mcp-config', '--mcp-config', 'C:\review folder\empty.json',
    '--tools=', '--output-format', 'text')
$actualArguments = @(Get-GeneratorAuditCLIArguments -MCPConfigPath 'C:\review folder\empty.json')
if (($actualArguments -join "`n") -cne ($expectedArguments -join "`n")) {
    throw 'The no-tools review invocation contract changed.'
}
Write-Output "PASS: $($cases.Count) review-completion checks. A verdict is not proof of review quality."
Write-Output 'PASS: exact isolated-review arguments, including a path with spaces.'
