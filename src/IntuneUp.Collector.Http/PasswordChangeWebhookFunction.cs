using System.Net;
using System.Text.Json;
using Azure.Data.Tables;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;

namespace IntuneUp.Collector.Http;

/// <summary>
/// Webhook endpoint for Entra ID audit log events.
/// When a user changes their password, removes them from the
/// PasswordExpiry table so they stop receiving notifications.
///
/// Configure in Entra ID:
///   Monitoring > Diagnostic Settings > stream "AuditLogs" to Event Hub or
///   Azure Monitor > Alerts > Action Group > Webhook to this endpoint.
///
/// Alternatively, use Microsoft Graph subscriptions (change notifications)
/// on the user resource for passwordLastSet changes.
///
/// This function is NOT exposed to clients (separate from mTLS endpoint).
/// Secured via Function Key (AuthorizationLevel.Function).
/// </summary>
public sealed class PasswordChangeWebhookFunction
{
    private readonly ILogger<PasswordChangeWebhookFunction> _logger;
    private readonly TableClient _tableClient;

    public PasswordChangeWebhookFunction(
        ILogger<PasswordChangeWebhookFunction> logger,
        TableServiceClient tableServiceClient,
        IConfiguration configuration)
    {
        _logger = logger;
        var tableName = configuration["IntuneUp:PasswordExpiry:TableName"] ?? "PasswordExpiry";
        _tableClient = tableServiceClient.GetTableClient(tableName);
    }

    [Function("PasswordChangeWebhook")]
    public async Task<HttpResponseData> Run(
        [HttpTrigger(AuthorizationLevel.Function, "post", Route = "password-change-webhook")]
        HttpRequestData req)
    {
        // Microsoft Graph change notifications send a validation request first
        var query = System.Web.HttpUtility.ParseQueryString(req.Url.Query);
        var validationToken = query["validationToken"];
        if (!string.IsNullOrEmpty(validationToken))
        {
            _logger.LogInformation("Graph subscription validation request received");
            var validationResponse = req.CreateResponse(HttpStatusCode.OK);
            validationResponse.Headers.Add("Content-Type", "text/plain");
            await validationResponse.WriteStringAsync(validationToken);
            return validationResponse;
        }

        // Parse the notification payload
        string body;
        using (var reader = new StreamReader(req.Body))
            body = await reader.ReadToEndAsync();

        if (string.IsNullOrWhiteSpace(body))
        {
            var badReq = req.CreateResponse(HttpStatusCode.BadRequest);
            await badReq.WriteAsJsonAsync(new { error = "Empty body" });
            return badReq;
        }

        try
        {
            // Extract UPN from various notification formats
            var upns = ExtractUpnsFromNotification(body);

            foreach (var upn in upns)
            {
                var rowKey = upn.ToLowerInvariant();
                try
                {
                    await _tableClient.DeleteEntityAsync("PasswordExpiry", rowKey);
                    _logger.LogInformation("Removed password expiry record for {UPN} (password changed)", upn);
                }
                catch (Azure.RequestFailedException ex) when (ex.Status == 404)
                {
                    _logger.LogDebug("No expiry record found for {UPN} (already clean)", upn);
                }
            }

            var ok = req.CreateResponse(HttpStatusCode.OK);
            await ok.WriteAsJsonAsync(new { processed = upns.Count });
            return ok;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to process password change notification");
            var error = req.CreateResponse(HttpStatusCode.InternalServerError);
            await error.WriteAsJsonAsync(new { error = "Processing failed" });
            return error;
        }
    }

    /// <summary>
    /// Extracts UPNs from various notification formats:
    /// - Entra ID Audit Log (via Event Hub / Diagnostic Settings)
    /// - Microsoft Graph change notifications
    /// - Simple JSON: { "upn": "user@domain.com" }
    /// </summary>
    private static List<string> ExtractUpnsFromNotification(string body)
    {
        var upns = new List<string>();
        var doc = JsonDocument.Parse(body);

        // Format 1: Simple { "upn": "user@domain.com" }
        if (doc.RootElement.TryGetProperty("upn", out var upnProp))
        {
            var upn = upnProp.GetString();
            if (!string.IsNullOrEmpty(upn)) upns.Add(upn);
            return upns;
        }

        // Format 2: Graph change notification { "value": [ { "resourceData": { "userPrincipalName": "..." } } ] }
        if (doc.RootElement.TryGetProperty("value", out var valueProp) && valueProp.ValueKind == JsonValueKind.Array)
        {
            foreach (var notification in valueProp.EnumerateArray())
            {
                if (notification.TryGetProperty("resourceData", out var rd) &&
                    rd.TryGetProperty("userPrincipalName", out var rdUpn))
                {
                    var u = rdUpn.GetString();
                    if (!string.IsNullOrEmpty(u)) upns.Add(u);
                }
            }
        }

        // Format 3: Entra Audit Log { "records": [ { "properties": { "targetResources": [ { "userPrincipalName": "..." } ] } } ] }
        if (doc.RootElement.TryGetProperty("records", out var records) && records.ValueKind == JsonValueKind.Array)
        {
            foreach (var record in records.EnumerateArray())
            {
                if (record.TryGetProperty("properties", out var props) &&
                    props.TryGetProperty("targetResources", out var targets) &&
                    targets.ValueKind == JsonValueKind.Array)
                {
                    foreach (var target in targets.EnumerateArray())
                    {
                        if (target.TryGetProperty("userPrincipalName", out var tUpn))
                        {
                            var u = tUpn.GetString();
                            if (!string.IsNullOrEmpty(u)) upns.Add(u);
                        }
                    }
                }
            }
        }

        return upns;
    }
}
