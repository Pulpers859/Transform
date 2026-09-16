function Get-GeneratorAuditCLIArguments {
    param([Parameter(Mandatory)][string]$MCPConfigPath)
    @('--print', '--safe-mode', '--permission-mode', 'dontAsk',
        '--strict-mcp-config', '--mcp-config', $MCPConfigPath,
        '--tools=', '--output-format', 'text')
}

function Get-GeneratorAuditVerdict {
    param([AllowEmptyString()][AllowNull()][string]$ReviewText)

    # This verifies an explicit completed-review shape, not review quality or approval.
    if ([string]::IsNullOrWhiteSpace($ReviewText) -or $ReviewText.Length -lt 300) {
        return $null
    }
    $nonemptyLines = @($ReviewText -split '\r?\n' | Where-Object { $_.Trim().Length -gt 0 })
    $fenceCharacter = $null
    $fenceLength = 0
    foreach ($line in $nonemptyLines) {
        if ($line -match '^\s*(`{3,}|~{3,})(.*)$') {
            $marker = $Matches[1]
            $suffix = $Matches[2]
            if ($null -eq $fenceCharacter) {
                $fenceCharacter = $marker[0]
                $fenceLength = $marker.Length
            } elseif ($marker[0] -eq $fenceCharacter -and $marker.Length -ge $fenceLength -and
                [string]::IsNullOrWhiteSpace($suffix)) {
                $fenceCharacter = $null
                $fenceLength = 0
            }
        }
    }
    if ($null -ne $fenceCharacter) { return $null }
    $lastLine = $nonemptyLines[-1].Trim() -replace '^#{1,6}\s+', ''
    $lastLine = $lastLine.Replace('**', '').Trim()
    if ($lastLine -match '^(?i:(?:Verdict:\s*)?(APPROVE WITH FOLLOW-UPS|REQUEST CHANGES|APPROVE))\.?$') {
        return $Matches[1].ToUpperInvariant()
    }
    return $null
}
