using System.Text.Json;
using Azure.Monitor.Ingestion;
using Azure.Messaging.ServiceBus;
using Azure.Storage.Blobs;
using IntuneUp.Common.Models;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;

namespace IntuneUp.Collector.ServiceBus;

/// <summary>
/// Processes messages from the Service Bus queue and writes to Log Analytics
/// via the Logs Ingestion API (DCE + DCR, Entra ID authentication).
/// Supports claim-check pattern: if message has ClaimCheck property, fetches payload from Blob Storage.
/// </summary>
public sealed class ProcessorFunction
{
    private readonly ILogger<ProcessorFunction> _logger;
    private readonly LogsIngestionClient _logsIngestionClient;
    private readonly BlobContainerClient _blobContainer;
    private readonly IConfiguration _configuration;
    private readonly string _dcrImmutableId;
    private readonly string _tablePrefix;

    public ProcessorFunction(
        ILogger<ProcessorFunction> logger,
        LogsIngestionClient logsIngestionClient,
        BlobServiceClient blobServiceClient,
        IConfiguration configuration)
    {
        _logger = logger;
        _logsIngestionClient = logsIngestionClient;
        _configuration = configuration;
        _dcrImmutableId = configuration["IntuneUp:LogAnalytics:DcrImmutableId"] ?? throw new InvalidOperationException("IntuneUp:LogAnalytics:DcrImmutableId not set");
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

        // Build custom table name: IntuneUp_BitLockerStatus_CL
        var sanitizedUseCase = new string(payload.UseCase
            .Where(c => char.IsLetterOrDigit(c) || c == '_')
            .ToArray());
        var tableName = $"{_tablePrefix}_{sanitizedUseCase}_CL";
        var streamName = $"Custom-{tableName}";

        // Allow per-use-case DCR override; fall back to the default DCR
        var dcrId = _configuration[$"IntuneUp:LogAnalytics:Dcr:{sanitizedUseCase}:ImmutableId"]
            ?? _dcrImmutableId;

        // Build the log record — Data is stored as a dynamic column so the
        // DCR schema stays generic across all use cases.
        var record = new Dictionary<string, object?>
        {
            ["DeviceId"] = payload.DeviceId,
            ["DeviceName"] = payload.DeviceName,
            ["UPN"] = payload.UPN,
            ["UseCase"] = payload.UseCase,
            ["ReceivedAt"] = payload.ReceivedAt.ToString("o"),
            ["FunctionRegion"] = payload.FunctionRegion,
            ["Data"] = payload.Data
        };

        var result = await _logsIngestionClient.UploadAsync(dcrId, streamName, new[] { record });

        if (result.IsError)
        {
            _logger.LogError("Logs Ingestion API: upload failed with status {Status} for table {TableName}", result.Status, tableName);
            throw new InvalidOperationException($"Logs Ingestion API returned error status {result.Status} for table {tableName}");
        }

        _logger.LogInformation("Written to Log Analytics table {TableName} for device {DeviceName}", tableName, payload.DeviceName);
    }
}
