# Third-Party Notices

Intune.Up uses third-party libraries licensed under permissive open-source licenses.
This file lists those components together with their license information.

---

## NuGet Packages (MIT License)

The following packages are licensed under the **MIT License**:

| Package | Version | License |
|---------|---------|---------|
| Azure.Data.Tables | 12.11.0 | MIT |
| Azure.Identity | 1.21.0 | MIT |
| Azure.Messaging.ServiceBus | 7.20.1 | MIT |
| Azure.Monitor.Ingestion | 1.2.0 | MIT |
| Azure.Monitor.OpenTelemetry.Exporter | 1.2.0 | MIT |
| Azure.Security.KeyVault.Secrets | 4.10.0 | MIT |
| Azure.Storage.Blobs | 12.27.0 | MIT |
| Microsoft.ApplicationInsights.WorkerService | 2.23.0 | MIT |
| Microsoft.Azure.Functions.Worker | 2.51.0 | MIT |
| Microsoft.Azure.Functions.Worker.ApplicationInsights | 2.50.0 | MIT |
| Microsoft.Azure.Functions.Worker.Extensions.Http.AspNetCore | 2.1.0 | MIT |
| Microsoft.Azure.Functions.Worker.Extensions.ServiceBus | 5.24.0 | MIT |
| Microsoft.Azure.Functions.Worker.Sdk | 2.0.7 | MIT |
| Microsoft.Extensions.Configuration.AzureAppConfiguration | 8.5.0 | MIT |

MIT License: https://opensource.org/licenses/MIT

> Copyright (c) Microsoft Corporation. All rights reserved.
>
> Permission is hereby granted, free of charge, to any person obtaining a copy
> of this software and associated documentation files (the "Software"), to deal
> in the Software without restriction, including without limitation the rights
> to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
> copies of the Software, and to permit persons to whom the Software is
> furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in all
> copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
> IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
> FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.

---

## NuGet Packages (Apache 2.0 License)

| Package | Version | License |
|---------|---------|---------|
| OpenTelemetry | various | Apache 2.0 |
| OpenTelemetry.Api | various | Apache 2.0 |

Apache License 2.0: https://www.apache.org/licenses/LICENSE-2.0

---

## Azure Bicep Templates

The Bicep templates in `infrastructure/bicep/` are original work and part of this project.
They deploy Azure resources using the Azure Resource Manager API.

---

## PowerShell Modules (Automation Runbook)

The runbook `Write-PasswordExpiryTriggers.ps1` requires the following PowerShell modules
at runtime in Azure Automation:

| Module | License | Note |
|--------|---------|------|
| Microsoft.Graph.Authentication | MIT | Installed in Azure Automation |
| Microsoft.Graph.Users | MIT | Installed in Azure Automation |

These modules are **not redistributed** with this solution — they are installed
from the PowerShell Gallery at runtime.

---

## Microsoft Configuration Manager (SCCM)

Some remediation scripts in `remediations/` and `service-desk/` are designed to work
with **Microsoft Endpoint Configuration Manager (SCCM)** / **Microsoft Intune**.

These scripts require an existing SCCM/Intune license from Microsoft.
No SCCM components are redistributed as part of this solution.

---

## Summary

| License | Components |
|---------|------------|
| **MIT** | All Azure SDK NuGet packages, Microsoft.Graph modules, this solution |
| **Apache 2.0** | OpenTelemetry packages |
| **Commercial** | Microsoft SCCM/Intune (license required, not redistributed) |

There are **no licensing restrictions** preventing sharing this solution's source code.
