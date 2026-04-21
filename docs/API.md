# Intune.Up API Reference

## Endpoints

### 1. POST /api/collect — Device Telemetry Collection

Receives telemetry data from managed devices and routes it through Service Bus to Log Analytics.

**Authentication:** Function Key (pass as `?code=<key>` query parameter)

#### Request

```http
POST https://<func-http>.azurewebsites.net/api/collect?code=<function-key>
Content-Type: application/json
```

#### Payload Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `DeviceId` | string | ✅ **Yes** | Unique device identifier (e.g., Intune device ID) |
| `UseCase` | string | ✅ **Yes** | Determines the Log Analytics table name: `IntuneUp_{UseCase}_CL` |
| `DeviceName` | string | No | Friendly device name (defaults to "UNKNOWN") |
| `UPN` | string | No | User Principal Name of the logged-in user |
| `Data` | object | No | **Flexible key-value pairs** — any additional data. All keys are flattened into the Log Analytics record |

> **UseCase determines the table:** If `UseCase = "BitLockerStatus"`, data goes to `IntuneUp_BitLockerStatus_CL`.
> Only alphanumeric characters and underscores are kept in the table name.

#### Payload Examples

**Minimal payload:**
```json
{
  "DeviceId": "device-abc-123",
  "UseCase": "Heartbeat"
}
```

**Full payload with custom data:**
```json
{
  "DeviceId": "device-abc-123",
  "DeviceName": "LAPTOP-USER01",
  "UPN": "user@contoso.com",
  "UseCase": "BitLockerStatus",
  "Data": {
    "EncryptionStatus": "Encrypted",
    "ProtectionStatus": "On",
    "EncryptionMethod": "XtsAes256",
    "Volume": "C:",
    "KeyProtectors": "Tpm, RecoveryPassword"
  }
}
```

**Custom telemetry (any fields in Data):**
```json
{
  "DeviceId": "device-xyz-789",
  "UseCase": "SoftwareInventory",
  "Data": {
    "AppName": "Microsoft Teams",
    "Version": "24.1.0",
    "InstallDate": "2024-01-15",
    "Publisher": "Microsoft"
  }
}
```

#### Response

**Success (202 Accepted):**
```json
{
  "status": "accepted",
  "deviceId": "device-abc-123",
  "messageId": null
}
```

**Validation Error (400):**
```json
{
  "error": "Missing required fields: DeviceId, UseCase"
}
```

#### Data Flow

```
Client → POST /api/collect → Service Bus (device-telemetry queue)
                                    ↓
                              SB Processor Function
                                    ↓
                            Log Analytics table: IntuneUp_{UseCase}_CL
```

---

### 2. GET /api/password-expiry — Password Expiry Check

Checks if a user's password is expiring soon. Reads from Azure Table Storage (populated by an Automation Runbook).

**Authentication:** Function Key

#### Request

```http
GET https://<func-http>.azurewebsites.net/api/password-expiry?upn=user@contoso.com&code=<function-key>
```

| Parameter | Required | Description |
|-----------|----------|-------------|
| `upn` | ✅ Yes | User Principal Name to check |

#### Responses

**Password NOT expiring (200):**
```json
{
  "Expiring": false
}
```

**Password expiring (200):**
```json
{
  "Expiring": true,
  "DaysUntilExpiry": 7,
  "ExpiryDate": "2024-03-15",
  "UserUPN": "user@contoso.com"
}
```

---

### 3. POST /api/password-change-webhook — Password Change Notification

Webhook endpoint for Entra ID audit events. When a user changes their password, removes them from the expiry notifications table.

**Authentication:** Function Key

Accepts multiple notification formats:
- Simple JSON: `{ "upn": "user@domain.com" }`
- Microsoft Graph change notifications
- Entra ID Audit Log records

---

## Getting Function Keys

```powershell
# Via Azure CLI REST API
$funcId = az functionapp show -g <rg> -n <func-name> --query "id" -o tsv
az rest --method post --uri "$funcId/host/default/listkeys?api-version=2022-03-01" -o json
```
