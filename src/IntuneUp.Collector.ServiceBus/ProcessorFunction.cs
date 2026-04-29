using System.Text.Json;
using Azure;
using Azure.Core;
using Azure.Identity;
using Azure.Monitor.Ingestion;
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
    private readonly BlobContainerClient _blobContainer;
    private readonly LogsIngestionClient _logsIngestionClient;
    private readonly string _dcrImmutableId;
    private readonly string _streamName;
    private readonly string _tablePrefix;

    public ProcessorFunction(
        ILogger<ProcessorFunction> logger,
        BlobServiceClient blobServiceClient,
        IConfiguration configuration)
    {
        _logger = logger;
        var dceUri = configuration["IntuneUp:LogsIngestion:DceUri"] ?? throw new InvalidOperationException("IntuneUp:LogsIngestion:DceUri not set");
        _dcrImmutableId = configuration["IntuneUp:LogsIngestion:DcrImmutableId"] ?? throw new InvalidOperationException("IntuneUp:LogsIngestion:DcrImmutableId not set");
        _streamName = configuration["IntuneUp:LogsIngestion:StreamName"] ?? "Custom-IntuneUp";
        _tablePrefix = configuration["IntuneUp:LogAnalytics:TablePrefix"] ?? "IntuneUp";

        TokenCredential credential = new DefaultAzureCredential();
        _logsIngestionClient = new LogsIngestionClient(new Uri(dceUri), credential);
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

        await UploadToLogsIngestionAsync(logType, record);

        _logger.LogInformation("Written to Log Analytics table {LogType} for device {DeviceName}", logType, payload.DeviceName);
    }

    private async Task UploadToLogsIngestionAsync(string logType, Dictionary<string, object?> record)
    {
        record["LogType"] = logType;

        try
        {
            Response response = await _logsIngestionClient.UploadAsync(
                ruleId: _dcrImmutableId,
                streamName: _streamName,
                logs: new[] { record });

            _logger.LogDebug("Logs ingestion upload status: {Status}", response.Status);
        }
        catch (RequestFailedException ex)
        {
            _logger.LogError(ex, "Failed uploading logs via Logs Ingestion API. DCR={DcrImmutableId} Stream={StreamName}", _dcrImmutableId, _streamName);
            throw;
        }
    }
}
