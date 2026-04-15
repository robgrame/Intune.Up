using System.Net;
using System.Text.Json;
using Azure.Messaging.ServiceBus;
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
/// </summary>
public sealed class CollectFunction
{
    private readonly ILogger<CollectFunction> _logger;
    private readonly CertificateValidator _certValidator;
    private readonly ServiceBusSender _sender;
    private readonly string _region;

    public CollectFunction(
        ILogger<CollectFunction> logger,
        IConfiguration configuration,
        ServiceBusClient serviceBusClient)
    {
        _logger = logger;
        _certValidator = new CertificateValidator(
            configuration["ALLOWED_ISSUER_THUMBPRINTS"],
            configuration["REQUIRED_CERT_SUBJECT"],
            string.Equals(configuration["CHECK_CERT_REVOCATION"], "true", StringComparison.OrdinalIgnoreCase));
        var queueName = configuration["SERVICEBUS_QUEUE_NAME"] ?? "device-telemetry";
        _sender = serviceBusClient.CreateSender(queueName);
        _region = configuration["REGION_NAME"] ?? "unknown";
    }

    [Function("Collect")]
    public async Task<HttpResponseData> Run(
        [HttpTrigger(AuthorizationLevel.Function, "post", Route = "collect")] HttpRequestData req)
    {
        // Validate client certificate
        // App Service mutual TLS populates X-ARR-ClientCert with the base64-encoded cert.
        // We validate that it was issued by a trusted CA (issuer thumbprint in chain).
        bool certValid = false;
        var arrCert = req.Headers.TryGetValues("X-ARR-ClientCert", out var certValues)
            ? certValues.FirstOrDefault()
            : null;

        if (!string.IsNullOrEmpty(arrCert))
        {
            try
            {
                var certBytes = Convert.FromBase64String(arrCert);
                var cert = System.Security.Cryptography.X509Certificates.X509CertificateLoader.LoadCertificate(certBytes);
                var result = _certValidator.Validate(cert);
                certValid = result.Valid;
                if (!certValid)
                    _logger.LogWarning("Certificate rejected: {Reason}", result.Reason);
                else
                    _logger.LogDebug("Certificate accepted: {Thumbprint} {Subject}", result.Thumbprint, result.Subject);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to parse X-ARR-ClientCert");
            }
        }
        else
        {
            _logger.LogWarning("Rejected - no client certificate provided");
        }

        if (!certValid)
        {
            var unauthorized = req.CreateResponse(HttpStatusCode.Unauthorized);
            await unauthorized.WriteAsJsonAsync(new { error = "Unauthorized - valid client certificate required" });
            return unauthorized;
        }

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

        // Enrich and enqueue
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
        await _sender.SendMessageAsync(new ServiceBusMessage(messageBody)
        {
            ContentType = "application/json",
            Subject = payload.UseCase,
            MessageId = $"{payload.DeviceId}-{payload.UseCase}-{DateTimeOffset.UtcNow.Ticks}"
        });

        _logger.LogInformation("Accepted payload from {DeviceName} use case {UseCase}", payload.DeviceName, payload.UseCase);

        var accepted = req.CreateResponse(HttpStatusCode.Accepted);
        await accepted.WriteAsJsonAsync(new { status = "accepted" });
        return accepted;
    }
}
