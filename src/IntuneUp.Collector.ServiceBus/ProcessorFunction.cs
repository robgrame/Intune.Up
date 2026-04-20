using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Azure.Messaging.ServiceBus;
using Azure.Storage.Blobs;
using IntuneUp.Common.Models;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;

namespace IntuneUp.Collector.ServiceBus;

/// <summary>
/// Processes messages from the Service Bus queue and writes to Log Analytics.
/// Supports claim-check pattern: if message has ClaimCheck property, fetches payload from Blob Storage.
/// </summary>
public sealed class ProcessorFunction
{
    private readonly ILogger<ProcessorFunction> _logger;
    private readonly IHttpClientFactory _httpClientFactory;
    private readonly BlobContainerClient _blobContainer;
    private readonly string _workspaceId;
    private readonly string _sharedKey;
    private readonly string _tablePrefix;

    public ProcessorFunction(
        ILogger<ProcessorFunction> logger,
        IHttpClientFactory httpClientFactory,
        BlobServiceClient blobServiceClient,
        IConfiguration configuration)
    {
        _logger = logger;
        _httpClientFactory = httpClientFactory;
        _workspaceId = configuration["IntuneUp:LogAnalytics:WorkspaceId"] ?? throw new InvalidOperationException("IntuneUp:LogAnalytics:WorkspaceId not set");
        _sharedKey = configuration["IntuneUp:LogAnalytics:SharedKey"] ?? throw new InvalidOperationException("IntuneUp:LogAnalytics:SharedKey not set");
        _tablePrefix = configuration["IntuneUp:LogAnalytics:TablePrefix"] ?? "IntuneUp";
        var containerName = configuration["IntuneUp:ClaimCheck:ContainerName"] ?? "claim-check";
        _blobContainer = blobServiceClient.GetBlobContainerClient(containerName);
    }

    [Function("Processor")]
    public async Task Run(
        [ServiceBusTrigger("%ServiceBusQueueName%", Connection = "ServiceBusConnection")]
        ServiceBusReceivedMessage message)
    {
        EnrichedTelemetryMessage? payload;

        // Claim-check: fetch full payload from Blob Storage if flagged
        if (message.ApplicationProperties.TryGetValue("ClaimCheck", out var claimCheck) && claimCheck is true)
        {
            var claimRef = JsonSerializer.Deserialize<JsonElement>(message.Body);
            var blobName = claimRef.GetProperty("BlobName").GetString()
                ?? throw new InvalidOperationException("ClaimCheck message missing BlobName");

            var blobClient = _blobContainer.GetBlobClient(blobName);
            var download = await blobClient.DownloadContentAsync();
            payload = JsonSerializer.Deserialize<EnrichedTelemetryMessage>(download.Value.Content);

            _logger.LogInformation("Claim-check: fetched {BlobName} ({Size}KB)", blobName, download.Value.Content.ToMemory().Length / 1024);

            // Cleanup blob after processing
            await blobClient.DeleteIfExistsAsync();
        }
        else
        {
            payload = JsonSerializer.Deserialize<EnrichedTelemetryMessage>(message.Body);
        }

        if (payload is null)
        {
            _logger.LogError("Failed to deserialize message {MessageId}", message.MessageId);
            throw new InvalidOperationException("Invalid message payload");
        }

        // Build Log Analytics table name: IntuneUp_BitLockerStatus
        var sanitizedUseCase = new string(payload.UseCase
            .Where(c => char.IsLetterOrDigit(c) || c == '_')
            .ToArray());
        var logType = $"{_tablePrefix}_{sanitizedUseCase}";

        // Flatten: merge Data fields into the top-level record
        var record = new Dictionary<string, object?>
        {
            ["DeviceId"] = payload.DeviceId,
            ["DeviceName"] = payload.DeviceName,
            ["UPN"] = payload.UPN,
            ["UseCase"] = payload.UseCase,
            ["ReceivedAt"] = payload.ReceivedAt.ToString("o"),
            ["FunctionRegion"] = payload.FunctionRegion
        };

        if (payload.Data is not null)
        {
            foreach (var kvp in payload.Data)
                record[kvp.Key] = kvp.Value;
        }

        var jsonBody = JsonSerializer.Serialize(new[] { record });
        await SendToLogAnalyticsAsync(logType, jsonBody);

        _logger.LogInformation("Written to Log Analytics table {LogType} for device {DeviceName}", logType, payload.DeviceName);
    }

    private async Task SendToLogAnalyticsAsync(string logType, string jsonBody)
    {
        var date = DateTime.UtcNow.ToString("r");
        var bodyBytes = Encoding.UTF8.GetBytes(jsonBody);
        var contentLength = bodyBytes.Length;

        var stringToHash = $"POST\n{contentLength}\napplication/json\nx-ms-date:{date}\n/api/logs";
        var keyBytes = Convert.FromBase64String(_sharedKey);
        var hashBytes = HMACSHA256.HashData(keyBytes, Encoding.UTF8.GetBytes(stringToHash));
        var signature = Convert.ToBase64String(hashBytes);
        var authorization = $"SharedKey {_workspaceId}:{signature}";

        var uri = $"https://{_workspaceId}.ods.opinsights.azure.com/api/logs?api-version=2016-04-01";

        var client = _httpClientFactory.CreateClient("LogAnalytics");
        using var request = new HttpRequestMessage(HttpMethod.Post, uri);
        request.Content = new ByteArrayContent(bodyBytes);
        request.Content.Headers.ContentType = new MediaTypeHeaderValue("application/json");
        request.Headers.Add("Authorization", authorization);
        request.Headers.Add("Log-Type", logType);
        request.Headers.Add("x-ms-date", date);
        request.Headers.Add("time-generated-field", "ReceivedAt");

        var response = await client.SendAsync(request);
        response.EnsureSuccessStatusCode();
    }
}
