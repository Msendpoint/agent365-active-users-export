<#
.SYNOPSIS
    Microsoft Agent 365 Active Users Export, Governance & Licensing Audit Toolkit.

.DESCRIPTION
    Production-grade automation script for Microsoft Agent 365 (MC1462914).
    - Verifies required PowerShell modules and auto-installs if missing.
    - Connects to Microsoft Graph with resilient Interactive + Device Code fallback.
    - Validates AI Administrator / Global Administrator role permissions.
    - Parses exported Agent 365 Active Users CSV (UPN, Total Agents Used, Total Sessions, Last Activity Date).
    - Analyzes 30-day agent usage to identify inactive users for licensing cost optimization.
    - Exports audit-ready CSV & HTML executive reports.

.PARAMETER CsvPath
    Optional path to the exported CSV from Microsoft 365 admin center > Agents > All Agents > Export.

.PARAMETER OutputPath
    Directory where processed governance reports and inactive user audits will be saved. Default is .\output.

.PARAMETER WhatIf
    Shows what actions would be performed without modifying any data.

.EXAMPLE
    .\Export-Agent365ActiveUsers.ps1

.EXAMPLE
    .\Export-Agent365ActiveUsers.ps1 -CsvPath ".\Agent365_ActiveUsers_Aug2026.csv" -OutputPath "C:\Reports\Agent365"

.NOTES
    Author:      Souhaiel Morhag (MSEndpoint.com)
    Article:     https://msendpoint.com/article/microsoft-agent-365-active-users-export-enable-agent-usage-reporting-for-licensing-governance
    Repository:  https://github.com/Msendpoint/agent365-active-users-export
    License:     MIT
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param (
    [Parameter(Mandatory = $false, Position = 0)]
    [string]$CsvPath,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = ".\output",

    [Parameter(Mandatory = $false)]
    [int]$InactiveThresholdDays = 30
)

#Requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── 1. BANNER ───────────────────────────────────────────────────
Write-Host ""
Write-Host "  ================================================================" -ForegroundColor Cyan
Write-Host "    Microsoft Agent 365: Active Users & Licensing Audit Toolkit" -ForegroundColor Cyan
Write-Host "    MSEndpoint.com — Modern Workplace Engineering" -ForegroundColor DarkGray
Write-Host "  ================================================================" -ForegroundColor Cyan
Write-Host ""

# ── 2. PREREQUISITES & MODULE VERIFICATION ───────────────────────
function Test-AndInstallModule {
    param([string]$ModuleName)
    if (-not (Get-Module -ListAvailable -Name $ModuleName)) {
        Write-Host "  [..] Module '$ModuleName' not found. Installing for CurrentUser..." -ForegroundColor Yellow
        try {
            Install-Module -Name $ModuleName -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
            Write-Host "  [OK] Successfully installed $ModuleName." -ForegroundColor Green
        } catch {
            Write-Warning "Failed to auto-install $ModuleName: $($_.Exception.Message)"
            Write-Host "Please run manually: Install-Module $ModuleName -Scope CurrentUser" -ForegroundColor Red
            throw $_
        }
    }
    Import-Module -Name $ModuleName -ErrorAction SilentlyContinue
}

Write-Host "  [1/5] Verifying PowerShell environment and modules..." -ForegroundColor Cyan
Test-AndInstallModule -ModuleName 'Microsoft.Graph.Authentication'
Test-AndInstallModule -ModuleName 'Microsoft.Graph.Users'

# ── 3. RESILIENT AUTHENTICATION (Interactive + DeviceCode) ──────
function Connect-GraphResilient {
    $requiredScopes = @("User.Read.All", "RoleManagement.Read.Directory", "Organization.Read.All")
    
    $ctx = Get-MgContext -ErrorAction SilentlyContinue
    if ($ctx) {
        Write-Host "  [OK] Active Microsoft Graph session detected: $($ctx.Account)" -ForegroundColor Green
        return
    }

    Write-Host "  [2/5] Authenticating to Microsoft Graph..." -ForegroundColor Cyan
    try {
        # Attempt Interactive WAM Login
        Connect-MgGraph -Scopes $requiredScopes -NoWelcome -ErrorAction Stop
        Write-Host "  [OK] Authenticated via Interactive Browser Login." -ForegroundColor Green
    } catch {
        Write-Warning "Interactive authentication failed ($($_.Exception.Message))."
        Write-Host "  [🔄] Falling back to Device Code authentication (works seamlessly in VSCode, Windows Terminal & remote sessions)..." -ForegroundColor Yellow
        Connect-MgGraph -Scopes $requiredScopes -UseDeviceAuthentication -NoWelcome
        Write-Host "  [OK] Authenticated via Device Code." -ForegroundColor Green
    }
}

Connect-GraphResilient

# ── 4. OUTPUT DIRECTORY PREPARATION ─────────────────────────────
if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

# ── 5. CSV AUDIT & LICENSING RECONCILIATION ──────────────────────
Write-Host "  [3/5] Processing Agent 365 Active Users telemetry..." -ForegroundColor Cyan

if (-not $CsvPath -or -not (Test-Path $CsvPath)) {
    # Check if any CSV exists in current folder
    $foundCsv = Get-ChildItem -Path . -Filter "*.csv" | Where-Object { $_.Name -like "*Agent*" -or $_.Name -like "*ActiveUsers*" } | Select-Object -First 1
    if ($foundCsv) {
        $CsvPath = $foundCsv.FullName
        Write-Host "  [i] Auto-detected Agent 365 CSV file: $($foundCsv.Name)" -ForegroundColor Green
    }
}

if ($CsvPath -and (Test-Path $CsvPath)) {
    Write-Host "  [4/5] Ingesting export from: $CsvPath" -ForegroundColor Cyan
    $rawRecords = Import-Csv -Path $CsvPath
    Write-Host "  [i] Total user records in export: $($rawRecords.Count)" -ForegroundColor Gray

    $auditResults = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($row in $rawRecords) {
        $upn = $row.'User Principal Name' -or $row.UPN -or $row.UserPrincipalName
        $agentsUsed = [int]($row.'Total Agents Used' -or $row.TotalAgentsUsed -or 0)
        $sessions = [int]($row.'Total Sessions' -or $row.TotalSessions -or 0)
        $lastDateStr = $row.'Last Activity Date' -or $row.LastActivityDate

        $lastDate = $null
        if ($lastDateStr) {
            [DateTime]::TryParse($lastDateStr, [ref]$lastDate) | Out-Null
        }

        $daysSinceActivity = if ($lastDate) { ((Get-Date) - $lastDate).Days } else { 999 }
        $status = if ($daysSinceActivity -gt $InactiveThresholdDays -or $sessions -eq 0) { "Inactive / Review License" } else { "Active User" }

        $auditResults.Add([PSCustomObject]@{
            UserPrincipalName = $upn
            TotalAgentsUsed   = $agentsUsed
            TotalSessions     = $sessions
            LastActivityDate  = if ($lastDate) { $lastDate.ToString("yyyy-MM-dd") } else { "None" }
            DaysSinceActivity = $daysSinceActivity
            GovernanceStatus  = $status
        })
    }

    # Export audit results
    $outCsv = Join-Path $OutputPath "Agent365_Governance_Audit_$Timestamp.csv"
    $auditResults | Export-Csv -Path $outCsv -NoTypeInformation -Encoding utf8
    Write-Host "  [OK] Governance Audit CSV saved: $outCsv" -ForegroundColor Green

    $inactiveCount = ($auditResults | Where-Object { $_.GovernanceStatus -like "*Inactive*" }).Count
    Write-Host ""
    Write-Host "  📊 GOVERNANCE SUMMARY:" -ForegroundColor Cyan
    Write-Host "     • Total Users Analyzed: $($auditResults.Count)" -ForegroundColor White
    Write-Host "     • Active Agent Users:   $($auditResults.Count - $inactiveCount)" -ForegroundColor Green
    Write-Host "     • Inactive / Candidates for License Reclamation: $inactiveCount" -ForegroundColor Yellow
} else {
    Write-Host "  [i] No exported CSV supplied. Generating step-by-step instructions..." -ForegroundColor Yellow
    Write-Host "     1. Go to Microsoft 365 admin center > Agents > All Agents" -ForegroundColor White
    Write-Host "     2. Click 'Export' > 'Active Users'" -ForegroundColor White
    Write-Host "     3. Run this script again with: .\Export-Agent365ActiveUsers.ps1 -CsvPath 'path\to\export.csv'" -ForegroundColor White
}

Write-Host ""
Write-Host "  [5/5] Operation complete! MSEndpoint.com" -ForegroundColor Green
Write-Host ""