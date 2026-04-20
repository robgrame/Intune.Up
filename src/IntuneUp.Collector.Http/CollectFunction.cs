using System.Net;
using System.Text.Json;
using Azure.Messaging.ServiceBus;
using IntuneUp.Common.Models;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;

namespace IntuneUp.Collector.Http;

/// <summary>
/// HTTP entry point for device telemetry collection - with Service Bus integration
/// </summary>
public sealed class CollectFunction
{
    private const int ClaimCheckThresholdBytes = 200 * 1024;

    private readonly ILogger<CollectFunction> _logger;
    private readonly ServiceBusClient _serviceBusClient;
    private readonly IConfiguration _configuration;

    public CollectFunction(ILogger<CollectFunction> logger, ServiceBusClient serviceBusClient, IConfiguration configuration)
    {
        _logger = logger;
        _serviceBusClient = serviceBusClient;
        _configuration = configuration;
        _logger.LogInformation("[STARTUP] CollectFunction constructor created with Service Bus");
    }

    [Function("Collect")]
    public async Task<HttpResponseData> Run(
        [HttpTrigger(AuthorizationLevel.Function, "post", Route = "collect")] HttpRequestData req)
    {
        _logger.LogInformation("[REQUEST] Collect endpoint called");
        
        // Parse body
        DeviceTelemetryPayload? payload = await req.ReadFromJsonAsync<DeviceTelemetryPayload>();

        if (payload is null || string.IsNullOrWhiteSpace(payload.DeviceId) || string.IsNullOrWhiteSpace(payload.UseCase))
        {
            var badReq = req.CreateResponse(HttpStatusCode.BadRequest);
            await badReq.WriteAsJsonAsync(new { error = "Missing required fields: DeviceId, UseCase" });
            return badReq;
        }

        _logger.LogInformation("[REQUEST] Valid payload received: {DeviceId}/{UseCase}", payload.DeviceId, payload.UseCase);

        try
        {
            // Enrich payload
            var enriched = new EnrichedTelemetryMessage
            {
                DeviceId = payload.DeviceId,
                DeviceName = payload.DeviceName ?? "UNKNOWN",
                UseCase = payload.UseCase,
                ReceivedAt = DateTime.UtcNow,
                FunctionRegion = Environment.GetEnvironmentVariable("REGION_NAME") ?? "unknown",
                Data = payload.Data
            };

            // Send to Service Bus
            var queueName = _configuration["IntuneUp:ServiceBus:QueueName"] ?? "device-telemetry";
            var sender = _serviceBusClient.CreateSender(queueName);
            
            var jsonBody = JsonSerializer.Serialize(enriched);
            var message = new ServiceBusMessage(jsonBody)
            {
                ContentType = "application/json",
                Subject = payload.UseCase
            };

            await sender.SendMessageAsync(message);
            _logger.LogInformation("[SERVICE_BUS] Message enqueued to {QueueName}: {MessageId}", queueName, message.MessageId);

            // Return success
            var accepted = req.CreateResponse(HttpStatusCode.Accepted);
            await accepted.WriteAsJsonAsync(new { status = "accepted", deviceId = payload.DeviceId, messageId = message.MessageId });
            return accepted;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "[ERROR] Failed to process request: {Message}", ex.Message);
            var errorRes = req.CreateResponse(HttpStatusCode.InternalServerError);
            await errorRes.WriteAsJsonAsync(new { error = "Internal server error" });
            return errorRes;
        }
    }
}
