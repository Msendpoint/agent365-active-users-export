### FILE: scripts/Export-Agent365ActiveUsers.ps1
<#
.SYNOPSIS
    Exports the Microsoft Agent 365 Active Users report using the Microsoft Graph beta endpoint.

.DESCRIPTION
    This script connects to Microsoft Graph and retrieves the Agent 365 Active Users usage report
    (getAgent365ActiveUserDetail) for a specified reporting period (D7, D30, D90, D180).
    It targets the /beta Graph endpoint per Microsoft's current rollout pattern for Agent 365
    usage reporting (MC1462914), validates the returned schema before parsing, handles
    pseudonymized/concealed identity output gracefully, and exports the results to CSV for
    licensing reconciliation and governance review.

    Because this targets a /beta endpoint, the script performs a defensive schema check on the
    first row of returned data and will warn (not silently fail) if expected columns are missing
    or renamed, consistent with known beta reporting endpoint instability (e.g. the Q1 2025
    getM365CopilotUsageUserDetail column reshuffle).

.EXAMPLE
    .\Export-Agent365ActiveUsers.ps1 -Period D30 -OutputPath "C:\Reports\Agent365ActiveUsers.csv"

.EXAMPLE
    .\Export-Agent365ActiveUsers.ps1 -Period D90 -OutputPath "C:\Reports\Agent365_90Day.csv" -Verbose

.NOTES
    Author:      Souhaiel Morhag
    Company:     MSEndpoint.com
    Blog:        https://msendpoint.com
    Academy:     https://app.msendpoint.com/academy
    LinkedIn:    https://linkedin.com/in/souhaiel-morhag
    GitHub:      https://github.com/Msendpoint
    License:     MIT
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('D7', 'D30', 'D90', 'D180')]
    [string]$Period = 'D30',

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = ".\Agent365ActiveUsers_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv",

    [Parameter(Mandatory = $false)]
    [switch]$SkipSchemaValidation
)

# Expected schema based on getM365CopilotUsageUserDetail conventions (subject to /beta change)
$expectedColumns = @(
    'User Principal Name',
    'Display Name',
    'Agent Name',
    'Agent ID',
    'Last Activity Date',
    'Interaction Count',
    'Product/Workload'
)

function Test-Agent365Schema {
    param(
        [Parameter(Mandatory = $true)]
        [object]$SampleRow,
        [Parameter(Mandatory = $true)]
        [string[]]$ExpectedColumns
    )

    $actualColumns = $SampleRow.PSObject.Properties.Name
    $missing = $ExpectedColumns | Where-Object { $_ -notin $actualColumns }

    if ($missing.Count -gt 0) {
        Write-Warning "Schema drift detected on /beta endpoint. Missing/renamed columns: $($missing -join ', ')"
        Write-Warning "Do not assume column order. Review Microsoft's current getAgent365ActiveUserDetail schema before trusting this export in production licensing workflows."
        return $false
    }

    return $true
}

try {
    # Ensure Microsoft Graph PowerShell SDK is available
    if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
        throw "Microsoft.Graph.Authentication module not found. Install with: Install-Module Microsoft.Graph -Scope CurrentUser"
    }

    Write-Verbose "Connecting to Microsoft Graph with Reports.Read.All scope..."
    Connect-MgGraph -Scopes "Reports.Read.All" -NoWelcome -ErrorAction Stop

    # Construct the beta endpoint call - naming convention per MC1462914 reconstruction
    $endpoint = "/beta/reports/getAgent365ActiveUserDetail(period='$Period')?`$format=application/json"
    Write-Verbose "Calling Graph endpoint: $endpoint"

    $response = Invoke-MgGraphRequest -Method GET -Uri $endpoint -ErrorAction Stop

    # Normalize response - Graph reports endpoints can return either 'value' array or raw CSV-shaped JSON
    $rows = if ($response.value) { $response.value } else { $response }

    if (-not $rows -or $rows.Count -eq 0) {
        Write-Warning "No rows returned. This may indicate:"
        Write-Warning " - No agent activity in the selected $Period window"
        Write-Warning " - 24-48h reporting latency has not yet elapsed for recent activity"
        Write-Warning " - Your role (Reports Reader / Global Admin) lacks Agent 365 report scope"
        Write-Warning "Check Org Settings > Services > Reports > 'Display concealed names in all reports' before filing a support ticket."
        return
    }

    # Defensive schema validation against known beta instability
    if (-not $SkipSchemaValidation) {
        $null = Test-Agent365Schema -SampleRow $rows[0] -ExpectedColumns $expectedColumns
    }

    # Detect pseudonymized/concealed identities (e.g., User1234 pattern)
    $concealedCount = ($rows | Where-Object { $_.'User Principal Name' -match '^User\d+$' }).Count
    if ($concealedCount -gt 0) {
        Write-Warning "$concealedCount row(s) contain pseudonymized identifiers (e.g., User1234)."
        Write-Warning "This is expected behavior when 'Display concealed names in all reports' is disabled - not a bug."
        Write-Warning "UPN-based joins against HR/CMDB feeds will fail silently for these rows."
    }

    # Export to CSV
    $rows | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
    Write-Host "Export complete: $OutputPath ($($rows.Count) rows)" -ForegroundColor Green

}
catch {
    Write-Error "Failed to export Agent 365 Active Users report: $($_.Exception.Message)"
    Write-Error "If this is a 404/BadRequest on the /beta endpoint, Microsoft may have changed the getAgent365ActiveUserDetail schema or path. Verify against your tenant's live Graph metadata."
}
finally {
    if (Get-MgContext) {
        Disconnect-MgGraph | Out-Null
        Write-Verbose "Disconnected from Microsoft Graph."
    }
}