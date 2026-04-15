using System.Net;
using Azure.Data.Tables;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;

namespace IntuneUp.Collector.Http;

/// <summary>
/// Endpoint for clients to check if a user's password is expiring.
/// Called by detect.ps1 on endpoints: GET /api/password-expiry?upn=user@domain.com
/// Reads from Azure Table Storage (populated by server-side Runbook).
/// </summary>
public sealed class PasswordExpiryFunction
{
    private readonly ILogger<PasswordExpiryFunction> _logger;
    private readonly TableClient _tableClient;

    public PasswordExpiryFunction(
        ILogger<PasswordExpiryFunction> logger,
        TableServiceClient tableServiceClient,
        IConfiguration configuration)
    {
        _logger = logger;
        var tableName = configuration["IntuneUp:PasswordExpiry:TableName"] ?? "PasswordExpiry";
        _tableClient = tableServiceClient.GetTableClient(tableName);
    }

    [Function("PasswordExpiry")]
    public async Task<HttpResponseData> Run(
        [HttpTrigger(AuthorizationLevel.Function, "get", Route = "password-expiry")]
        HttpRequestData req)
    {
        var query = System.Web.HttpUtility.ParseQueryString(req.Url.Query);
        var upn = query["upn"];

        if (string.IsNullOrWhiteSpace(upn))
        {
            var badReq = req.CreateResponse(HttpStatusCode.BadRequest);
            await badReq.WriteAsJsonAsync(new { error = "Missing required parameter: upn" });
            return badReq;
        }

        try
        {
            var entity = await _tableClient.GetEntityIfExistsAsync<TableEntity>(
                "PasswordExpiry", upn.ToLowerInvariant());

            if (!entity.HasValue)
            {
                var notFound = req.CreateResponse(HttpStatusCode.OK);
                await notFound.WriteAsJsonAsync(new { Expiring = false });
                return notFound;
            }

            var record = entity.Value!;
            var daysUntilExpiry = record.GetInt32("DaysUntilExpiry") ?? -1;
            var expiryDate = record.GetString("ExpiryDate") ?? "";

            var ok = req.CreateResponse(HttpStatusCode.OK);
            await ok.WriteAsJsonAsync(new
            {
                Expiring = true,
                DaysUntilExpiry = daysUntilExpiry,
                ExpiryDate = expiryDate,
                UserUPN = upn
            });

            _logger.LogInformation("Password expiry check for {UPN}: {Days} days", upn, daysUntilExpiry);
            return ok;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to query password expiry for {UPN}", upn);
            var error = req.CreateResponse(HttpStatusCode.InternalServerError);
            await error.WriteAsJsonAsync(new { error = "Internal error" });
            return error;
        }
    }
}
