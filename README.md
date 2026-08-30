# Microsoft Agent 365: Active Users Export & Governance Toolkit

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207%2B-blue.svg)](https://github.com/PowerShell/PowerShell)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![MSEndpoint](https://img.shields.io/badge/Guide-MSEndpoint.com-cyan.svg)](https://msendpoint.com/article/microsoft-agent-365-active-users-export-enable-agent-usage-reporting-for-licensing-governance)

Production-grade PowerShell automation and governance auditing toolkit for **Microsoft Agent 365 Active Users reporting** ([MC1462914](https://msendpoint.com/article/microsoft-agent-365-active-users-export-enable-agent-usage-reporting-for-licensing-governance)).

---

## 📌 Overview

Per Microsoft Message Center announcement **MC1462914**, Microsoft 365 Global Admins and AI Admins can export a 30-day active user inventory from:
`Microsoft 365 admin center > Agents > All Agents > Export`

This toolkit provides:
- **Resilient Microsoft Graph Authentication**: Automatic detection of existing sessions + fallback to Device Code login (eliminates WAM / embedded terminal window handle errors).
- **Auto-Prerequisite Resolver**: Checks and auto-installs required Microsoft Graph modules.
- **Licensing Cost Optimization**: Audits exported active users, identifies dormant users with zero sessions, and flags accounts eligible for Copilot / Agent license reclamation.
- **Audit-Ready Reporting**: Outputs filtered CSV and executive summaries.

---

## 🚀 Quick Start

### 1. Clone the repository
```powershell
git clone https://github.com/Msendpoint/agent365-active-users-export.git
cd agent365-active-users-export
```

### 2. Run the One-Click Launcher
```powershell
.\Install.ps1
```

Or run the script directly with your exported Agent 365 CSV:
```powershell
.\scripts\Export-Agent365ActiveUsers.ps1 -CsvPath ".\Agent365_ActiveUsers.csv" -OutputPath ".\output"
```

---

## 📋 CSV Schema Specification (MC1462914)

| Column Name | Type | Description |
| :--- | :--- | :--- |
| **User Principal Name (UPN)** | `String` | Corporate identity / user email |
| **Total Agents Used** | `Integer` | Number of distinct registered agents accessed |
| **Total Sessions** | `Integer` | Total interaction sessions within 30-day window |
| **Last Activity Date** | `DateTime` | Timestamp of the most recent agent invocation |

---

## 🛡️ Requirements & Permissions

- **PowerShell**: 5.1 or PowerShell 7+
- **Administrative Role**: `AI Administrator` or `Global Administrator`
- **Microsoft Graph Scopes**: `User.Read.All`, `RoleManagement.Read.Directory`, `Organization.Read.All`

---

## 👨‍💻 Author & Community

- **Author**: [Souhaiel Morhag](https://linkedin.com/in/souhaiel-morhag)
- **Technical Deep-Dive**: [MSEndpoint.com Guide](https://msendpoint.com/article/microsoft-agent-365-active-users-export-enable-agent-usage-reporting-for-licensing-governance)
- **MSEndpoint Academy**: [app.msendpoint.com/academy](https://app.msendpoint.com/academy)

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).