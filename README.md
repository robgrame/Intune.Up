# Intune.Up

**Enterprise device management automation built on Microsoft Intune and Azure.**

A modular, production-ready framework to implement silent remediations, user-facing campaigns, on-demand Service Desk actions, and custom data collection — without third-party agents.

---

## Overview

Intune.Up provides reusable patterns and templates for:

- **Silent remediations** – scheduled, automated fixes running in SYSTEM context
- **User-facing campaigns** – dual-context pattern (SYSTEM action + USER toast notification)
- **Service Desk L1 actions** – on-demand scripts triggered from the Intune portal
- **Custom data collection** – secure telemetry pipeline from endpoints to Log Analytics
- **Reporting** – KQL queries and Azure Monitor Workbooks ready to deploy

All scripts are written in **PowerShell**, deployable via **Intune Remediations** or **Platform Scripts** with no additional agents required on endpoints.

---

## Architecture

### Data Collection Pipeline

```
┌─────────────────────┐
│  Endpoint (SYSTEM)  │  PowerShell collect script
│  collect.ps1        │  + client X.509 certificate
└────────┬────────────┘
         │ HTTPS POST
         ▼
┌─────────────────────┐
│ Azure Function      │  Validates certificate thumbprint
│ HTTP Trigger        │  Enqueues message
└────────┬────────────┘
         │ Service Bus
         ▼
┌─────────────────────┐
│ Azure Function      │  Processes message
│ Service Bus Trigger │  Writes to Log Analytics
└────────┬────────────┘
         │
         ▼
┌─────────────────────┐
│  Log Analytics WS   │  Custom log tables (via DCR/DCE)
│  KQL / Workbooks    │  DCR stream → table mapping
└─────────────────────┘
```

### User Notification Pattern (dual-context)

```
Intune Remediation
    └── detect.ps1            [SYSTEM]
    └── remediate-system.ps1  [SYSTEM]
            └── Creates one-time Scheduled Task
                    └── notify-user.ps1  [USER context]
                            └── Toast Notification
```

---

## Repository Structure

```
Intune.Up/
├── remediations/
│   ├── silent/                       # Automated remediations (no UI)
│   │   ├── _template/
│   │   └── cleanup-windows-temp/
│   └── ui/                           # Remediations with user interaction
│       ├── _template/
│       ├── reboot-reminder/
│       └── password-expiry-reminder/
├── data-collection/
│   ├── scripts/
│   │   ├── _template/
│   │   └── login-information/
│   └── collector/
│       ├── function-http/            # Azure Function: HTTP entry point (PS1 reference)
│       └── function-sb/              # Azure Function: Service Bus processor (PS1 reference)
├── src/                              # .NET 10 solution (production)
│   ├── IntuneUp.Collector.Http/      # HTTP trigger Function (C#)
│   ├── IntuneUp.Collector.ServiceBus/ # Service Bus trigger Function (C#)
│   └── IntuneUp.Common/             # Shared models + CertificateValidator
├── service-desk/
│   └── runbooks/
│       ├── clear-chrome-settings/
│       └── server-side/
├── reporting/
│   ├── kql/
│   └── workbooks/
├── infrastructure/
│   └── bicep/
└── docs/
    ├── architecture.md
    └── patterns/
```

---

## Use Cases

### Silent Remediations

| Use Case | Description | Schedule |
|----------|-------------|----------|
| `cleanup-windows-temp` | Cleans Windows temp folders across all user profiles. Excludes `.docx .xlsx .csv .pptx`. Empties Recycle Bin. | 2x/week |

### User Campaigns (dual-context)

| Use Case | Description | Schedule |
|----------|-------------|----------|
| `reboot-reminder` | Detects devices with last reboot >14 days. Toast notification asks user to restart. | Daily |
| `password-expiry-reminder` | Server-side trigger file pattern. Detection reads days-until-expiry. Notification links to SSPR portal. | Daily |

> Each campaign ships two notification implementations: **native Windows Toast XML** (no dependencies) and **BurntToast** (richer UI). Choose based on your environment.

### Service Desk L1 (on-demand)

| Use Case | Description |
|----------|-------------|
| `clear-chrome-settings` | Clears Chrome history, cookies, cache, session data across all user profiles. Gracefully handles running Chrome. |

### Data Collection (GETINFO)

| Use Case | Collects | Table |
|----------|----------|-------|
| `login-information` | Last logged-on user, session type, Azure AD/Domain join status, recent logon events, uptime | `IntuneUp_LoginInformation_CL` |

---

## Getting Started

### Prerequisites

- Microsoft Intune tenant
- Azure subscription (Log Analytics, Azure Functions, Service Bus)
- PowerShell 5.1+ on managed Windows endpoints
- Client X.509 certificate distributed to endpoints via Intune (SCEP or PKCS)

### Deploy Infrastructure

The automated `deploy.ps1` script handles the complete deployment pipeline:

```powershell
# Deploy to westeurope (recommended - tested and verified)
.\deploy.ps1 -Environment prod -Location westeurope

# Or if you have a CA certificate thumbprint for mTLS validation:
.\deploy.ps1 -Environment prod -Location westeurope -AllowedIssuerThumbprints "ABC123..."

# Skip build if you've already compiled the functions:
.\deploy.ps1 -Environment prod -Location westeurope -SkipBuild
```

**Manual Deployment (if you prefer):**

```bash
az login
az group create --name rg-intuneup-prod --location westeurope

az deployment group create \
  --resource-group rg-intuneup-prod \
  --template-file infrastructure/bicep/main.bicep \
  --parameters environment=prod location=westeurope
```

> **Note:** This subscription has VM quota constraints in `eastus`. Use `westeurope` or other available regions. See [DEPLOYMENT-SUCCESS.md](DEPLOYMENT-SUCCESS.md) for details.

### Complete mTLS Setup (Admin Only)

After deploying infrastructure, the HTTP Function requires certificate authorization:

```powershell
# Admin authorizes the test certificate
.\authorize-certificate.ps1 `
  -KeyVaultName "kv-intuneup-prod" `
  -Thumbprint "4E050ADBD50A4132C1CC2B237929E113431993D2"
```

See [docs/ADMIN-GUIDE.md](docs/ADMIN-GUIDE.md) for detailed procedures.

### Test the Endpoint

#### Local Testing (Development)

```powershell
# Start local function emulator
cd src/IntuneUp.Collector.Http
func start --csharp

# In another terminal: Run test client
.\test-client-basic.ps1 -FunctionUrl "http://localhost:7071/api/collect"

# Expected output: ✅ Payload accepted (HTTP 202)
```

#### Production Testing

```powershell
# Test with existing certificate (after authorization)
.\test-client.ps1 `
  -FunctionUrl "https://func-intuneup-http-prod.azurewebsites.net/api/collect" `
  -ResourceGroup "rg-intuneup-prod" `
  -FunctionAppName "func-intuneup-http-prod" `
  -SkipCertSetup

# Basic connectivity check (no mTLS)
.\test-client-basic.ps1 `
  -FunctionUrl "https://func-intuneup-http-prod.azurewebsites.net/api/collect"
```

See [TEST-CLIENT.md](TEST-CLIENT.md) for examples and troubleshooting. See [DEPLOYMENT-STATUS.md](DEPLOYMENT-STATUS.md) for latest testing results.
  --resource-group rg-intuneup-dev \
  --template-file infrastructure/bicep/main.bicep \
  --parameters baseName=intuneup environment=dev \
               allowedCertThumbprints="<thumbprint1>,<thumbprint2>"
```

### Deploy a Remediation

1. **Intune portal** → Devices → Scripts and Remediations → Remediations → Create
2. Upload `detect.ps1` and `remediate.ps1` from the use case folder
3. Set: Run in 64-bit PowerShell = Yes | Run as logged-on credentials = No (SYSTEM)
4. Assign to device group and configure schedule

For UI campaigns, deploy `notify-user.ps1` to `C:\ProgramData\IntuneUp\notify\{UseCase}\` via a Platform Script first.

---

## Naming Convention

```
INTUNEUP-{CATEGORY}-{Description}

SILENT  – automated, no user interaction
UI      – with user notification (dual-context)
MANUAL  – on-demand (Service Desk)
GETINFO – data collection, no system changes
```

---

## Security

- Endpoints **never write directly** to Log Analytics
- Client authentication via **X.509 certificate thumbprint** allowlist
- Service Bus access via **Managed Identity** (recommended)
- All Azure Functions: HTTPS-only, TLS 1.2 minimum
- Server-side trigger files include a **25-hour staleness check** to prevent stale campaigns

---

## Reporting

Import `reporting/workbooks/device-telemetry.workbook.json` into **Azure Monitor Workbooks** for a dashboard covering active devices, pending reboots, join type distribution, and full device snapshots. KQL queries in `reporting/kql/queries.kql`.

---

## Roadmap

- [ ] AI Assistant integration via MCP server (Teams bot compatible)
- [ ] BitLocker status data collection
- [ ] WMI repair remediation
- [ ] SCCM agent health remediation
- [ ] Automated certificate rotation runbook

---

## License

MIT
