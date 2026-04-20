using System.Net;
using System.Text.Json;
using IntuneUp.Common.Models;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;

namespace IntuneUp.Collector.Http;

/// <summary>
/// HTTP entry point for device telemetry collection - MINIMAL TEST VERSION
/// </summary>
public sealed class CollectFunction
{
    private const int ClaimCheckThresholdBytes = 200 * 1024;

    private readonly ILogger<CollectFunction> _logger;

    public CollectFunction(ILogger<CollectFunction> logger)
    {
        _logger = logger;
        _logger.LogInformation("[STARTUP] CollectFunction minimal constructor created");
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

        // Return success
        var accepted = req.CreateResponse(HttpStatusCode.Accepted);
        await accepted.WriteAsJsonAsync(new { status = "accepted", deviceId = payload.DeviceId });
        return accepted;
    }
}
