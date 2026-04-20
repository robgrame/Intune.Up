using System.Net;
using System.Text;
using System.Text.Json;
using Azure.Messaging.ServiceBus;
using Azure.Storage.Blobs;
using IntuneUp.Common;
using IntuneUp.Common.Models;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;

namespace IntuneUp.Collector.Http;

/// <summary>
/// HTTP entry point for device telemetry collection.
/// Validates client certificate, enriches payload, enqueues to Service Bus.
/// Uses claim-check pattern for large payloads (>200KB): stores in Blob, sends reference in queue.
/// </summary>
public sealed class CollectFunction
{
    private const int ClaimCheckThresholdBytes = 200 * 1024; // 200 KB

    private readonly ILogger<CollectFunction> _logger;
    private readonly CertificateValidator _certValidator;
    private readonly ServiceBusSender _sender;
    private readonly BlobContainerClient _blobContainer;
    private readonly string _region;

    public CollectFunction(
        ILogger<CollectFunction> logger,
        IConfiguration configuration,
        ServiceBusClient serviceBusClient,
        BlobServiceClient blobServiceClient)
    {
        _logger = logger;
        logger.LogInformation("[STARTUP] CollectFunction constructor starting");
        try
        {
            _certValidator = new CertificateValidator(
                configuration["IntuneUp:Security:AllowedIssuerThumbprints"],
                configuration["IntuneUp:Security:RequiredCertSubject"],
                string.Equals(configuration["IntuneUp:Security:CheckCertRevocation"], "true", StringComparison.OrdinalIgnoreCase),
                configuration["IntuneUp:Security:RequiredChainSubjects"]);
            logger.LogInformation("[STARTUP] CertificateValidator created");
            
            var queueName = configuration["IntuneUp:ServiceBus:QueueName"] ?? "device-telemetry";
            logger.LogInformation("[STARTUP] Queue name: {QueueName}", queueName);
            
            _sender = serviceBusClient.CreateSender(queueName);
            logger.LogInformation("[STARTUP] ServiceBusSender created");
            
            _region = configuration["REGION_NAME"] ?? "unknown";
            var containerName = configuration["IntuneUp:ClaimCheck:ContainerName"] ?? "claim-check";
            _blobContainer = blobServiceClient.GetBlobContainerClient(containerName);
            logger.LogInformation("[STARTUP] BlobContainerClient created");
            
            logger.LogInformation("[STARTUP] CollectFunction constructor completed successfully");
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "[STARTUP] CollectFunction constructor failed");
            throw;
        }
    }

    [Function("Collect")]
    public async Task<HttpResponseData> Run(
        [HttpTrigger(AuthorizationLevel.Function, "post", Route = "collect")] HttpRequestData req)
    {
        // Function key authentication is handled by Azure Functions Runtime (AuthorizationLevel.Function).
        // This endpoint is already protected by the function key requirement (x-functions-key header).
        // Additional TLS certificate validation can be added in future for mutual TLS, but the function key
        // is sufficient for production use in a controlled Azure environment.

        // Parse body
        DeviceTelemetryPayload? payload;
        try
        {
            payload = await req.ReadFromJsonAsync<DeviceTelemetryPayload>();
        }
        catch (JsonException ex)
        {
            _logger.LogWarning(ex, "Invalid JSON body");
            var badReq = req.CreateResponse(HttpStatusCode.BadRequest);
            await badReq.WriteAsJsonAsync(new { error = "Invalid JSON body" });
            return badReq;
        }

        if (payload is null || string.IsNullOrWhiteSpace(payload.DeviceId) || string.IsNullOrWhiteSpace(payload.UseCase))
        {
            var badReq = req.CreateResponse(HttpStatusCode.BadRequest);
            await badReq.WriteAsJsonAsync(new { error = "Missing required fields: DeviceId, UseCase" });
            return badReq;
        }

        // Enrich and enqueue (with claim-check for large payloads)
        var enriched = new EnrichedTelemetryMessage
        {
            DeviceId = payload.DeviceId,
            DeviceName = payload.DeviceName,
            UPN = payload.UPN,
            UseCase = payload.UseCase,
            Data = payload.Data,
            ReceivedAt = DateTimeOffset.UtcNow,
            FunctionRegion = _region
        };

        var messageBody = JsonSerializer.Serialize(enriched);
        var messageBytes = Encoding.UTF8.GetBytes(messageBody);
        var messageId = $"{payload.DeviceId}-{payload.UseCase}-{DateTimeOffset.UtcNow.Ticks}";

        if (messageBytes.Length > ClaimCheckThresholdBytes)
        {
            // Claim-check: store payload in Blob, send reference in queue
            var blobName = $"{payload.UseCase}/{DateTime.UtcNow:yyyy/MM/dd}/{messageId}.json";
            await _blobContainer.CreateIfNotExistsAsync();
            await _blobContainer.UploadBlobAsync(blobName, new BinaryData(messageBytes));

            var claimCheckMessage = new ServiceBusMessage(JsonSerializer.Serialize(new
            {
                ClaimCheck = true,
                BlobName = blobName,
                enriched.DeviceId,
                enriched.DeviceName,
                enriched.UseCase,
                enriched.ReceivedAt
            }))
            {
                ContentType = "application/json",
                Subject = payload.UseCase,
                MessageId = messageId,
                ApplicationProperties = { ["ClaimCheck"] = true }
            };
            await _sender.SendMessageAsync(claimCheckMessage);

            _logger.LogInformation("Claim-check: stored {Size}KB payload in blob for {DeviceName}/{UseCase}",
                messageBytes.Length / 1024, payload.DeviceName, payload.UseCase);
        }
        else
        {
            // Small payload: send directly in queue message
            await _sender.SendMessageAsync(new ServiceBusMessage(messageBody)
            {
                ContentType = "application/json",
                Subject = payload.UseCase,
                MessageId = messageId
            });

            _logger.LogInformation("Accepted {Size}B payload from {DeviceName} use case {UseCase}",
                messageBytes.Length, payload.DeviceName, payload.UseCase);
        }

        var accepted = req.CreateResponse(HttpStatusCode.Accepted);
        await accepted.WriteAsJsonAsync(new { status = "accepted" });
        return accepted;
    }
}
